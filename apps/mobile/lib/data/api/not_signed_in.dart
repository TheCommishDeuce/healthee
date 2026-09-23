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
