import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/today_screen.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  testWidgets('journal is not a destination; Today still offers weight entry', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(TodayScreen)));
    expect(
      router.configuration.findMatch(Uri(path: '/journal')).isError,
      isTrue,
    );
    expect(find.text('Log weight'), findsOneWidget);
  });

  testWidgets('tabs and Settings do not offer the retired journal', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 14000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(TodayScreen)));
    for (final tab in ['Actions', 'Insights', 'Sleep']) {
      await tapTab(tester, tab);
      for (final label in [
        'Add to your journal',
        'Your journal',
        'Journal',
        'Journal for this day',
      ]) {
        expect(
          find.text(label),
          findsNothing,
          reason: '$tab must not link to a removed screen',
        );
      }
    }
    unawaited(router.push(Routes.settings));
    await tester.pumpAndSettle();
    expect(find.text('Health journal'), findsNothing);
    expect(find.text('Account & server'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
