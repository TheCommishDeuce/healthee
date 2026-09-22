/// The Actions tab and its screens are removed (DESIGN_DECISIONS P5): no tab,
/// no route, no link from Insights. The nightly jobs behind them stay on the
/// server, so nothing here is a data deletion.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/shared/v02/data_footer.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  testWidgets('no Actions tab and none of its paths resolve', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    expect(find.text('Actions'), findsNothing);
    expect(find.text('Insights'), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byType(TodayScreen)));
    for (final path in <String>[
      '/actions',
      '/recommendations',
      '/outcomes',
      '/challenge/1',
      '/program/1',
    ]) {
      expect(
        router.configuration.findMatch(Uri(path: path)).isError,
        isTrue,
        reason: '$path must not resolve to a screen',
      );
    }
  });

  testWidgets('Insights no longer links to challenge outcomes', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 14000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tapTab(tester, 'Insights');
    expect(find.text('Challenge outcomes'), findsNothing);
    expect(find.text('Sleep history'), findsOneWidget);
    expect(find.text('Fitness estimates'), findsOneWidget);
    expect(find.text(DataFooter.line), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
