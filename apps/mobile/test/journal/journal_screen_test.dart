/// The journal — the grid, the sheet it opens, and what a failed write keeps.
///
/// The form moved into a sheet with the v02 redesign, so the three write
/// behaviours are asked of the sheet rather than of the screen. They are the
/// same three, unchanged, and they are the reason this suite exists: an entry
/// nobody acknowledged must not clear the form, and a rejected amount must never
/// reach the wire.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/features/journal/journal_screen.dart';
import 'package:healthee/features/journal/v02/journal_grid.dart';
import 'package:healthee/shared/sheets/log_sheet.dart';

void main() {
  late Dio dio;
  late JournalRepository repository;
  final writes = <RequestOptions>[];
  var reject = false;
  setUp(() async {
    writes.clear();
    reject = false;
    dio = Dio(BaseOptions(baseUrl: 'https://test.example'));
    repository = JournalRepository(dio, await CacheSession.capture(null));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          writes.add(request);
          if (reject) {
            handler.reject(
              DioException.connectionError(
                requestOptions: request,
                reason: 'offline',
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{'ok': true},
              ),
            );
          }
        },
      ),
    );
  });
  tearDown(() => dio.close());

  Widget host({bool signedIn = true, bool fastOpen = false}) => ProviderScope(
    overrides: [
      serverSessionProvider.overrideWith(
        (ref) async => signedIn
            ? const ServerSessionStatus(
                signedIn: true,
                baseUrl: 'https://test.example',
              )
            : const ServerSessionStatus.signedOut(),
      ),
      journalRepositoryProvider.overrideWith((ref) async => repository),
      journalFeedProvider.overrideWith(
        (ref) => Stream.value(
          ServerSnapshot(
            JournalFeed(entries: const [], fastOpen: fastOpen),
            fetchedAt: DateTime.utc(2026, 9, 6),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: JournalScreen(now: DateTime(2026, 9, 6, 12)),
    ),
  );

  /// Opens the sheet for one kind by tapping its tile, as an owner would.
  Future<void> openLog(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('signed out owner gets a sign-in action, no editable journal', (
    tester,
  ) async {
    await tester.pumpWidget(host(signedIn: false));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to save your journal'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(JournalGrid), findsNothing);
  });

  testWidgets('THE GRID IS THE PROTOTYPE’S TEN, IN ITS ORDER', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(kJournalTiles.length, 10);
    expect(
      kJournalTiles.map((tile) => tile.label).toList(),
      <String>[
        'Caffeine',
        'Water',
        'Mood',
        'Meditation',
        'Exercise',
        'Weight',
        'Alcohol',
        'Fasting',
        'Habit',
        'Symptom',
      ],
      reason: 'screens-actions.js::H.journalKinds, with LogKind’s own labels',
    );
    for (final tile in kJournalTiles) {
      expect(find.text(tile.label), findsOneWidget, reason: tile.label);
    }
  });

  testWidgets('A GRID ROW IS THREE EQUAL COLUMNS, AT EVERY PHONE WIDTH', (
    tester,
  ) async {
    for (final width in <double>[320, 360, 390, 414]) {
      tester.view
        ..physicalSize = Size(width * 3, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final first = tester.getRect(find.text('Caffeine').first);
      final second = tester.getRect(find.text('Water').first);
      final third = tester.getRect(find.text('Mood').first);
      // Painted geometry: the three sit on one line and none of them is off it.
      expect(first.center.dy, closeTo(second.center.dy, 0.5), reason: '$width');
      expect(second.center.dy, closeTo(third.center.dy, 0.5), reason: '$width');
      expect(first.left, greaterThanOrEqualTo(0), reason: '$width');
      expect(third.right, lessThanOrEqualTo(width), reason: '$width');
    }
  });

  testWidgets('THE LOG SHEET IS PRESENTED ON THE ROOT NAVIGATOR', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openLog(tester, 'Caffeine');

    expect(find.byType(LogSheet), findsOneWidget);
    // Its foot reaches the bottom of the app rather than stopping at whatever
    // box the screen underneath happens to occupy.
    final sheet = tester.getRect(find.byType(LogSheet));
    final app = tester.getRect(find.byType(MaterialApp));
    expect(sheet.bottom, closeTo(app.bottom, 0.5));
  });

  testWidgets('invalid input remains editable and is not sent', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openLog(tester, 'Caffeine');

    await tester.enterText(find.byType(TextField).first, '-20');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '-20',
    );
  });

  testWidgets('successful save clears form only after acknowledgement', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openLog(tester, 'Caffeine');

    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(writes.single.data, containsPair('amount', 80.0));
    expect(find.text('Saved.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  testWidgets('failed save retains draft and reports unconfirmed outcome', (
    tester,
  ) async {
    reject = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await openLog(tester, 'Caffeine');

    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save could not be confirmed'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '80',
    );
  });

  testWidgets('THE FAST TILE READS THE SERVER’S STATE, NEVER GUESSES IT', (
    tester,
  ) async {
    await tester.pumpWidget(host(fastOpen: true));
    await tester.pumpAndSettle();
    // The feed says a fast is open, so the tile offers the other half.
    expect(find.text('End fast'), findsOneWidget);
    expect(find.text('Fasting'), findsNothing);

    await tester.tap(find.text('End fast'));
    await tester.pumpAndSettle();
    // No amount field on the fast sheet: there is nothing to type.
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.widgetWithText(Row, 'End fast').last);
    await tester.pumpAndSettle();
    expect(writes, isNotEmpty);
  });
}
