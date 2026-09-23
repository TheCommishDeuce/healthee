/// R3: the day's hourly heart rate and stress are drawn once — on Today.
///
/// Activity drew them as a linked chart; F1 put both on Today as their own,
/// more detailed cards, and the owner took the repeat off Activity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/day_cards.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  testWidgets('HOURLY HEART RATE AND STRESS ARE ON TODAY, NOT ACTIVITY', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 5000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    expect(find.byType(HeartRateDayCard), findsOneWidget);
    expect(find.byType(StressDayCard), findsOneWidget);

    await tapTab(tester, 'Activity');
    expect(find.text('Heart rate & stress'), findsNothing);
    expect(find.byType(V02LinkedChart), findsNothing);
    // The rest of the screen is intact.
    expect(find.text('The sessions behind it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
