/// The two ways QR enrollment stops that no other sign-in path has.
///
/// `docs/QR_ENROLLMENT.md`. A part of `signin_failure.dart` because
/// [ServerSignInFailure] is sealed; split out rather than added there so the
/// enrollment copy sits in one place.
part of 'signin_failure.dart';

/// What was scanned or pasted is not a Healthee enrollment link.
final class InvalidEnrollmentLink extends ServerSignInFailure {
  /// [detail] is a short, secret-free reason. Never the link: it holds a code.
  const InvalidEnrollmentLink(this.detail);

  /// Why it was refused: `'it is not a Healthee enrollment link'`, …
  final String detail;

  @override
  String get headline => "That isn't a Healthee enrollment code";

  @override
  String get remedy =>
      'This app reads the QR printed by `healthee.db.enroll issue` on your '
      'server, and $detail. Nothing was sent anywhere and nothing has been saved.';

  @override
  String get code => 'invalid_enrollment_link';

  @override
  bool get canRetry => false;
}

/// The server read the code and did not accept it.
///
/// One case on purpose: the server answers unknown, already used and expired
/// codes identically so that it never confirms a code exists, and the app does
/// not pretend to know which it was.
final class EnrollmentCodeRefused extends ServerSignInFailure {
  /// The server's single refusal.
  const EnrollmentCodeRefused();

  @override
  String get headline => 'That enrollment code was not accepted';

  @override
  String get remedy =>
      'Codes work once and expire after a few minutes. Ask for a new one on '
      'the server (`healthee.db.enroll issue`) and scan it again. Nothing has '
      'been saved.';

  @override
  String get code => 'enrollment_code_refused';

  @override
  bool get canRetry => false;
}
