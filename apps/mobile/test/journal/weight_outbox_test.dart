/// The weigh-in outbox — DESIGN_DECISIONS A8: held before sending, released only
/// on confirmation, retried in order, and never blocked by an entry the server
/// will never accept.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/log_draft.dart';
import 'package:healthee/data/journal/log_kind.dart';
import 'package:healthee/data/journal/weight_outbox.dart';
import 'package:healthee/data/store/local_store.dart';

final DateTime _now = DateTime(2026, 9, 20, 8);

LogDraft _weight(double kg, {int minutesAgo = 0}) => LogDraft(
  kind: LogKind.weight,
  at: _now.subtract(Duration(minutes: minutesAgo)),
  amount: kg,
);

/// A repository whose server answers each request with the next [replies]
/// entry: 200, a status to refuse with, or null for "no connection".
Future<(JournalRepository, List<RequestOptions>)> _server(
  List<int?> replies,
) async {
  final sent = <RequestOptions>[];
  final dio = Dio(BaseOptions(baseUrl: 'https://test.example'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        sent.add(request);
        final status = replies.isEmpty ? 200 : replies.removeAt(0);
        if (status == null) {
          handler.reject(
            DioException.connectionError(requestOptions: request, reason: 'x'),
          );
        } else if (status != 200) {
          handler.reject(
            DioException.badResponse(
              statusCode: status,
              requestOptions: request,
              response: Response(requestOptions: request, statusCode: status),
            ),
          );
        } else {
          handler.resolve(
            Response(requestOptions: request, data: {'ok': true}),
          );
        }
      },
    ),
  );
  return (JournalRepository(dio, await CacheSession.capture(null)), sent);
}

void main() {
  late LocalStore store;
  late WeightOutbox outbox;
  setUp(() {
    store = LocalStore.memory();
    outbox = WeightOutbox(store);
  });
  tearDown(() => store.close());

  test(
    'a held entry reads back exactly, observed when it was observed',
    () async {
      await outbox.hold(_weight(72.4, minutesAgo: 5), now: _now);
      final held = (await outbox.pending()).single;
      expect(held.kind, LogKind.weight);
      expect(held.amount, 72.4);
      expect(held.at, _now.subtract(const Duration(minutes: 5)));
    },
  );

  test('HOLDING THE SAME INSTANT TWICE KEEPS ONE, the newer weight', () async {
    await outbox.hold(_weight(72.4), now: _now);
    await outbox.hold(_weight(72.9), now: _now);
    expect((await outbox.pending()).single.amount, 72.9);
  });

  test('nothing invalid can wait in the queue', () async {
    for (final draft in <LogDraft>[
      _weight(0),
      _weight(1000),
      LogDraft(kind: LogKind.caffeine, at: _now, amount: 80),
      LogDraft(
        kind: LogKind.weight,
        at: _now.add(const Duration(hours: 1)),
        amount: 70,
      ),
    ]) {
      await expectLater(outbox.hold(draft, now: _now), throwsFormatException);
    }
    expect(await outbox.pending(), isEmpty);
  });

  test('a flush sends oldest first and releases only what landed', () async {
    await outbox.hold(_weight(71, minutesAgo: 60), now: _now);
    await outbox.hold(_weight(72, minutesAgo: 30), now: _now);
    final (repository, sent) = await _server(<int?>[200, null]);

    final result = await outbox.flush(repository);

    expect(result.sent, 1);
    expect(result.remaining, 1);
    expect(sent.map((r) => (r.data as Map)['amount']), <Object?>[71.0, 72.0]);
    expect((await outbox.pending()).single.amount, 72);
  });

  test(
    'A SERVER THAT CANNOT BE REACHED STOPS THE FLUSH and loses nothing',
    () async {
      await outbox.hold(_weight(71, minutesAgo: 60), now: _now);
      await outbox.hold(_weight(72, minutesAgo: 30), now: _now);
      final (repository, sent) = await _server(<int?>[null]);

      final result = await outbox.flush(repository);

      expect((result.sent, result.remaining), (0, 2));
      expect(sent, hasLength(1), reason: 'no hammering a server that is down');
      expect(await outbox.pending(), hasLength(2));
    },
  );

  test('an expired credential is a retry, not a refusal', () async {
    await outbox.hold(_weight(71), now: _now);
    final (repository, _) = await _server(<int?>[401]);
    expect((await outbox.flush(repository)).remaining, 1);
    expect(await outbox.pending(), hasLength(1));
  });

  test(
    'A REFUSED ENTRY IS DROPPED rather than blocking the newer ones',
    () async {
      await outbox.hold(_weight(71, minutesAgo: 60), now: _now);
      await outbox.hold(_weight(72, minutesAgo: 30), now: _now);
      final (repository, sent) = await _server(<int?>[422, 200]);

      final result = await outbox.flush(repository);

      expect((result.sent, result.refused, result.remaining), (1, 1, 0));
      expect(sent, hasLength(2));
      expect(await outbox.pending(), isEmpty);
    },
  );

  test('held entries survive a restart of the store', () async {
    final directory = await Directory.systemTemp.createTemp('healthee-weight-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/store.sqlite';
    final first = LocalStore.at(path);
    await WeightOutbox(first).hold(_weight(70.5), now: _now);
    await first.close();

    final reopened = LocalStore.at(path);
    addTearDown(reopened.close);
    expect((await WeightOutbox(reopened).pending()).single.amount, 70.5);
  });

  test(
    'a v7 store upgrades with an empty outbox and its pending rows intact',
    () async {
      final directory = await Directory.systemTemp.createTemp('healthee-v7-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/store.sqlite';
      final old = LocalStore.at(path);
      await old.customStatement(
        'INSERT INTO strap_samples (metric, ts_ms, day, value) VALUES (?, ?, ?, ?)',
        ['hr', 1788652800000, '2026-09-06', 60],
      );
      await old.customStatement('DROP TABLE pending_weights');
      await old.customStatement('PRAGMA user_version = 7');
      await old.close();

      final upgraded = LocalStore.at(path);
      addTearDown(upgraded.close);
      expect(await WeightOutbox(upgraded).pending(), isEmpty);
      expect(await upgraded.pushReader.pendingCount(), 1);
    },
  );
}
