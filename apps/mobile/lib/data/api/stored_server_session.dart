import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

/// What KIND of credential a stored session holds.
///
/// It is written down rather than inferred, because the two behave differently
/// on `/api/*` and there is no way to tell them apart by looking: both are
/// opaque strings. A phone that guessed wrong would either send a device token
/// where only a JWT is accepted, or drop the transitional token an owner
/// mid-migration is still relying on — and both surface as an unexplained 401.
enum StoredCredentialKind {
  /// Minted by `POST /api/device` for this phone. `/ingest/*` only; `/api/*`
  /// takes the Supabase JWT beside it.
  device,

  /// Redeemed from an administrator's one-time QR code (`POST /api/enroll`).
  /// This phone's own `phone`-scoped token, accepted on BOTH `/api/*` and
  /// `/ingest/*` and revocable per phone (`docs/QR_ENROLLMENT.md`).
  enrolled,

  /// ⛔ The shared `REALTIME_INGEST_TOKEN`, pasted by the owner. One string, no
  /// identity, and accepted by the server on BOTH paths — which is exactly why
  /// it is going away. It is also what every session written before this field
  /// existed holds, so it is the value a legacy record decodes to.
  shared,
}

/// One atomic keystore value: credentials and an opaque cache namespace.
@immutable
class StoredServerSession {
  /// An existing session, including the legacy migration path.
  const StoredServerSession({
    required this.baseUrl,
    required this.token,
    required this.cacheScope,
    required this.kind,
  });

  /// Each verified sign-in gets a private namespace, even on the same server.
  factory StoredServerSession.create(
    String baseUrl,
    String token, {
    required StoredCredentialKind kind,
  }) {
    final random = Random.secure();
    return StoredServerSession(
      baseUrl: baseUrl,
      token: token,
      kind: kind,
      cacheScope: base64UrlEncode(
        List.generate(18, (_) => random.nextInt(256)),
      ),
    );
  }

  /// Read a previously committed snapshot. A null record means signed out.
  static StoredServerSession? decode(String encoded) {
    final Object? data;
    try {
      data = jsonDecode(encoded);
    } on FormatException {
      // jsonDecode includes the input in its exception; this input is a secret.
      throw const FormatException('Stored server session is malformed');
    }
    if (data == null) return null;
    if (data is! Map<String, dynamic> ||
        data['baseUrl'] is! String ||
        data['token'] is! String ||
        data['cacheScope'] is! String) {
      throw const FormatException('Stored server session is malformed');
    }
    return StoredServerSession(
      baseUrl: data['baseUrl'] as String,
      token: data['token'] as String,
      cacheScope: data['cacheScope'] as String,
      // A record written before this field existed holds the shared token,
      // because that is the only thing this app could store then. Defaulting to
      // `device` would silently stop sending the one credential those phones
      // have — an upgrade that signs the owner out for no visible reason.
      kind: switch (data['kind']) {
        'device' => StoredCredentialKind.device,
        'enrolled' => StoredCredentialKind.enrolled,
        _ => StoredCredentialKind.shared,
      },
    );
  }

  /// Where this token was verified.
  final String baseUrl;

  /// Never printed or used as a cache key.
  final String token;

  /// Contains no credentials; rotates when another session is installed.
  final String cacheScope;

  /// Which credential [token] is. See [StoredCredentialKind].
  final StoredCredentialKind kind;

  /// Serialized once and committed with one keystore write.
  String encode() => jsonEncode({
    'baseUrl': baseUrl,
    'token': token,
    'cacheScope': cacheScope,
    'kind': kind.name,
  });

  @override
  String toString() => 'StoredServerSession(redacted)';
}
