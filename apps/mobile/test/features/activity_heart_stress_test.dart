import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/activity/v02/heart_stress_panel.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  testWidgets('the linked heart rate/stress chart is on Activity, not Today', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    expect(find.byType(HeartStressPanel), findsNothing);
    await tapTab(tester, 'Activity');
    expect(find.byType(HeartStressPanel), findsOneWidget);
    expect(find.byType(V02LinkedChart), findsOneWidget);
    expect(tester.getSize(find.byType(V02LinkedChart)).height, greaterThan(0));
    expect(find.textContaining('not proof'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no stress stream does not invent a linked comparison', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      todayHost(
        store,
        home: const ActivityScreen(),
        server: todayView(
          mutate: (json) => {...json, 'today_stress_series': const <Object?>[]},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HeartStressPanel), findsNothing);
    expect(find.byType(V02LinkedChart), findsNothing);
    expect(find.text('The sessions behind it'), findsOneWidget);
  });
}
