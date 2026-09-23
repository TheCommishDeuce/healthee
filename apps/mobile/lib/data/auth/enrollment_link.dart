/// The administrator's enrollment QR, read back — `docs/QR_ENROLLMENT.md`.
///
/// `healthee://enroll?v=1&server=<url>&code=<one-time code>`, printed by
/// `python -m healthee.db.enroll issue` on the server. Parsing is strict because
/// the link decides where this phone will send its owner's health data: the
/// server address goes through [ServerUrl.parse], the same rules a typed address
/// meets, so a cleartext or credential-carrying address is refused here too.
///
/// The app registers no intent filter for this scheme. A link is only ever read
/// from the in-app scanner or pasted by the owner, never opened by another app
/// or a web page.
library;

import 'package:healthee/data/api/server_url.dart';
import 'package:healthee/data/api/signin_failure.dart';
import 'package:meta/meta.dart';

/// A parsed enrollment link. `toString` never prints the code.
@immutable
class EnrollmentLink {
  const EnrollmentLink._(this.server, this.code);

  /// The only payload version this build understands.
  static const String version = '1';

  /// The server to enroll with.
  final ServerUrl server;

  /// The one-time code. A secret until redeemed.
  final String code;

  /// Parses [raw], or throws a [ServerSignInException] naming what is wrong.
  static EnrollmentLink parse(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'healthee' || uri.host != 'enroll') {
      throw const ServerSignInException(
        InvalidEnrollmentLink('it is not a Healthee enrollment link'),
      );
    }
    if (uri.queryParameters['v'] != version) {
      throw const ServerSignInException(
        InvalidEnrollmentLink(
          'it was made for a different version of this app — update the app '
          'or the server',
        ),
      );
    }
    final String code = uri.queryParameters['code']?.trim() ?? '';
    if (code.isEmpty) {
      throw const ServerSignInException(
        InvalidEnrollmentLink('it carries no code'),
      );
    }
    final ServerUrl server = ServerUrl.parse(
      uri.queryParameters['server'] ?? '',
    );
    return EnrollmentLink._(server, code);
  }

  @override
  String toString() => 'EnrollmentLink(${server.host}, code redacted)';
}
