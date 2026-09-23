import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/v02/meters.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  void viewport(WidgetTester tester, {double width = 390}) {
    tester.view
      ..physicalSize = Size(width, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Today is sleep, recovery, weight, then steps, heart rate, stress', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();
    expect(find.text('Log weight'), findsOneWidget);
    expect(find.text('Recovery'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.byType(FactorBars), findsOneWidget);
    expect(find.textContaining('/ 100 remaining'), findsNothing);
    for (final absent in <String>[
      'Your night',
      'Your day',
      'Longer view',
      'Daily journal',
      'Suggested actions',
      'Heart rate & stress',
      'Steps & energy',
      'Biological age · estimate',
      'Ask your coach',
    ]) {
      expect(find.text(absent), findsNothing, reason: absent);
    }
    final sleepY = tester.getTopLeft(find.text('Sleep').first).dy;
    final recoveryY = tester.getTopLeft(find.text('Recovery')).dy;
    final weightY = tester.getTopLeft(find.text('Log weight')).dy;
    expect(sleepY, lessThan(recoveryY));
    expect(recoveryY, lessThan(weightY));
    // F1: the day, below the morning's three, each its own card.
    var previous = weightY;
    for (final title in <String>['Steps', 'Heart rate', 'Stress']) {
      final y = tester.getTopLeft(find.text(title).last).dy;
      expect(y, greaterThan(previous), reason: title);
      previous = y;
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offline Today shows local sleep and one retry, not invented recovery',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(todayHost(store, serverUnreachable: true));
      await tester.pumpAndSettle();
      expect(find.text('Log weight'), findsOneWidget);
      expect(find.text('6h 20m'), findsOneWidget);
      expect(find.textContaining('From this phone'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('72'), findsNothing);
    },
  );

  testWidgets(
    'server sleep duration is shown rather than the different local copy',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => {
              ...json,
              'last_sleep': {
                ...json['last_sleep']! as Map<String, Object?>,
                'duration_min': 420,
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7h 00m'), findsOneWidget);
      expect(find.text('6h 20m'), findsNothing);
    },
  );

  testWidgets(
    'an old night names its year rather than looking like this year',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => {
              ...json,
              'last_sleep': {
                ...json['last_sleep']! as Map<String, Object?>,
                'end_iso': '2025-08-04T05:30:00Z',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('· 2025'), findsOneWidget);
    },
  );

  testWidgets('an undated night explicitly says its date is unavailable', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(
          mutate: (json) => {
            ...json,
            'last_sleep': {
              ...json['last_sleep']! as Map<String, Object?>,
              'end_iso': null,
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sleep date unavailable'), findsOneWidget);
    expect(find.textContaining('Night ending'), findsNothing);
  });

  testWidgets(
    'the sleep date converts the wire instant to explicitly local time',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => {
              ...json,
              'last_sleep': {
                ...json['last_sleep']! as Map<String, Object?>,
                'end_iso': '2026-07-31T00:30:00+14:00',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final end = DateTime.parse('2026-07-31T00:30:00+14:00').toLocal();
      expect(
        find.text(
          'Night ending ${prettyDate(end.toIso8601String())} · ${end.year} (local)',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('recovery detail remains reachable', (tester) async {
    viewport(tester);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recovery').first);
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryScreen), findsOneWidget);
  });

  testWidgets('Today fits narrow layouts without hiding safety notices', (
    tester,
  ) async {
    viewport(tester, width: 320);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();
    expect(find.text('POSSIBLE EARLY SIGNAL'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server sleep refusal is not replaced by local measurements', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(
          mutate: (json) => {
            ...json,
            'last_sleep': {
              'duration_min': 999,
              'withheld': {
                'reason': 'test',
                'message': 'The night is incomplete.',
              },
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The night is incomplete.'), findsOneWidget);
    expect(find.text('16h 39m'), findsNothing);
    expect(find.text('6h 20m'), findsNothing);
  });
}
