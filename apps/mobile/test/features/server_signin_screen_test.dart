/// The sign-in screen, outcome by outcome.
///
/// The bar is Standards §3's — loading, error-with-retry and empty all render,
/// and no state is a blank card — plus this product's own rule that every
/// failure names itself and offers a way forward.
///
/// The assertions are against **rendered text**, not against the model. The
/// model being right and the screen dropping it is precisely the failure this
/// work package is repairing one layer down: the taxonomy in `signin_failure`
/// is worth nothing if the owner still reads "couldn't reach the server" when
/// the token was refused.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/auth/identity_providers.dart';
import 'package:healthee/features/signin/server_signin_screen.dart';
import 'package:healthee/features/signin/widgets/token_signin_form.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

import '../pairing/_pairing_fakes.dart';
import '../signin/_signin_fakes.dart';

const String _url = 'https://healthee.example.com';

/// The screen under a build with NO identity provider, which is what these
/// cases are about: the transitional pasted-token path, and the three async
/// states around it. `identityAvailableProvider` is overridden rather than left
/// to `Env` so this is a decision the test makes, not one the absence of a
/// dart-define makes for it.
Widget _host(
  FakeSecretStore store,
  ScriptedServer server, {
  bool identity = false,
}) {
  return ProviderScope(
    overrides: [
      credentialsProvider.overrideWithValue(Credentials(store)),
      identityAvailableProvider.overrideWithValue(identity),
      serverSessionRepositoryProvider.overrideWithValue(
        repositoryWith(store, server),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const ServerSignInScreen(),
    ),
  );
}

/// Pumps [app] into a viewport tall enough to hit-test the whole screen.
///
/// v02 draws the form inside one scrolling page under a detail header, so the
/// submit button sits below the default 800x600 window's fold — and a tap on a
/// widget that is built but off-screen misses SILENTLY, which reads here as
/// "the 200 outcome renders nothing". What these tests assert is which sentence
/// each outcome produces, never what fits above the fold.
Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view
    ..physicalSize = const Size(420, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

/// The token form's own fields — the enrollment card above it has one too.
Finder get _formFields => find.descendant(
  of: find.byType(TokenSignInForm),
  matching: find.byType(TextField),
);

/// Fills both fields and submits.
Future<void> _submit(
  WidgetTester tester, {
  String url = _url,
  String token = kSentinelToken,
}) async {
  await tester.enterText(_formFields.first, url);
  await tester.enterText(_formFields.last, token);
  await tester.tap(find.text('Check and sign in'));
  await tester.pumpAndSettle();
}

void main() {
  group('the three shared async states', () {
    testWidgets('loading names what it is waiting for', (tester) async {
      // One frame only: the keystore read has not resolved yet.
      await _pump(tester, _host(FakeSecretStore(), ScriptedServer()));

      expect(find.byType(LoadingState), findsOneWidget);
      expect(find.text('Checking what is already signed in'), findsOneWidget);
    });

    testWidgets('a keystore failure renders an error WITH a retry', (
      tester,
    ) async {
      await _pump(
        tester,
        ProviderScope(
          overrides: [
            serverSessionProvider.overrideWith(
              (ref) => Future<ServerSessionStatus>.error(
                StateError('keystore unavailable'),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ServerSignInScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't read this phone's keystore"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('signed out renders the form, not a blank card', (
      tester,
    ) async {
      await _pump(tester, _host(FakeSecretStore(), ScriptedServer()));
      await tester.pumpAndSettle();

      expect(find.text('Sign in with an API token'), findsOneWidget);
      expect(_formFields, findsNWidgets(2));
      expect(find.text('Check and sign in'), findsOneWidget);
    });
  });

  group('the form', () {
    testWidgets('SHOWS NO ADDRESS when the build was given none', (tester) async {
      // A test build has no `HELIO_API`, which since the app started discovering
      // its identity provider is also the normal case for a PUBLISHED APK: it is
      // aimed at nobody. `Env.apiBaseUrl` then falls back to
      // `http://127.0.0.1:8765`, and prefilling that would show the reader an
      // answer we do not have — a real-looking address, wrong for everyone who did
      // not build the app, sitting in a field above a button.
      //
      // Reported from a real install: "i need to add server address its set as
      // 127". An empty field asks the question instead; the hint carries the shape.
      await _pump(tester, _host(FakeSecretStore(), ScriptedServer()));
      await tester.pumpAndSettle();

      final url = tester.widget<TextField>(_formFields.first);
      expect(url.controller!.text, isEmpty);
      expect(find.textContaining('healthee.example.com'), findsOneWidget);
    });

    testWidgets('the token field is obscured, and the eye reveals it', (
      tester,
    ) async {
      await _pump(tester, _host(FakeSecretStore(), ScriptedServer()));
      await tester.pumpAndSettle();

      TextField token() =>
          tester.widget<TextField>(_formFields.last);
      expect(token().obscureText, isTrue);

      await tester.tap(find.byTooltip('Show the token'));
      await tester.pumpAndSettle();
      expect(token().obscureText, isFalse);

      await tester.tap(find.byTooltip('Hide the token'));
      await tester.pumpAndSettle();
      expect(token().obscureText, isTrue);
    });

    testWidgets('the promise about where the token goes is ON the form', (
      tester,
    ) async {
      await _pump(tester, _host(FakeSecretStore(), ScriptedServer()));
      await tester.pumpAndSettle();

      // v02 sets the prose with a typographic apostrophe, so the needle carries
      // one too — the promise itself is word for word what it was.
      expect(
        find.textContaining('kept in this phone’s secure keystore'),
        findsOneWidget,
      );
      expect(find.textContaining('never written to a log'), findsOneWidget);
    });
  });

  group('the three outcomes are genuinely different on screen', () {
    testWidgets('200 stores the session and shows what is held', (
      tester,
    ) async {
      final store = FakeSecretStore();
      await _pump(tester, _host(store, ScriptedServer()));
      await tester.pumpAndSettle();
      await _submit(tester);

      expect(await Credentials(store).apiToken(), kSentinelToken);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text(_url), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      // The token itself is never rendered, revealed or not.
      expect(find.textContaining(kSentinelToken), findsNothing);
    });

    testWidgets('401 says REFUSED, offers no retry, and stores nothing', (
      tester,
    ) async {
      final store = FakeSecretStore();
      await _pump(
        tester,
        _host(store, ScriptedServer(reply: const ServerReply(401))),
      );
      await tester.pumpAndSettle();
      await _submit(tester);

      expect(find.text('That token was refused by the server'), findsOneWidget);
      expect(
        find.textContaining('the connection itself is fine'),
        findsOneWidget,
      );
      // Retrying the same token fails identically, so no button pretends otherwise.
      expect(find.text('Try again'), findsNothing);
      expect(store.values, isEmpty);
      // The form is still there to paste into — the way forward is real.
      expect(find.text('Check and sign in'), findsOneWidget);
    });

    testWidgets('unreachable says UNREACHABLE, and does not say refused', (
      tester,
    ) async {
      final store = FakeSecretStore();
      await _pump(
        tester,
        _host(
          store,
          ScriptedServer(failWith: hostNotFound('healthee.example.com')),
        ),
      );
      await tester.pumpAndSettle();
      await _submit(tester);

      expect(find.text("Couldn't reach healthee.example.com"), findsOneWidget);
      expect(find.textContaining('not a wrong token'), findsOneWidget);
      // The evening this feature exists to save: these two must never swap.
      expect(find.text('That token was refused by the server'), findsNothing);
      // A connection problem IS worth retrying, unlike a refusal.
      expect(find.text('Try again'), findsOneWidget);
      expect(store.values, isEmpty);
    });

    testWidgets('a rejected certificate reads as TLS, not as a dead network', (
      tester,
    ) async {
      await _pump(
        tester,
        _host(FakeSecretStore(), ScriptedServer(failWith: tlsRejected())),
      );
      await tester.pumpAndSettle();
      await _submit(tester);

      expect(
        find.textContaining('HTTPS certificate was rejected'),
        findsOneWidget,
      );
    });
  });

  group('the address rules are enforced at the screen, before any request', () {
    testWidgets('a remote http:// address is refused, and says why', (
      tester,
    ) async {
      final store = FakeSecretStore();
      final server = ScriptedServer();
      await _pump(tester, _host(store, server));
      await tester.pumpAndSettle();
      await _submit(tester, url: 'http://healthee.example.com');

      expect(
        find.textContaining('will not send your token to healthee.example.com'),
        findsOneWidget,
      );
      expect(find.textContaining('readable by every hop'), findsOneWidget);
      expect(server.sent, isEmpty, reason: 'nothing may go on the wire');
      expect(store.values, isEmpty);
    });

    testWidgets('a pasted token with a trailing newline still signs in', (
      tester,
    ) async {
      final store = FakeSecretStore();
      await _pump(tester, _host(store, ScriptedServer()));
      await tester.pumpAndSettle();
      await _submit(tester, token: '  $kSentinelToken\n');

      expect(find.text('Signed in'), findsOneWidget);
      expect(await Credentials(store).apiToken(), kSentinelToken);
    });
  });

  group('a phone already signed in', () {
    Future<void> pumpSignedIn(
      WidgetTester tester,
      FakeSecretStore store,
    ) async {
      store.values
        ..['helio_token'] = kSentinelToken
        ..['helio_base_url'] = _url;
      await _pump(tester, _host(store, ScriptedServer()));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows the session rather than a form that would overwrite it',
      (tester) async {
        await pumpSignedIn(tester, FakeSecretStore());

        expect(find.text('Signed in'), findsOneWidget);
        expect(find.text(_url), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      },
    );

    testWidgets('sign-out clears the token from the keystore', (tester) async {
      final store = FakeSecretStore();
      await pumpSignedIn(tester, store);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(store.values.containsKey('helio_token'), isFalse);
      expect(store.values.containsKey('helio_base_url'), isFalse);
      expect(_formFields, findsNWidgets(2));
    });

    testWidgets('sign-out says what it does and does not take away', (
      tester,
    ) async {
      await pumpSignedIn(tester, FakeSecretStore());

      expect(
        find.textContaining('Everything your strap measured stays here'),
        findsOneWidget,
      );
    });

    testWidgets('"use a different server" opens the form at the current one', (
      tester,
    ) async {
      await pumpSignedIn(tester, FakeSecretStore());
      await tester.tap(find.text('Use a different server'));
      await tester.pumpAndSettle();

      final url = tester.widget<TextField>(_formFields.first);
      expect(url.controller!.text, _url);
    });
  });
}
