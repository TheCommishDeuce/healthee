/// Which credential goes on which path, and what happens when there is none.
///
/// The server accepts each of the two on exactly one of the two paths — a JWT on
/// `/api/*`, a device token on `/ingest/*` — so getting this wrong is not a
/// style question. Sending the device token to `/api/*` is a 401 the app would
/// keep retrying with a credential that cannot work; sending the hour-long JWT
/// to `/ingest/*` is a background sync that stops working overnight and blames
/// the network.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/interceptors.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/auth/device_token_client.dart';

import '../pairing/_pairing_fakes.dart';
import '_identity_fakes.dart';
import '_signin_fakes.dart';

const String _stored = 'the-stored-device-token-777';
const String _minted = 'freshly-minted-device-token-888';

void main() {
  late FakeSecretStore store;
  late Credentials credentials;
  late ScriptedServer server;

  setUp(() async {
    store = FakeSecretStore();
    credentials = Credentials(store);
    await credentials.setServerSession(
      baseUrl: 'https://healthee.example.com',
      token: _stored,
      kind: StoredCredentialKind.device,
    );
    server = ScriptedServer();
  });

  /// A dio carrying the interceptor under test.
  Dio clientWith({required bool signedIn, ScriptedAuth? auth}) {
    final identity = identityWith(auth ?? ScriptedAuth(), store);
    final dio = Dio(BaseOptions(baseUrl: 'https://healthee.example.com'))
      ..httpClientAdapter = server
      ..interceptors.add(
        ServerSessionInterceptor(credentials, signedIn ? identity : null),
      );
    return dio;
  }

  /// Signs [identity] in so a session exists, then returns a client using it.
  Future<Dio> signedInClient({ScriptedAuth? auth}) async {
    final identity = identityWith(auth ?? ScriptedAuth(), store);
    await identity.signIn(email: 'owner@example.com', password: 'right');
    final dio = Dio(BaseOptions(baseUrl: 'https://healthee.example.com'))
      ..httpClientAdapter = server
      ..interceptors.add(ServerSessionInterceptor(credentials, identity));
    return dio;
  }

  String? sentAuth() => server.sent.single.headers['Authorization'] as String?;

  group('signed in with an identity', () {
    test('/api/* carries the JWT', () async {
      final dio = await signedInClient();
      await dio.get<Object?>('/api/today');
      expect(sentAuth(), 'Bearer $kAccessToken');
    });

    test('/ingest/* carries the DEVICE token, not the JWT', () async {
      final dio = await signedInClient();
      await dio.post<Object?>('/ingest/helio', data: <String, Object?>{});
      expect(sentAuth(), 'Bearer $_stored');
      expect(sentAuth(), isNot(contains(kAccessToken)));
    });

    test('NO LIVE JWT SENDS NO HEADER AT ALL — never the device token', () async {
      // The fallback is the tempting line and it is wrong twice: `/api/*` does
      // not accept a device token, so it buys nothing; and it would turn "your
      // session ended, sign in again" into an indistinguishable 401 the app
      // would replay forever. A device token was minted, so an identity minted
      // it — the JWT or nothing.
      // A stored session already past its expiry, so the first ask refreshes
      // rather than returning what it holds — and a provider that refuses the
      // refresh, which is what a revoked or rotated refresh token looks like.
      await store.write(key: 'supabase_session', value: _expiredSession());
      final expired = identityWith(
        ScriptedAuth(
          status: 401,
          reply: const <String, Object?>{
            'error_code': 'refresh_token_not_found',
            'msg': 'Invalid Refresh Token',
          },
        ),
        store,
      );

      final dio = Dio(BaseOptions(baseUrl: 'https://healthee.example.com'))
        ..httpClientAdapter = server
        ..interceptors.add(ServerSessionInterceptor(credentials, expired));
      await dio.get<Object?>('/api/today');

      expect(sentAuth(), isNull);
    });
  });

  group('after a real sign-in, end to end', () {
    test('THE SIGN-IN ITSELF FILES THE CREDENTIAL AS A DEVICE TOKEN', () async {
      // Asserted through the consequence rather than on the field: what the kind
      // decides is which credential every later `/api/*` call carries, and a
      // sign-in that filed its minted token as the shared one would send that
      // token where the server takes only a JWT — a 401 on every screen, with
      // the stored value looking perfectly correct.
      final fresh = FakeSecretStore();
      final auth = ScriptedAuth();
      final signIn = ScriptedServer(
        replies: const <ServerReply>[
          ServerReply(200, body: '{"premium":false}'),
          ServerReply(200, body: '{"device_token":"$_minted","id":"x"}'),
        ],
      );
      final identity = identityWith(auth, fresh);
      await ServerSessionRepository(
        credentials: Credentials(fresh),
        probe: probeWith(signIn),
        identity: identity,
        devices: DeviceTokenClient(
          DeviceTokenClient.dioFor()..httpClientAdapter = signIn,
        ),
      ).signIn(
        url: 'https://healthee.example.com',
        email: 'owner@example.com',
        password: 'right',
      );

      final after = ScriptedServer();
      final dio = Dio(BaseOptions(baseUrl: 'https://healthee.example.com'))
        ..httpClientAdapter = after
        ..interceptors.add(
          ServerSessionInterceptor(Credentials(fresh), identity),
        );

      await dio.get<Object?>('/api/today');
      expect(after.sent.single.headers['Authorization'], 'Bearer $kAccessToken');

      after.sent.clear();
      await dio.post<Object?>('/ingest/helio', data: <String, Object?>{});
      expect(after.sent.single.headers['Authorization'], 'Bearer $_minted');
    });
  });

  group('a phone still holding the SHARED token', () {
    test('it goes on both paths — the transitional shape', () async {
      // The one credential the server takes on `/api/*` and `/ingest/*` alike,
      // which is exactly why it is going away. Routed by the recorded kind, not
      // by whether an identity happens to be signed in: the two are independent,
      // and an owner mid-migration can be both.
      await credentials.setServerSession(
        baseUrl: 'https://healthee.example.com',
        token: _stored,
        kind: StoredCredentialKind.shared,
      );
      final dio = clientWith(signedIn: false);
      await dio.get<Object?>('/api/today');
      expect(sentAuth(), 'Bearer $_stored');

      server.sent.clear();
      await dio.post<Object?>('/ingest/helio', data: <String, Object?>{});
      expect(sentAuth(), 'Bearer $_stored');
    });

    test('AND AN IDENTITY DOES NOT OVERRIDE IT', () async {
      await credentials.setServerSession(
        baseUrl: 'https://healthee.example.com',
        token: _stored,
        kind: StoredCredentialKind.shared,
      );
      final dio = await signedInClient();
      await dio.get<Object?>('/api/today');
      expect(sentAuth(), 'Bearer $_stored');
    });
  });

  group('an ENROLLED phone (docs/QR_ENROLLMENT.md)', () {
    test('its own token goes on both paths', () async {
      await credentials.setServerSession(
        baseUrl: 'https://healthee.example.com',
        token: _stored,
        kind: StoredCredentialKind.enrolled,
      );
      final dio = clientWith(signedIn: false);
      await dio.get<Object?>('/api/today');
      expect(sentAuth(), 'Bearer $_stored');

      server.sent.clear();
      await dio.post<Object?>('/ingest/helio', data: <String, Object?>{});
      expect(sentAuth(), 'Bearer $_stored');
    });

    test('A LEFTOVER IDENTITY SESSION DOES NOT REPLACE IT ON /api/*', () async {
      await credentials.setServerSession(
        baseUrl: 'https://healthee.example.com',
        token: _stored,
        kind: StoredCredentialKind.enrolled,
      );
      final dio = await signedInClient();
      await dio.get<Object?>('/api/today');
      expect(sentAuth(), 'Bearer $_stored');
    });

    test('the kind survives the keystore round trip', () async {
      await credentials.setServerSession(
        baseUrl: 'https://healthee.example.com',
        token: _stored,
        kind: StoredCredentialKind.enrolled,
      );
      expect(
        (await credentials.serverSession())!.kind,
        StoredCredentialKind.enrolled,
      );
    });
  });

  group('no session at all', () {
    test('nothing is sent, and the build default stands', () async {
      final empty = FakeSecretStore();
      final dio = Dio(BaseOptions(baseUrl: 'https://healthee.example.com'))
        ..httpClientAdapter = server
        ..interceptors.add(
          ServerSessionInterceptor(Credentials(empty), null),
        );
      await dio.get<Object?>('/api/today');
      expect(sentAuth(), isNull);
    });
  });
}

/// A stored session whose access token expired an hour ago.
///
/// The token is JWT-shaped because `Session.expiresAt` reads the `exp` claim out
/// of it — see `jwtExpiringIn`. An opaque string here decodes to no expiry at
/// all and the session reads as live forever, which is the assertion quietly
/// passing against the wrong state.
String _expiredSession() {
  final stale = jwtExpiringIn(const Duration(hours: -1));
  return '{"access_token":"$stale","token_type":"bearer","expires_in":-3600,'
      '"refresh_token":"$kRefreshToken","user":{"id":"$kUserId",'
      '"aud":"authenticated","app_metadata":{},"user_metadata":{},'
      '"created_at":"2026-01-01T00:00:00Z"}}';
}
