// Today summarizes a night; the full timeline remains on Sleep.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/sleep/v02/night_panels.dart';
import 'package:healthee/features/sleep/v02/sleep_reading.dart';
import 'package:healthee/features/today/widgets/sleep_summary.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';
import 'package:healthee/shared/charts/v02/v02_hypnogram.dart';
import 'package:healthee/shared/metric_info/metric_info.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  testWidgets('Today shows the night summary, not another chart dashboard', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();
    expect(find.byType(SleepSummary), findsOneWidget);
    expect(find.byType(V02Hypnogram), findsNothing);
    expect(find.byType(HStackedSleep), findsNothing);
  });

  testWidgets('the sleep timeline remains on Sleep at full width', (
    tester,
  ) async {
    await tester.pumpWidget(todayHost(store, home: const SleepScreen()));
    await tester.pumpAndSettle();
    await reveal(tester, find.text(NightTimelinePanel.title));
    expect(find.byType(V02Hypnogram), findsOneWidget);
  });

  testWidgets('Sleep explanation remains reachable from the Today summary', (
    tester,
  ) async {
    await tester.pumpWidget(todayHost(store, home: const SleepScreen()));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SleepReading),
        matching: find.byType(MetricInfoDot),
      ),
      findsNothing,
    );
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();
    final summary = find.byType(SleepSummary);
    await reveal(tester, summary);
    await tester.tap(
      find.descendant(of: summary, matching: find.byType(MetricInfoDot)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(kMetricInfo['sleep']!.title),
      ),
      findsOneWidget,
    );
  });
}
