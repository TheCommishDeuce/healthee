/// Account & server — `H.screens.account`, carrying the real sign-in.
///
/// ```js
/// H.screens.account = () => `${H.header('Your data. Your space.','Account & server',true)}
///   <div class="card"><div class="row">${H.icon('shield')}<h3>A private connection</h3></div>
///     <p class="small section">…</p></div>
///   <form id="server-form" class="section"><label class="field">Server address…</label>
///     <button class="button secondary full">Test sample connection</button></form>
///   <div class="card flush section">${two rows}</div>
///   ${H.footer()}`;
/// ```
///
/// ## One surface, not two
///
/// The prototype has an `account` screen with an address field and a separate
/// `welcome` screen that links to it. This product already had a real sign-in
/// screen at `/server`, reached from Settings and from Today's data-health
/// section. Building the prototype's account screen as a *second* place to type
/// a server address would be two doors onto one keystore write — the shape
/// `server_setting.dart` was deleted for. So this screen **is** the account
/// screen, and the settings row points at it.
///
/// ## This screen is a destination, never a gate
///
/// Nothing redirects here. **Strap-only is a supported mode**: the whole
/// measured half of Today comes off this phone's own store and renders with no
/// network at all, and a sign-in wall in front of it would take the owner's own
/// measurements away until they satisfied a server.
///
/// ## The address is shown; the token is not, ever
///
/// `server_session_card.dart` argues it: a stored secret with no consumer must
/// not acquire one just so it can be rendered into a screenshot and an
/// accessibility tree. `test/signin/signin_secrecy_test.dart` executes the
/// claim rather than trusting this comment.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/env.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/auth/enrollment_link.dart';
import 'package:healthee/data/auth/identity_providers.dart';
import 'package:healthee/features/signin/server_signin_controller.dart';
import 'package:healthee/features/signin/widgets/enrollment_entry.dart';
import 'package:healthee/features/signin/widgets/server_session_card.dart';
import 'package:healthee/features/signin/widgets/server_signin_form.dart';
import 'package:healthee/features/signin/widgets/signin_failure_card.dart';
import 'package:healthee/features/signin/widgets/token_signin_form.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/list_row.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// Sign in to the Healthee server, or review the session already held.
class ServerSignInScreen extends ConsumerWidget {
  /// [onDone] is the route back into the app. Null in tests.
  const ServerSignInScreen({this.onDone, super.key});

  /// The prototype's own h1.
  static const String title = 'Your data. Your space.';

  /// Its eyebrow.
  static const String eyebrow = 'Account & server';

  /// The prototype's own promise, made true: this app contacts the server the
  /// owner named and nothing else.
  static const String privacy =
      'Your health history belongs on the server you choose. Healthee talks to '
      'that address and to your strap, and to nothing else.';

  /// `.card .row { gap: 12px }` and `.section { margin-top: 24px }`.
  static const double rowGap = 12;

  /// Called after a sign-in lands.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return SettingsPage(
      title: title,
      eyebrow: eyebrow,
      children: <Widget>[
        PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(SolarIconsOutline.shieldCheck, color: colors.accent),
                  const SizedBox(width: rowGap),
                  Expanded(
                    child: Text(
                      'A private connection',
                      style: FormType.heading3.copyWith(color: colors.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SectionGap.height),
              const SmallProse(privacy),
            ],
          ),
        ),
        const SectionGap(),
        AsyncView<ServerSessionStatus>(
          value: ref.watch(serverSessionProvider),
          onRetry: () => ref.invalidate(serverSessionProvider),
          loadingLabel: 'Checking what is already signed in',
          errorMessage: "Couldn't read this phone's keystore",
          builder: (context, session) =>
              _SignInBody(session: session, onDone: onDone),
        ),
        const SectionGap(),
        FlushCard(
          children: <Widget>[
            ListRow(
              icon: SolarIconsOutline.userCircle,
              title: 'How this app signs in',
              subtitle: 'Welcome and account connection',
              onTap: () => unawaited(context.push(Routes.welcome)),
            ),
            ListRow(
              icon: SolarIconsOutline.shieldCheck,
              title: 'Your data & privacy',
              subtitle: 'What stays local and what is uploaded',
              onTap: () => unawaited(context.push(Routes.about)),
            ),
          ],
        ),
        const DataFooter(),
      ],
    );
  }
}

class _SignInBody extends ConsumerStatefulWidget {
  const _SignInBody({required this.session, required this.onDone});

  final ServerSessionStatus session;
  final VoidCallback? onDone;

  @override
  ConsumerState<_SignInBody> createState() => _SignInBodyState();
}

/// What the address field starts with when nothing is stored.
///
/// ⛔ **Empty on a build with no server compiled in**, which since the app started
/// discovering its identity provider is the normal case: a published APK is aimed
/// at nobody. `Env.apiBaseUrl` then falls back to `http://127.0.0.1:8765`, and
/// prefilling THAT is showing somebody an answer we do not have — a real-looking
/// address that is wrong for everyone who did not build the app, sitting in a
/// field above a button. An empty field with a hint asks the question instead.
///
/// A build that WAS given `HELIO_API` still prefills it: there the address is a
/// fact about the build rather than a guess about the reader.
String get _suggestedAddress => Env.isUsingFallbackApi ? '' : Env.apiBaseUrl;

class _SignInBodyState extends ConsumerState<_SignInBody> {
  @override
  void initState() {
    super.initState();
    unawaited(_readKnownEmail());
  }

  /// Fills [_knownEmail] from the keystore, if the strap has ever been paired.
  Future<void> _readKnownEmail() async {
    final email = await ref.read(credentialsProvider).zeppEmail();
    if (!mounted || email == null || email.isEmpty) {
      return;
    }
    setState(() => _knownEmail = email);
  }

  /// True once the owner has asked to point at a different server, so the form
  /// replaces the summary without the session having been cleared first.
  bool _replacing = false;

  /// The Zepp account's email, once read, so the form can prefill it.
  ///
  /// Read here rather than through `rememberedZeppAccount()`, which returns the
  /// password beside it: this screen has no use for that password and pulling it
  /// into memory to ignore it is how a secret ends up somewhere it was never
  /// needed. One key, one read.
  String? _knownEmail;

  /// True once the owner has asked for the ⛔ transitional pasted-token form.
  ///
  /// Not a preference and not remembered: it lasts as long as this screen. The
  /// path exists for an owner mid-migration and for a build with no identity
  /// provider, and neither is a state to make comfortable.
  bool _pastingToken = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverSignInControllerProvider);
    final controller = ref.read(serverSignInControllerProvider.notifier);
    final session = widget.session;
    final hasIdentity = ref.watch(identityAvailableProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!session.signedIn || _replacing) ...<Widget>[
          EnrollmentEntry(
            enabled: !state.isBusy,
            onEdited: controller.clearFailure,
            onEnroll: (link) => unawaited(_enroll(link)),
          ),
          const SectionGap(),
        ],
        if (session.signedIn && !_replacing)
          ServerSessionCard(
            baseUrl: session.baseUrl!,
            enabled: !state.isBusy,
            onSignOut: () => unawaited(controller.signOut()),
            onReplace: () => setState(() => _replacing = true),
          )
        // The stored server when there is one, so "use a different server"
        // starts from what is actually in use rather than from the build's
        // compiled-in default.
        else if (_pastingToken || !hasIdentity)
          TokenSignInForm(
            initialUrl: session.baseUrl ?? _suggestedAddress,
            enabled: !state.isBusy,
            onEdited: controller.clearFailure,
            configured: hasIdentity,
            onUsePassword: hasIdentity
                ? () => setState(() => _pastingToken = false)
                : null,
            onSubmit: (url, token) =>
                unawaited(_submitToken(url: url, token: token)),
          )
        else
          ServerSignInForm(
            initialUrl: session.baseUrl ?? _suggestedAddress,
            enabled: !state.isBusy,
            onEdited: controller.clearFailure,
            onUseToken: () => setState(() => _pastingToken = true),
            // The Zepp email when the strap is paired — the owner typed it on
            // this phone already. Never the Zepp password: see the form.
            initialEmail: _knownEmail,
            onSubmit: (url, email, password, {required create}) => unawaited(
              _submit(
                url: url,
                email: email,
                password: password,
                create: create,
              ),
            ),
          ),
        if (state.failure case final failure?) ...<Widget>[
          const SectionGap(),
          SignInFailureCard(failure: failure, onRetry: controller.clearFailure),
        ],
        if (state.isBusy) ...<Widget>[
          const SectionGap(),
          LoadingState(label: state.busyLabel),
        ],
      ],
    );
  }

  /// Runs the sign-in and leaves only if it landed.
  Future<void> _submit({
    required String url,
    required String email,
    required String password,
    required bool create,
  }) async {
    final controller = ref.read(serverSignInControllerProvider.notifier);
    await _land(
      create
          ? await controller.createAccount(
              url: url,
              email: email,
              password: password,
            )
          : await controller.signIn(url: url, email: email, password: password),
    );
  }

  /// The QR enrollment path (`docs/QR_ENROLLMENT.md`).
  Future<void> _enroll(EnrollmentLink link) async {
    final controller = ref.read(serverSignInControllerProvider.notifier);
    await _land(await controller.enroll(link));
  }

  /// ⛔ TRANSITIONAL — the pasted-token path. See `data/api/server_session.dart`.
  Future<void> _submitToken({
    required String url,
    required String token,
  }) async {
    final controller = ref.read(serverSignInControllerProvider.notifier);
    await _land(await controller.signInWithToken(url: url, token: token));
  }

  /// Leaves only if the sign-in landed.
  ///
  /// The `mounted` guard is not ceremony: a sign-in is up to three network
  /// round trips and this screen can be popped while they are in flight.
  Future<void> _land(bool signedIn) async {
    if (!signedIn || !mounted) {
      return;
    }
    setState(() {
      _replacing = false;
      _pastingToken = false;
    });
    widget.onDone?.call();
  }
}
