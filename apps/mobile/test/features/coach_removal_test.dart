/// The interactive coach is removed (DESIGN_DECISIONS P3): no route, no entry
/// point, and the conversations it kept on the phone are dropped on upgrade
/// without touching a measurement.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/insights/v02/finding_detail_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/shared/v02/data_footer.dart';

import '_today_host.dart';

const Finding _finding = Finding(
  kind: 'pairwise_lag',
  metricA: 'hrv_sleep_avg',
  metricB: 'recovery_score',
  eventKind: null,
  description: 'Spearman(hrv_sleep_avg, recovery_score) = +0.78',
  effectSize: 0.7794,
  effectMetric: 'spearman_r',
  qValue: 3.15e-27,
  nSamples: 138,
  lagDays: 0,
  researchNoteIds: <String>['slow_breathing_hrv_acute'],
);

void main() {
  group('no coach destination is reachable', () {
    late LocalStore store;
    setUp(() async {
      store = LocalStore.memory();
      await seedDevice(store);
    });
    tearDown(() => store.close());

    testWidgets('the coach paths are not registered', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 4000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(TodayScreen)));
      for (final path in <String>['/coach', '/coach/history']) {
        expect(
          router.configuration.findMatch(Uri(path: path)).isError,
          isTrue,
          reason: '$path must not resolve to a screen',
        );
      }
    });

    testWidgets('Insights no longer offers to ask the coach', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 14000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Insights');
      expect(find.text('A useful question comes next'), findsNothing);
      expect(find.text('Ask your coach'), findsNothing);
      expect(find.text(DataFooter.line), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a finding opens without a coach hand-off', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const FindingDetailScreen(routeKey: 'k', finding: _finding),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(DataFooter.line), findsOneWidget);
    expect(find.text('Talk this through'), findsNothing);
  });

  test(
    'v6 upgrade drops the coach tables and keeps pending strap data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'healthee-coach-drop-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/store.sqlite';
      final old = LocalStore.at(path);
      await old.customStatement(
        'INSERT INTO strap_samples (metric, ts_ms, day, value) VALUES (?, ?, ?, ?)',
        ['hr', 1788652800000, '2026-09-06', 60],
      );
      // The two v6 tables, as that schema created them, holding a conversation.
      await old.customStatement(
        'CREATE TABLE stored_coach_threads (scope TEXT NOT NULL DEFAULT \'\', '
        'id TEXT NOT NULL, started_at TEXT NOT NULL, last_at TEXT NOT NULL, '
        'opening TEXT NOT NULL, turns INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (scope, id))',
      );
      await old.customStatement(
        'CREATE TABLE stored_coach_turns (scope TEXT NOT NULL DEFAULT \'\', '
        'thread_id TEXT NOT NULL, seq INTEGER NOT NULL, kind TEXT NOT NULL, '
        'payload TEXT NOT NULL, at TEXT NOT NULL, '
        'PRIMARY KEY (scope, thread_id, seq))',
      );
      await old.customStatement(
        "INSERT INTO stored_coach_threads VALUES ('', 't', 'x', 'x', 'q', 1)",
      );
      await old.customStatement('PRAGMA user_version = 6');
      await old.close();

      final upgraded = LocalStore.at(path);
      addTearDown(upgraded.close);
      final tables = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'stored_coach_%'",
          )
          .get();
      expect(tables, isEmpty);
      expect(await upgraded.pushReader.pendingCount(), 1);
    },
  );
}
