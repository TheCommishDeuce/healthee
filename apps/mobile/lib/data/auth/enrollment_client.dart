/// `POST /api/enroll` — trades a one-time code for this phone's own token.
///
/// `docs/QR_ENROLLMENT.md`. Sent with **no** credential: the code is the
/// credential, and this phone holds nothing else for that server yet. The
/// returned token is `phone`-scoped (`hph_…`) and is what the app then sends on
/// both `/api/*` and `/ingest/*`.
///
/// Same transport contract as [DeviceTokenClient]: its own dio (no session
/// interceptors, so no stale credential can ride along), no redirects, and
/// every status read rather than thrown.
library;

import 'package:dio/dio.dart';
import 'package:healthee/core/env.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/server_url.dart';
import 'package:healthee/data/api/signin_failure.dart';
import 'package:healthee/data/api/transport_failure.dart';
import 'package:healthee/data/auth/device_token_client.dart';

/// The redemption path.
const String kEnrollPath = '/api/enroll';

/// Redeems enrollment codes.
class EnrollmentClient {
  /// Wraps [dio]; production passes [dioFor].
  const EnrollmentClient(this._dio);

  /// A dio with this client's limits and nothing else.
  static Dio dioFor({Duration timeout = Env.requestTimeout}) =>
      DeviceTokenClient.dioFor(timeout: timeout);

  final Dio _dio;

  /// The phone token for [code], or a [ServerSignInException] saying why not.
  Future<String> redeem({
    required ServerUrl url,
    required String code,
    required String? label,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.postUri<Object?>(
        url.resolve(kEnrollPath),
        data: <String, Object?>{'code': code, 'label': ?label},
        options: Options(headers: {'Accept': 'application/json'}),
      );
    } on DioException catch (error) {
      AppLog.failure(
        'signin',
        '${url.host} did not answer the enrollment request (${error.type.name})',
        'transport failure while redeeming an enrollment code',
      );
      throw ServerSignInException(unreachableFailure(error, url.host));
    }
    return _read(response, url);
  }

  String _read(Response<Object?> response, ServerUrl url) {
    final status = response.statusCode ?? 0;
    if (status == 401) {
      AppLog.info('signin', '${url.host} did not accept the enrollment code');
      throw const ServerSignInException(EnrollmentCodeRefused());
    }
    if (status == 409) {
      AppLog.info(
        'signin',
        '${url.host} refused: this account is at its device cap',
      );
      final data = response.data;
      throw ServerSignInException(
        DeviceTokenCapReached(
          data is Map<String, Object?> && data['detail'] is String
              ? data['detail']! as String
              : null,
        ),
      );
    }
    final data = response.data;
    if (status < 200 || status >= 300) {
      AppLog.info(
        'signin',
        '${url.host} answered $status to the enrollment request',
      );
      throw ServerSignInException(
        ServerAnsweredUnexpectedly(
          status: status,
          detail: 'the enrollment request was not accepted',
        ),
      );
    }
    if (data is! Map<String, Object?> || data['device_token'] is! String) {
      throw ServerSignInException(
        ServerAnsweredUnexpectedly(
          status: status,
          detail: 'an enrollment reply this app could not read',
        ),
      );
    }
    return data['device_token']! as String;
  }
}
