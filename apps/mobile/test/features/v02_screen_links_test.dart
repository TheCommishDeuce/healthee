// Tap actual controls on the real router, including the simplified Today cards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/features/today/widgets/sleep_summary.dart';

import '_today_host.dart';

Future<void> _open(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  Future<void> pump(WidgetTester tester, {String? tab}) async {
    tester.view
      ..physicalSize = const Size(420, 3400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    if (tab != null) await tapTab(tester, tab);
  }

  test('detail routes are retained', () {
    expect(Routes.body, '/body');
    expect(Routes.fitness, '/fitness');
    expect(Routes.recovery, '/recovery');
    expect(Routes.sleepHistory, '/sleep-history');
  });

  testWidgets('Today recovery opens its detail', (tester) async {
    await pump(tester);
    await _open(tester, find.text('Recovery').first);
    expect(find.byType(RecoveryScreen), findsOneWidget);
  });

  testWidgets('Today sleep opens the full Sleep page', (tester) async {
    await pump(tester);
    await _open(tester, find.byType(SleepSummary));
    expect(find.byType(SleepScreen), findsOneWidget);
  });

  testWidgets('Sleep details opens sleep history', (tester) async {
    await pump(tester, tab: 'Sleep');
    await _open(tester, find.text('Details'));
    expect(find.byType(SleepHistoryScreen), findsOneWidget);
  });

  testWidgets('Activity bridge opens recovery', (tester) async {
    await pump(tester, tab: 'Activity');
    await _open(tester, find.text('View recovery'));
    expect(find.byType(RecoveryScreen), findsOneWidget);
  });

  testWidgets(
    'Body remains reachable from Insights rather than the Today hero',
    (tester) async {
      await pump(tester, tab: 'Insights');
      await _open(tester, find.byType(AgeEntryCard));
      expect(find.byType(BodyScreen), findsOneWidget);
    },
  );

  testWidgets('Insights sleep history opens the nights', (tester) async {
    await pump(tester, tab: 'Insights');
    await _open(tester, find.text('Sleep history'));
    expect(find.byType(SleepHistoryScreen), findsOneWidget);
  });

  testWidgets('Insights fitness estimates opens fitness', (tester) async {
    await pump(tester, tab: 'Insights');
    await _open(tester, find.text('Fitness estimates'));
    expect(find.byType(FitnessScreen), findsOneWidget);
  });
}
