import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/weight_outbox.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/widgets/weight_entry.dart';
import 'package:healthee/shared/sheets/weight_log_sheet.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;
  late Dio dio;
  late JournalRepository repository;
  final writes = <RequestOptions>[];
  var reject = false;
  var refuse = false;
  Completer<void>? acknowledgement;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
    writes.clear();
    reject = false;
    refuse = false;
    acknowledgement = null;
    dio = Dio(BaseOptions(baseUrl: 'https://test.example'));
    repository = JournalRepository(dio, await CacheSession.capture(null));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          writes.add(request);
          if (reject) {
            handler.reject(
              DioException.connectionError(
                requestOptions: request,
                reason: 'offline',
              ),
            );
            return;
          }
          if (refuse) {
            handler.reject(
              DioException.badResponse(
                statusCode: 422,
                requestOptions: request,
                response: Response(requestOptions: request, statusCode: 422),
              ),
            );
            return;
          }
          await acknowledgement?.future;
          handler.resolve(
            Response(requestOptions: request, data: {'ok': true}),
          );
        },
      ),
    );
  });
  tearDown(() async {
    dio.close(force: true);
    await store.close();
  });

  Future<void> openWeight(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(todayHost(store, journalRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log weight'));
    await tester.pumpAndSettle();
    expect(find.byType(WeightLogSheet), findsOneWidget);
  }

  String draft(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  testWidgets(
    'Today opens the existing weight-only form on the root navigator',
    (tester) async {
      await openWeight(tester);
      expect(find.text('kg'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Notes (optional)'), findsNothing);
      expect(writes, isEmpty);
      expect(
        tester.getRect(find.byType(WeightLogSheet)).bottom,
        closeTo(tester.getRect(find.byType(MaterialApp)).bottom, 0.5),
      );
    },
  );

  testWidgets(
    'slow credential loading keeps the entry responsive and opens when ready',
    (tester) async {
      final ready = Completer<JournalRepository>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            journalRepositoryProvider.overrideWith((ref) => ready.future),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: WeightEntry(signedIn: true)),
          ),
        ),
      );
      await tester.tap(find.text('Log weight'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Opening weight entry'), findsOneWidget);
      ready.complete(repository);
      await tester.pumpAndSettle();
      expect(find.byType(WeightLogSheet), findsOneWidget);
    },
  );

  testWidgets(
    'a credential failure is explained without opening an unusable form',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (count, error) => null,
          overrides: [
            journalRepositoryProvider.overrideWith(
              (ref) async => throw Exception('Keystore unavailable'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: WeightEntry(signedIn: true)),
          ),
        ),
      );
      await tester.tap(find.text('Log weight'));
      await tester.pumpAndSettle();
      expect(find.byType(WeightLogSheet), findsNothing);
      expect(
        find.textContaining('Could not open weight entry'),
        findsOneWidget,
      );
      expect(find.text('Log weight'), findsOneWidget);
      expect(find.text('Opening weight entry'), findsNothing);
    },
  );

  testWidgets('credential retries do not dispose the pending entry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (count, error) =>
            count == 0 ? const Duration(milliseconds: 20) : null,
        overrides: [
          journalRepositoryProvider.overrideWith((ref) async {
            if (++attempts == 1) throw Exception('Temporary keystore failure');
            return repository;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: WeightEntry(signedIn: true)),
        ),
      ),
    );
    await tester.tap(find.text('Log weight'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(WeightLogSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unconfirmed weight is retried later with its original timestamp',
    (tester) async {
      reject = true;
      await openWeight(tester);
      await tester.enterText(find.byType(TextField).first, '73.2');
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      final firstAt = (writes.single.data as Map)['at'];
      reject = false;

      final flushed = (await tester.runAsync(
        () => WeightOutbox(store).flush(repository),
      ))!;

      expect(flushed.sent, 1);
      expect(writes, hasLength(2));
      expect(writes.last.data, containsPair('at', firstAt));
      expect(writes.last.data, containsPair('type', 'weight'));
      expect(
        (await tester.runAsync(() => WeightOutbox(store).pending()))!,
        isEmpty,
      );
    },
  );

  testWidgets('invalid weight never reaches the server', (tester) async {
    await openWeight(tester);
    await tester.enterText(find.byType(TextField).first, '-4');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(draft(tester), '-4');
    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
    expect(find.text('Saved.'), findsNothing);
  });

  testWidgets(
    'weight clears only after acknowledgement, with no double submission',
    (tester) async {
      acknowledgement = Completer<void>();
      await openWeight(tester);
      await tester.enterText(find.byType(TextField).first, '73.2');
      await tester.tap(find.text('Save entry'));
      // Before the button can rebuild as disabled, another tap must not post again.
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single.path, '/api/log');
      expect(writes.single.data, containsPair('type', 'weight'));
      expect(writes.single.data, containsPair('amount', 73.2));
      expect(draft(tester), '73.2');
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Saved.'), findsNothing);
      await tester.tap(find.text('Saving…'));
      await tester.pump();
      expect(writes, hasLength(1));
      acknowledgement!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);
      expect(draft(tester), isEmpty);
    },
  );

  testWidgets('an offline save is held on the phone and says so', (
    tester,
  ) async {
    reject = true;
    await openWeight(tester);
    await tester.enterText(find.byType(TextField).first, '73.2');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    final held = (await tester.runAsync(() => WeightOutbox(store).pending()))!;
    expect(held.single.amount, 73.2);
    expect(find.textContaining('Saved on this phone'), findsOneWidget);
    expect(find.text('Saved.'), findsNothing);
    expect(draft(tester), isEmpty, reason: 'the entry is stored, not lost');
    expect(writes, hasLength(1));
  });

  testWidgets('a confirmed save leaves nothing held', (tester) async {
    await openWeight(tester);
    await tester.enterText(find.byType(TextField).first, '73.2');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.text('Saved.'), findsOneWidget);
    expect(
      (await tester.runAsync(() => WeightOutbox(store).pending()))!,
      isEmpty,
    );
  });

  testWidgets('a server refusal keeps the form and holds nothing', (
    tester,
  ) async {
    refuse = true;
    await openWeight(tester);
    await tester.enterText(find.byType(TextField).first, '73.2');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();

    expect(find.textContaining('did not accept this entry'), findsOneWidget);
    expect(draft(tester), '73.2');
    expect(
      (await tester.runAsync(() => WeightOutbox(store).pending()))!,
      isEmpty,
      reason: 'a refused entry must not wait for a retry that cannot succeed',
    );
  });

  testWidgets('a weight the server would refuse never leaves the form', (
    tester,
  ) async {
    await openWeight(tester);
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('Enter a weight between 10 and 700 kg.'), findsOneWidget);
    expect(
      (await tester.runAsync(() => WeightOutbox(store).pending()))!,
      isEmpty,
    );
  });
}
