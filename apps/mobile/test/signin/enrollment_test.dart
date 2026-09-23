/// QR enrollment on the phone — `docs/QR_ENROLLMENT.md`.
///
/// The link is parsed strictly (it decides where health data goes), the code is
/// redeemed with no credential attached, and only a token the server actually
/// returned replaces the session this phone already holds.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/signin_failure.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/auth/enrollment_client.dart';
import 'package:healthee/data/auth/enrollment_link.dart';
import 'package:healthee/data/auth/phone_enrollment.dart';

import '../pairing/_pairing_fakes.dart';
import '_signin_fakes.dart';

const String _code = 'one-time-enrollment-code-9c1f';
const String _phoneToken = 'hph_minted-phone-token-3b7e';
const String _link =
    'healthee://enroll?v=1&server=https%3A%2F%2Fhealth.example.com'
    '&code=$_code';

Matcher _failsWith<T extends ServerSignInFailure>() => throwsA(
  isA<ServerSignInException>().having((e) => e.failure, 'failure', isA<T>()),
);

EnrollmentClient _clientFor(ScriptedServer server) =>
    EnrollmentClient(EnrollmentClient.dioFor()..httpClientAdapter = server);

void main() {
  group('the link', () {
    test('a printed link yields its server and code', () {
      final link = EnrollmentLink.parse('  $_link  ');
      expect(link.server.value, 'https://health.example.com');
      expect(link.code, _code);
      expect(link.toString(), isNot(contains(_code)));
    });

    for (final (name, raw) in <(String, String)>[
      ('another scheme', 'https://enroll?v=1&server=https://h.example&code=c'),
      ('another host', 'healthee://pair?v=1&server=https://h.example&code=c'),
      (
        'another version',
        'healthee://enroll?v=2&server=https://h.example&code=c',
      ),
      ('no code', 'healthee://enroll?v=1&server=https://h.example'),
      ('free text', 'not a link at all'),
    ]) {
      test('refuses $name', () {
        expect(
          () => EnrollmentLink.parse(raw),
          _failsWith<InvalidEnrollmentLink>(),
        );
      });
    }

    test('A CLEARTEXT SERVER IS REFUSED, like a typed one', () {
      expect(
        () => EnrollmentLink.parse(
          'healthee://enroll?v=1&server=http%3A%2F%2Fevil.example&code=c',
        ),
        _failsWith<CleartextServerUrl>(),
      );
    });
  });

  group('redemption', () {
    test('posts the code with NO credential and returns the token', () async {
      final server = ScriptedServer(
        reply: const ServerReply(
          200,
          body: '{"device_token":"$_phoneToken","id":"x","user_id":"y"}',
        ),
      );
      final link = EnrollmentLink.parse(_link);

      final token = await _clientFor(
        server,
      ).redeem(url: link.server, code: link.code, label: 'Pixel');

      expect(token, _phoneToken);
      final sent = server.sent.single;
      expect(sent.uri.toString(), 'https://health.example.com/api/enroll');
      expect(sent.headers['Authorization'], isNull);
      expect(jsonDecode(utf8.decode(server.bodies.single)), <String, Object?>{
        'code': _code,
        'label': 'Pixel',
      });
    });

    test('a refused code is its own named failure', () async {
      final server = ScriptedServer(reply: const ServerReply(401));
      final link = EnrollmentLink.parse(_link);
      await expectLater(
        _clientFor(
          server,
        ).redeem(url: link.server, code: link.code, label: null),
        _failsWith<EnrollmentCodeRefused>(),
      );
    });

    test("the device cap carries the server's own sentence", () async {
      final server = ScriptedServer(
        reply: const ServerReply(409, body: '{"detail":"Revoke one first."}'),
      );
      final link = EnrollmentLink.parse(_link);
      await expectLater(
        _clientFor(
          server,
        ).redeem(url: link.server, code: link.code, label: null),
        throwsA(
          isA<ServerSignInException>().having(
            (e) => e.failure.remedy,
            'remedy',
            'Revoke one first.',
          ),
        ),
      );
    });
  });

  group('the session', () {
    test('an accepted code becomes an ENROLLED session', () async {
      final store = FakeSecretStore();
      final server = ScriptedServer(
        reply: const ServerReply(200, body: '{"device_token":"$_phoneToken"}'),
      );
      final repository = repositoryWith(store, server)..rejected = true;

      await repository.enroll(
        link: EnrollmentLink.parse(_link),
        client: _clientFor(server),
      );

      final session = (await Credentials(store).serverSession())!;
      expect(session.kind, StoredCredentialKind.enrolled);
      expect(session.token, _phoneToken);
      expect(session.baseUrl, 'https://health.example.com');
      expect(repository.rejected, isFalse);
    });

    test('A REFUSED CODE LEAVES THE PREVIOUS SESSION UNTOUCHED', () async {
      final store = FakeSecretStore();
      final credentials = Credentials(store);
      await credentials.setServerSession(
        baseUrl: 'https://old.example.com',
        token: kSentinelToken,
        kind: StoredCredentialKind.device,
      );
      final server = ScriptedServer(reply: const ServerReply(401));

      await expectLater(
        repositoryWith(
          store,
          server,
        ).enroll(link: EnrollmentLink.parse(_link), client: _clientFor(server)),
        _failsWith<EnrollmentCodeRefused>(),
      );

      final session = (await credentials.serverSession())!;
      expect(session.baseUrl, 'https://old.example.com');
      expect(session.token, kSentinelToken);
    });

    test('an unreachable server saves nothing', () async {
      final store = FakeSecretStore();
      final server = ScriptedServer(failWith: connectionRefused());
      await expectLater(
        repositoryWith(
          store,
          server,
        ).enroll(link: EnrollmentLink.parse(_link), client: _clientFor(server)),
        throwsA(isA<ServerSignInException>()),
      );
      expect(await Credentials(store).serverSession(), isNull);
    });
  });
}
