/// The strap outbox across the offline cases `PHASE_A_TRIAGE.md` lists and the
/// older suites did not cover: a restart with a refused credential, a response
/// lost after the server committed, and re-enrolling the same owner.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/interceptors.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/push/push_client.dart';
import 'package:healthee/data/push/push_outcome.dart';
import 'package:healthee/data/push/push_service.dart';
import 'package:healthee/data/store/local_store.dart';

import '_push_fakes.dart';
import 'push_service_test.dart' show seedOneDay;

final DateTime _now = DateTime(2026, 8, 4, 9, 30);

PushService _service(
  LocalStore store,
  FakeIngestTransport transport,
  Credentials credentials,
) => PushService(
  store: store,
  client: clientOver(transport),
  credentials: credentials,
);

Future<String> _storePath() async {
  final directory = await Directory.systemTemp.createTemp('healthee-offline-');
  addTearDown(() => directory.delete(recursive: true));
  return '${directory.path}/store.sqlite';
}

void main() {
  test('A RESTART WITH A REFUSED CREDENTIAL KEEPS EVERY PENDING ROW', () async {
    final path = await _storePath();
    final first = LocalStore.at(path);
    await seedOneDay(first);
    final pending = await first.pushReader.pendingCount();
    await first.close();

    final reopened = LocalStore.at(path);
    addTearDown(reopened.close);
    final refused = FakeIngestTransport(failWith: 401);

    final outcome = await _service(
      reopened,
      refused,
      signedIn(token: 'revoked-token'),
    ).run(now: _now);

    expect(outcome, isA<PushFailed>());
    expect(await reopened.pushReader.pendingCount(), pending);
    expect(
      (await reopened.pushReader.lastAttempt()).failureReason,
      isNotNull,
      reason: 'a refused phone must say so, not look idle',
    );
  });

  test(
    'a response lost after the server committed resends the SAME rows',
    () async {
      // The server wrote the page, then the answer never arrived (a 504 from the
      // edge). The client cannot know, so it keeps the rows and resends them; the
      // server's upsert on each row's own identity (`test_ingest_upsert.py`)
      // makes the second copy a no-op rather than a duplicate.
      final store = LocalStore.memory();
      addTearDown(store.close);
      await seedOneDay(store);
      final transport = FakeIngestTransport(failFirst: 1);
      final service = _service(store, transport, signedIn());

      expect(await service.run(now: _now), isA<PushFailed>());
      expect(await service.run(now: _now), isA<PushSent>());

      expect(transport.calls, 2);
      for (final key in <String>['samples', 'sleep', 'daily_totals']) {
        expect(transport.bodies[1][key], transport.bodies[0][key], reason: key);
      }
      expect(await store.pushReader.pendingCount(), 0);
    },
  );

  test(
    'RE-ENROLLING THE SAME OWNER UPLOADS THE BACKLOG WITH THE NEW TOKEN',
    () async {
      // The QR migration (docs/QR_ENROLLMENT.md): a phone that collected while its
      // old credential was refused, then enrolled, must send what it kept — once,
      // and with the enrolled token rather than the dead one.
      final store = LocalStore.memory();
      addTearDown(store.close);
      await seedOneDay(store);
      final pending = await store.pushReader.pendingCount();
      final secrets = MapSecretStore();
      final credentials = Credentials(secrets);
      await credentials.setServerSession(
        baseUrl: 'https://test.example',
        token: 'old-device-token',
        kind: StoredCredentialKind.device,
      );
      final transport = FakeIngestTransport(failWith: 401);
      // The production path: the token rides on the shared client's session
      // interceptor, read from the keystore at request time.
      final dio =
          Dio(
              BaseOptions(
                baseUrl: 'https://example.invalid',
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 300,
              ),
            )
            ..httpClientAdapter = transport
            ..interceptors.add(ServerSessionInterceptor(credentials, null));
      final service = PushService(
        store: store,
        client: PushClient(dio),
        credentials: credentials,
      );
      expect(await service.run(now: _now), isA<PushFailed>());
      expect(transport.authorizations.last, 'Bearer old-device-token');

      await credentials.setServerSession(
        baseUrl: 'https://test.example',
        token: 'hph_enrolled-phone-token',
        kind: StoredCredentialKind.enrolled,
      );
      transport.failWith = null;
      final outcome = await service.run(now: _now);

      expect(outcome, isA<PushSent>());
      expect((outcome as PushSent).rows, pending);
      expect(transport.authorizations.last, 'Bearer hph_enrolled-phone-token');
      expect(await store.pushReader.pendingCount(), 0);
    },
  );
}
