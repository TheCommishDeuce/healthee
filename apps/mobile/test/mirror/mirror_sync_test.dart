/// The phone's full-history mirror (`docs/MIRROR.md`): fetch what changed,
/// skip what did not, delete what the server dropped, keep owners apart, resume
/// after an interruption, and never hand a mirrored row to the upload queue.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/mirror/mirror_sync.dart';
import 'package:healthee/data/store/local_store.dart';

/// A scripted server: an owner, a manifest per stream, and the months' rows.
class _Server {
  String owner = 'owner-a';
  int version = 1;

  /// stream → month → (digest, rows)
  final Map<String, Map<String, (String, List<Map<String, Object?>>)>> data =
      {};

  /// Month fetches served, as `stream/month`.
  final List<String> fetches = [];

  /// Fail the month fetch after this many have been served.
  int? failAfter;

  void put(String stream, String month, String digest, int rows) {
    data.putIfAbsent(stream, () => {})[month] = (
      digest,
      [
        for (var i = 0; i < rows; i++)
          <String, Object?>{'i': i, 'month': month},
      ],
    );
  }

  AccountApi api() {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.example'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          final path = request.path;
          Object? body;
          if (path == '/api/account') {
            body = {'user_id': owner, 'timezone': 'UTC'};
          } else if (path == '/api/mirror/manifest') {
            body = {
              'version': version,
              'streams': {
                for (final MapEntry(key: stream, value: months) in data.entries)
                  stream: [
                    for (final MapEntry(key: month, value: (digest, rows))
                        in months.entries)
                      {'month': month, 'rows': rows.length, 'digest': digest},
                  ],
              },
            };
          } else {
            if (failAfter != null && fetches.length >= failAfter!) {
              handler.reject(
                DioException.connectionError(
                  requestOptions: request,
                  reason: 'x',
                ),
              );
              return;
            }
            final stream = path.split('/').last;
            final month = request.queryParameters['month']! as String;
            fetches.add('$stream/$month');
            final (digest, rows) = data[stream]![month]!;
            body = {
              'version': version,
              'stream': stream,
              'month': month,
              'rows': rows.length,
              'digest': digest,
              'items': rows,
            };
          }
          handler.resolve(Response(requestOptions: request, data: body));
        },
      ),
    );
    return AccountApi(dio, _session!);
  }

  static CacheSession? _session;
}

void main() {
  late LocalStore store;
  late MirrorSync mirror;
  late _Server server;

  setUpAll(() async => _Server._session = await CacheSession.capture(null));
  setUp(() {
    store = LocalStore.memory();
    mirror = MirrorSync(store);
    server = _Server()
      ..put('derived_daily', '2026-01', 'd1', 3)
      ..put('derived_daily', '2026-02', 'd2', 2)
      ..put('weight_log', '2026-02', 'w2', 1);
  });
  tearDown(() => store.close());

  test('a first run downloads every month and stores it verbatim', () async {
    final run = await mirror.run(server.api());

    expect((run.fetched, run.unchanged, run.removed), (3, 0, 0));
    // Three stream-months, but only January and February: B3 said "7 months"
    // for history that spans two.
    expect(run.fetchedMonths, 2);
    final stats = await mirror.stats();
    expect((stats.months, stats.rows), (2, 6));
    expect(stats.bytes, greaterThan(0));
    final january = await (store.select(
      store.mirrorMonths,
    )..where((r) => r.month.equals('2026-01'))).getSingle();
    expect(jsonDecode(january.payload), hasLength(3));
  });

  test('A SECOND RUN DOWNLOADS NOTHING', () async {
    await mirror.run(server.api());
    server.fetches.clear();

    final run = await mirror.run(server.api());

    expect((run.fetched, run.unchanged, run.fetchedMonths), (0, 3, 0));
    expect(server.fetches, isEmpty);
  });

  test(
    'a changed month is replaced whole, and only that month is fetched',
    () async {
      await mirror.run(server.api());
      server
        ..fetches.clear()
        ..put('derived_daily', '2026-01', 'd1-corrected', 1);

      final run = await mirror.run(server.api());

      expect(server.fetches, ['derived_daily/2026-01']);
      expect(run.fetched, 1);
      final january = await (store.select(
        store.mirrorMonths,
      )..where((r) => r.month.equals('2026-01'))).getSingle();
      expect(january.digest, 'd1-corrected');
      expect(jsonDecode(january.payload), hasLength(1));
    },
  );

  test('A MONTH THE SERVER NO LONGER LISTS IS DELETED', () async {
    await mirror.run(server.api());
    server.data['derived_daily']!.remove('2026-02');

    final run = await mirror.run(server.api());

    expect(run.removed, 1);
    // February still holds a weigh-in, so it is still a month held.
    final stats = await mirror.stats();
    expect((stats.months, stats.rows), (2, 4));
  });

  test(
    'an interrupted run keeps what it wrote and resumes where it stopped',
    () async {
      server.failAfter = 1;
      await expectLater(mirror.run(server.api()), throwsA(isA<DioException>()));
      expect(await store.select(store.mirrorMonths).get(), hasLength(1));

      server
        ..failAfter = null
        ..fetches.clear();
      final run = await mirror.run(server.api());

      expect(
        run.fetched,
        2,
        reason: 'the month already written is not fetched again',
      );
      expect(server.fetches, hasLength(2));
    },
  );

  test('a new contract version fetches everything again', () async {
    await mirror.run(server.api());
    server
      ..fetches.clear()
      ..version = 2;
    expect((await mirror.run(server.api())).fetched, 3);
  });

  test('ANOTHER OWNER NEVER SEES THE FIRST OWNER’S HISTORY', () async {
    await mirror.run(server.api());
    server
      ..owner = 'owner-b'
      ..data.clear()
      ..put('weight_log', '2026-03', 'b3', 1);

    await mirror.run(server.api());

    final stats = await mirror.stats();
    expect((stats.months, stats.rows), (1, 1));
    final bRows = await (store.select(
      store.mirrorMonths,
    )..where((r) => r.owner.equals('owner-b'))).get();
    expect(bRows.single.month, '2026-03');
  });

  test('mirrored history is never offered to the upload queue', () async {
    final before = await store.pushReader.pendingCount();
    await mirror.run(server.api());
    expect(await store.pushReader.pendingCount(), before);
  });

  test('nothing mirrored reads as empty, not as an error', () async {
    expect((await mirror.stats()).months, 0);
    expect((await mirror.stats()).lastSynced, isNull);
  });
}
