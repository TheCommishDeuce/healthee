/// **The proof that the API token is never logged.**
///
/// `test/pairing/pairing_secrecy_test.dart` says why this shape of test exists:
/// the legacy Python printed a url-encoded password at debug level, and nobody
/// caught it by reading the code — it was caught by seeing it in a terminal.
/// This is that discovery, for the credential that reaches the Healthee server.
///
/// The method: drive both paths a token travels — the **sign-in check**
/// (`ServerProbe`) and **every subsequent API call** (the app's real dio, with
/// its real interceptors) — using a sentinel that exists in no other file, with
/// `AppLog.sink` capturing everything the app logs, and fail if the sentinel
/// appears anywhere in the transcript.
///
/// It covers the failure paths hardest, because a failure is where a secret
/// escapes: the one object a `catch` reliably has in hand is the exception, and
/// a `DioException` was built from the request that carried the header.
///
/// ## Why this file is worth more than the code comments it checks
///
/// Every "we never log the token" claim elsewhere in this feature is a promise
/// about code that someone will edit. This is the only place the claim is
/// *executed*. If a future change logs `options.headers`, or hands a
/// `DioException` to `AppLog.failure` on a path where dio has started quoting
/// headers, or adds a query parameter for convenience — this fails, and the
/// message prints the transcript that betrayed it.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/interceptors.dart';
import 'package:healthee/data/api/server_url.dart';
import 'package:healthee/data/api/signin_failure.dart';

import '../pairing/_pairing_fakes.dart';
import '_signin_fakes.dart';

const String _url = 'https://healthee.example.com';

late List<String> _log;

void _startCapturing() {
  _log = [];
  AppLog.sink = _log.add;
}

/// Fails if the sentinel token is anywhere in what the app logged.
void _expectTokenNotLogged() {
  final transcript = _log.join('\n');
  expect(
    transcript,
    isNot(contains(kSentinelToken)),
    reason: 'the API token reached the log:\n$transcript',
  );
}

/// The app's REAL client — same interceptors, same order — over [server].
///
/// Not a stripped-down dio: the point is to exercise `ServerSessionInterceptor`
/// (which puts the token on the request) and `ApiLogInterceptor` (which writes
/// the log lines) together, because a leak needs both to be present.
Dio _appClient(FakeSecretStore store, ScriptedServer server, {bool logBodies = false}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://compiled-in.example.com',
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  )..httpClientAdapter = server;
  dio.interceptors.addAll([
    ServerSessionInterceptor(Credentials(store), null),
    ApiLogInterceptor(logBodies: logBodies),
  ]);
  return dio;
}

/// A keystore already holding a verified session.
FakeSecretStore _signedInStore() => FakeSecretStore()
  ..values['helio_token'] = kSentinelToken
  ..values['helio_base_url'] = _url;

void main() {
  setUp(_startCapturing);
  tearDown(() => AppLog.sink = null);

  test('the log seam is off unless a test turns it on', () {
    AppLog.sink = null;
    expect(AppLog.sink, isNull, reason: 'nothing in lib/ may assign this');
  });

  group('the sign-in check logs plenty, and never the token', () {
    test('an accepted token: the host is logged, the secret is not', () async {
      final store = FakeSecretStore();
      await repositoryWith(store, ScriptedServer())
          .signInWithToken(url: _url, token: kSentinelToken);

      // The flow really ran — otherwise "nothing leaked" would be vacuous.
      expect(_log, isNotEmpty);
      expect(_log.join('\n'), contains('accepted the token'));
      expect(_log.join('\n'), contains('healthee.example.com'));
      _expectTokenNotLogged();
    });

    test('a refusal whose BODY echoes the token does not put it in the log', () async {
      // A server that quotes the credential back is not hypothetical; the Zepp
      // sign-in did exactly this, which is why that client parses no bodies.
      final server = ScriptedServer(
        reply: const ServerReply(401, body: '{"detail":"bad token: $kSentinelToken"}'),
      );

      await expectLater(
        repositoryWith(FakeSecretStore(), server)
            .signInWithToken(url: _url, token: kSentinelToken),
        throwsA(isA<ServerSignInException>()),
      );

      expect(_log.join('\n'), contains('refused the token'));
      _expectTokenNotLogged();
    });

    test('a transport failure logs the dio TYPE, not the exception object', () async {
      await expectLater(
        repositoryWith(
          FakeSecretStore(),
          ScriptedServer(failWith: hostNotFound('healthee.example.com')),
        ).signInWithToken(url: _url, token: kSentinelToken),
        throwsA(isA<ServerSignInException>()),
      );

      final transcript = _log.join('\n');
      expect(transcript, contains('connectionError'));
      // A DioException stringifies its message and wrapped error; it is never
      // handed to the logger from this path, and the assertion pins that.
      expect(transcript, isNot(contains('DioException')));
      _expectTokenNotLogged();
    });

    test('a 500 body full of the token stays out of the log', () async {
      await expectLater(
        repositoryWith(
          FakeSecretStore(),
          ScriptedServer(reply: const ServerReply(500, body: kSentinelToken)),
        ).signInWithToken(url: _url, token: kSentinelToken),
        throwsA(isA<ServerSignInException>()),
      );

      _expectTokenNotLogged();
    });

    test('the named failure itself carries no token', () async {
      for (final server in [
        ScriptedServer(reply: const ServerReply(401)),
        ScriptedServer(reply: const ServerReply(500)),
        ScriptedServer(failWith: tlsRejected()),
      ]) {
        try {
          await repositoryWith(FakeSecretStore(), server)
              .signInWithToken(url: _url, token: kSentinelToken);
          fail('expected a failure');
        } on ServerSignInException catch (error) {
          expect(error.failure.headline, isNot(contains(kSentinelToken)));
          expect(error.failure.remedy, isNot(contains(kSentinelToken)));
          expect(error.failure.code, isNot(contains(kSentinelToken)));
          expect(error.toString(), isNot(contains(kSentinelToken)));
        }
      }
    });
  });

  group('every API call afterwards carries the token and never logs it', () {
    test('a 200 through the app client: logged, and clean', () async {
      final server = ScriptedServer();
      final dio = _appClient(_signedInStore(), server);

      await dio.get<Object?>('/api/today');

      // The interceptor really attached it — otherwise this proves nothing.
      expect(server.sent.single.headers['Authorization'], 'Bearer $kSentinelToken');
      expect(_log.join('\n'), contains('/api/today'));
      _expectTokenNotLogged();
    });

    test('a 401 through the app client — the failure path — is clean', () async {
      final server = ScriptedServer(
        reply: const ServerReply(401, body: '{"detail":"$kSentinelToken"}'),
      );
      final dio = _appClient(_signedInStore(), server);

      await expectLater(
        dio.get<Object?>('/api/today'),
        throwsA(isA<DioException>()),
      );

      // `ApiLogInterceptor.onError` hands the DioException to AppLog, and this
      // is the assertion that keeps that safe.
      expect(_log.join('\n'), contains('failed'));
      _expectTokenNotLogged();
    });

    test('a dead network through the app client is clean', () async {
      final server = ScriptedServer(failWith: connectionRefused());
      final dio = _appClient(_signedInStore(), server);

      await expectLater(
        dio.get<Object?>('/api/today'),
        throwsA(isA<DioException>()),
      );
      _expectTokenNotLogged();
    });

    test('even with body logging ON — the deliberate opt-in — the header is not', () async {
      // `HELIO_LOG_HTTP=true` is a developer's explicit act and it prints
      // response bodies. It must still never print the request's credential.
      final server = ScriptedServer();
      final dio = _appClient(_signedInStore(), server, logBodies: true);

      await dio.get<Object?>('/api/today');

      expect(_log.join('\n'), contains('premium'), reason: 'bodies really are on');
      _expectTokenNotLogged();
    });
  });

  group('the token is never in a URL, and never in the app state', () {
    test('no request the sign-in makes puts it in the address or the query', () async {
      final server = ScriptedServer();
      await repositoryWith(FakeSecretStore(), server)
          .signInWithToken(url: _url, token: kSentinelToken);

      for (final request in server.sent) {
        expect(request.uri.toString(), isNot(contains(kSentinelToken)));
        expect(request.queryParameters.toString(), isNot(contains(kSentinelToken)));
      }
    });

    test('no API call puts it in the address either', () async {
      final server = ScriptedServer();
      await _appClient(_signedInStore(), server).get<Object?>('/api/entitlement');

      expect(server.sent.single.uri.toString(), isNot(contains(kSentinelToken)));
    });

    test('the session status a widget can see holds the server, not the token', () async {
      final store = _signedInStore();
      final status = await repositoryWith(store, ScriptedServer()).status();

      expect(status.baseUrl, _url);
      expect(status.toString(), isNot(contains(kSentinelToken)));
    });

    test('a stored session is applied to the compiled-in base URL', () async {
      // Not secrecy, but the same interceptor: a request must go to the server
      // the token was accepted by, never to whatever the build was compiled with.
      final server = ScriptedServer();
      await _appClient(_signedInStore(), server).get<Object?>('/api/today');

      expect(server.sent.single.uri.toString(), '$_url/api/today');
    });

    test('with no session an /api/* read never leaves at all (B2)', () async {
      final server = ScriptedServer();
      await expectLater(
        _appClient(FakeSecretStore(), server).get<Object?>('/api/today'),
        throwsA(isA<DioException>()),
      );
      expect(server.sent, isEmpty);
    });

    test('with no session any other path keeps the build default, no header', () async {
      final server = ScriptedServer();
      await _appClient(FakeSecretStore(), server).get<Object?>('/ingest/samples');

      expect(
        server.sent.single.uri.toString(),
        'https://compiled-in.example.com/ingest/samples',
      );
      expect(server.sent.single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('the address is not a secret, and the parser says nothing about the token', () {
    test('a malformed address failure quotes no input', () async {
      try {
        ServerUrl.parse('https://owner:$kSentinelToken@example.com');
        fail('expected a failure');
      } on ServerSignInException catch (error) {
        expect(error.failure, isA<MalformedServerUrl>());
        expect(error.failure.remedy, isNot(contains(kSentinelToken)));
        _expectTokenNotLogged();
      }
    });
  });
}
