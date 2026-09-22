import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/shared/app_tab_bar.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  testWidgets('the retained tab destinations remain reachable', (tester) async {
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    for (final label in ['Today', 'Sleep', 'Activity', 'Insights', 'Actions']) {
      expect(
        find.descendant(of: find.byType(AppTabBar), matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.text('Coach'), findsNothing);
  });

  testWidgets('no floating chat or GPS action covers the screen content', (
    tester,
  ) async {
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    for (final tab in [
      'Today',
      'Sleep',
      'Activity',
      'Insights',
      'Actions',
      'Today',
    ]) {
      await tapTab(tester, tab);
      for (final scaffold in tester.widgetList<Scaffold>(
        find.byType(Scaffold),
      )) {
        expect(scaffold.floatingActionButton, isNull);
      }
    }
  });
}
