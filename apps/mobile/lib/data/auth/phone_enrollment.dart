/// Enrolling this phone from the administrator's QR — `docs/QR_ENROLLMENT.md`.
///
/// An extension on [ServerSessionRepository] rather than a method in it: that
/// file is at the 400-line gate (Standards §1), and enrollment shares only the
/// keystore write and the rejection flag with the password path.
library;

import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/server_url.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/auth/enrollment_client.dart';
import 'package:healthee/data/auth/enrollment_link.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'phone_enrollment.g.dart';

/// The redemption client. A provider so tests can answer for the server.
@Riverpod(keepAlive: true)
EnrollmentClient enrollmentClient(Ref ref) =>
    EnrollmentClient(EnrollmentClient.dioFor());

/// Enrollment on the session repository.
extension PhoneEnrollment on ServerSessionRepository {
  /// Redeems [link] with [client] and makes the result this phone's session.
  ///
  /// Nothing is written unless the server returned a token: a refused or
  /// unreachable redemption leaves whatever session was held before untouched.
  /// Replacing a session keeps the strap pairing and every unsent measurement;
  /// they upload with the new token.
  Future<ServerUrl> enroll({
    required EnrollmentLink link,
    required EnrollmentClient client,
    String? deviceLabel,
  }) async {
    final token = await client.redeem(
      url: link.server,
      code: link.code,
      label: deviceLabel,
    );
    await credentials.setServerSession(
      baseUrl: link.server.value,
      token: token,
      kind: StoredCredentialKind.enrolled,
    );
    rejected = false;
    AppLog.info('signin', 'enrolled this phone with ${link.server.host}');
    return link.server;
  }
}
