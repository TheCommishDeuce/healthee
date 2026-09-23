import 'package:dio/dio.dart';

/// The phone holds no server session, so the request was not made at all.
///
/// Typed so a screen can say "sign in" instead of "couldn't reach your server"
/// (B2): no server was contacted, and blaming one sends the owner looking for a
/// fault that does not exist.
class NotSignedIn implements Exception {
  /// Carries nothing; the state is the whole message.
  const NotSignedIn();

  @override
  String toString() => 'NotSignedIn: this phone holds no server session';
}

/// Whether [error] is this state — thrown directly by a provider that checked
/// the session itself, or as the `error` of the [DioException] the app client's
/// interceptor refuses an `/api/*` request with.
bool isNotSignedIn(Object? error) =>
    error is NotSignedIn || (error is DioException && error.error is NotSignedIn);
