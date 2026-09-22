/// The sign-in screen's one piece of logic. The widgets below it only draw.
///
/// Both methods have the same shape as the pairing controller's: publish a busy
/// label, run one repository call, land on idle or on a named failure. `on
/// ServerSignInException` is the only catch and it always sets
/// [ServerSignInState.failure], so "the button did nothing" is not reachable.
///
/// ## The credentials pass through and are not kept
///
/// [signIn] takes the password as a parameter, hands it to the repository, and
/// returns. It is never assigned to a field and never put in the state — see
/// `server_signin_state.dart`. The repository decides what is stored, and it
/// stores only a credential the server itself issued.
library;

import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/signin_failure.dart';
import 'package:healthee/data/auth/enrollment_link.dart';
import 'package:healthee/data/auth/phone_enrollment.dart';
import 'package:healthee/features/signin/server_signin_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_signin_controller.g.dart';

/// Drives the server sign-in screen.
@riverpod
class ServerSignInController extends _$ServerSignInController {
  @override
  ServerSignInState build() => const ServerSignInState();

  /// Signs in with an email and a password, and mints this device's token.
  ///
  /// Returns true when the sign-in landed, so the screen can leave without
  /// having to re-derive that from the state it just published.
  ///
  /// The busy label names the step, because these are three network calls to two
  /// different services and a single "Signing in…" over ten seconds tells the
  /// owner nothing about which one is slow.
  Future<bool> signIn({
    required String url,
    required String email,
    required String password,
  }) async {
    return _run('Signing in…', (repository) async {
      await repository.signIn(url: url, email: email, password: password);
    });
  }

  /// Creates an account with [email] and [password], then connects this phone.
  ///
  /// Separate from [signIn] rather than a flag on it, because the two produce
  /// different failures and the screen has to say which: signing in with an
  /// email that has no account, and creating one for an email that already has
  /// one, are opposite mistakes with opposite remedies.
  Future<bool> createAccount({
    required String url,
    required String email,
    required String password,
  }) async {
    return _run('Creating your account…', (repository) async {
      await repository.createAccount(url: url, email: email, password: password);
    });
  }

  /// ⛔ TRANSITIONAL — checks a PASTED [token] against [url] and stores it.
  ///
  /// The shared-token path. It goes when that secret does; see
  /// `data/api/server_session.dart`.
  Future<bool> signInWithToken({
    required String url,
    required String token,
  }) async {
    return _run('Checking with your server…', (repository) async {
      await repository.signInWithToken(url: url, token: token);
    });
  }

  /// The shape both sign-ins share: busy, one call, idle or a named failure.
  /// Redeems the administrator's enrollment [link] (`docs/QR_ENROLLMENT.md`).
  Future<bool> enroll(EnrollmentLink link) async {
    return _run('Enrolling this phone…', (repository) async {
      await repository.enroll(
        link: link,
        client: ref.read(enrollmentClientProvider),
      );
    });
  }

  Future<bool> _run(
    String label,
    Future<void> Function(ServerSessionRepository repository) call,
  ) async {
    state = state.working(label);
    try {
      await call(ref.read(serverSessionRepositoryProvider));
    } on ServerSignInException catch (error) {
      state = state.failing(error.failure);
      return false;
    }
    ref.invalidate(serverSessionProvider);
    state = const ServerSignInState();
    return true;
  }

  /// Clears the session. The strap pairing is deliberately untouched.
  Future<void> signOut() async {
    state = state.working('Signing out…');
    await ref.read(serverSessionRepositoryProvider).signOut();
    ref.invalidate(serverSessionProvider);
    state = const ServerSignInState();
  }

  /// Drops a failure so the form is clean again, e.g. after an edit.
  void clearFailure() {
    if (state.failure != null) {
      state = const ServerSignInState();
    }
  }
}
