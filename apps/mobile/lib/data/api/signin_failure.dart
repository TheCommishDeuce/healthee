/// Every way signing in to the server can fail, named — and what to do about each.
///
/// The same rule `data/pairing/pairing_failure.dart` states for pairing, for the
/// same reason: **"something went wrong" is banned in this product.** A failure
/// with no way forward is the interface equivalent of a swallowed exception.
///
/// ## Why the taxonomy is the whole work package
///
/// The failure this file exists to prevent is a *refusal reported as a
/// connection problem*. "Couldn't reach the server" shown for a token the server
/// actually read and rejected sends the owner to their router, their DNS and
/// their firewall for an evening, and none of those is where the answer is.
///
/// So the three answers below are produced by three structurally different code
/// paths in `server_probe.dart`, not by three branches of one `catch`:
///
/// ```text
///   before any bytes leave   MalformedServerUrl · CleartextServerUrl · MissingToken
///   the request never landed ServerUnreachable      (a DioException, response == null)
///   the server answered      TokenRefused · ServerAnsweredUnexpectedly  (a status code)
/// ```
///
/// A `DioException` type is not an error message; [UnreachableReason] is the
/// mapping, and it is a closed enum so a new dio type cannot silently become
/// "the request did not complete".
///
/// ## What is deliberately NOT in here
///
/// No case carries the token, and no case carries a response body. The nearest
/// thing to raw detail is [ServerAnsweredUnexpectedly.detail], which holds a
/// status code and a shape hint. `test/signin/signin_secrecy_test.dart` is the
/// proof rather than the promise.
library;

import 'package:meta/meta.dart';

// The identity provider's half of the taxonomy — see that file's own note.
part 'enrollment_failure.dart';
part 'identity_failure.dart';

/// A named sign-in failure, with the copy the screen renders.
@immutable
sealed class ServerSignInFailure {
  /// Base constructor. Use one of the subclasses.
  const ServerSignInFailure();

  /// A short, specific sentence naming *which* failure this is.
  String get headline;

  /// What the owner can do next. Never empty.
  String get remedy;

  /// A stable, secret-free identifier for the log. Not shown to a person.
  String get code;

  /// Whether re-running the same submit is worth offering.
  ///
  /// False wherever the input has to change first — pressing "Try again" on a
  /// token the server has already read and rejected fails identically.
  bool get canRetry => true;
}

/// The address is not one this app can send a request to.
final class MalformedServerUrl extends ServerSignInFailure {
  /// [detail] says what is wrong with it, in the owner's words.
  const MalformedServerUrl(this.detail);

  /// The specific problem: `'it has no host'`, `'ftp is not a web address'`.
  final String detail;

  @override
  String get headline => "That server address isn't one this app can use";

  @override
  String get remedy =>
      'It should look like https://healthee.example.com — $detail. An address '
      'typed without http:// or https:// is treated as https://.';

  @override
  String get code => 'malformed_server_url';

  @override
  bool get canRetry => false;
}

/// A plain-`http://` address pointing somewhere other than this phone.
///
/// Refused **before the request is built**, which is the only place it can be
/// refused usefully: a bearer token sent over cleartext to a remote host has
/// already been read off the wire by the time anything answers. There is no
/// override, because an override is a thing that gets ticked once and forgotten.
final class CleartextServerUrl extends ServerSignInFailure {
  /// [host] is the remote host the address pointed at.
  const CleartextServerUrl(this.host);

  /// The host that would have received the token in the clear.
  final String host;

  @override
  String get headline => 'Healthee will not send your token to $host in the clear';

  @override
  String get remedy =>
      'http:// means unencrypted, and a bearer token on an unencrypted '
      'connection is readable by every hop between this phone and $host — it '
      'would be compromised before the server even answered. Use https://, or '
      'reach the server over a tunnel and point Healthee at the local end. '
      'Plain http:// is allowed only for 127.0.0.1 and localhost, which never '
      'leave this device.';

  @override
  String get code => 'cleartext_server_url';

  @override
  bool get canRetry => false;
}

/// The token field was empty, or held nothing but whitespace.
final class MissingToken extends ServerSignInFailure {
  /// Nothing was typed.
  const MissingToken();

  @override
  String get headline => 'No token was entered';

  @override
  String get remedy =>
      'Paste the token your server was configured with. On a self-hosted '
      'install that is REALTIME_INGEST_TOKEN from the server\'s own .env file.';

  @override
  String get code => 'missing_token';

  @override
  bool get canRetry => false;
}

/// Why a request never landed. Closed, so a new dio failure type cannot silently
/// become the vague catch-all sentence.
enum UnreachableReason {
  /// DNS said nothing. Usually a typo in the host, or no network at all.
  hostNotFound('the name could not be looked up'),

  /// A machine answered the socket with "nothing is listening here".
  refused('the connection was refused'),

  /// It accepted the connection and never replied in time.
  timedOut('it did not answer in time'),

  /// TLS did not complete: an expired, self-signed or mismatched certificate.
  tlsRejected('the HTTPS certificate was rejected'),

  /// A transport failure that is none of the above. Kept honest rather than
  /// guessed at.
  unknown('the connection failed before any reply arrived');

  const UnreachableReason(this.sentence);

  /// The clause the failure copy reads out.
  final String sentence;
}

/// Nothing answered. **The token was not judged, and nothing was stored.**
final class ServerUnreachable extends ServerSignInFailure {
  /// [reason] is the mapped transport failure; [host] is who was being called.
  const ServerUnreachable({required this.reason, required this.host});

  /// Which kind of transport failure this was.
  final UnreachableReason reason;

  /// The host that did not answer.
  final String host;

  @override
  String get headline => "Couldn't reach $host";

  @override
  String get remedy =>
      'This is a connection problem, not a wrong token — ${reason.sentence}, so '
      'the server never got as far as reading it. Nothing has been saved. Check '
      'the address and that this phone can reach it, then try again.';

  @override
  String get code => 'server_unreachable_${reason.name}';
}

/// The server read the token and said no. **The one failure the owner can fix
/// by pasting something different.**
final class TokenRefused extends ServerSignInFailure {
  /// [status] is 401 or 403 — kept so the copy can be specific.
  const TokenRefused(this.status);

  /// The status the server answered with.
  final int status;

  @override
  String get headline => 'That token was refused by the server';

  @override
  String get remedy =>
      'The server answered HTTP $status, which means it read the token and did '
      'not recognise it — the connection itself is fine. Check it against '
      "REALTIME_INGEST_TOKEN in the server's .env, and watch for a stray "
      'character at either end when copying. Nothing has been saved.';

  @override
  String get code => 'token_refused';

  @override
  bool get canRetry => false;
}

/// Something answered, and it does not behave like the Healthee API.
///
/// The honest reading of "we got a reply and it was not a yes or a no". It is
/// **not** a catch-all: a refusal and a dead connection each have their own case
/// above, and only what remains lands here.
final class ServerAnsweredUnexpectedly extends ServerSignInFailure {
  /// [status] is what came back; [detail] is a short, secret-free hint.
  const ServerAnsweredUnexpectedly({required this.status, required this.detail});

  /// The HTTP status.
  final int status;

  /// A hint: `'a redirect'`, `'a reply that is not JSON'`, `'a server error'`.
  final String detail;

  @override
  String get headline => 'That address answered, but not like a Healthee server';

  @override
  String get remedy =>
      'It replied HTTP $status — $detail. Check the address points at the '
      'Healthee API itself rather than a proxy, a login page or a different '
      'service. Nothing has been saved.';

  @override
  String get code => 'unexpected_server_answer';
}

/// Thrown by the sign-in path. Carries a named [failure] and nothing else.
///
/// It deliberately does not extend or wrap `DioException`: that object holds the
/// request it came from, and the request holds the Authorization header.
@immutable
class ServerSignInException implements Exception {
  /// Wraps a named failure.
  const ServerSignInException(this.failure);

  /// Why the sign-in stopped.
  final ServerSignInFailure failure;

  @override
  String toString() => 'ServerSignInException(${failure.code})';
}
