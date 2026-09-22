import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
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

  void tall(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('missing recovery factors are absent, not scored zero', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(
          mutate: (json) {
            final score = json['recovery_score']! as Map<String, Object?>;
            return {
              ...json,
              'recovery_score': {
                ...score,
                'factors': {
                  ...score['factors']! as Map<String, Object?>,
                  'sleep': <String, Object?>{},
                },
              },
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bars = find.byType(FactorBars);
    final factors = tester.widget<FactorBars>(bars).factors;
    expect(factors.where((factor) => factor.fraction == null), hasLength(1));
    expect(
      find.descendant(of: bars, matching: find.byKey(FactorBars.fillKey)),
      findsNWidgets(factors.length - 1),
    );
    expect(find.descendant(of: bars, matching: find.text('—')), findsOneWidget);
  });

  testWidgets(
    'illness notice precedes every reading and keeps server wording',
    (tester) async {
      tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();
      final flagY = tester.getTopLeft(find.text('POSSIBLE EARLY SIGNAL')).dy;
      expect(
        find.textContaining('Breathing rate +2.4 bpm vs your 14-day baseline'),
        findsOneWidget,
      );
      for (final label in ['Sleep', 'Recovery', 'Log weight']) {
        expect(
          tester.getTopLeft(find.text(label).first).dy,
          greaterThan(flagY),
        );
      }
    },
  );

  testWidgets('server sleep and recovery are explicitly dated when cached', (
    tester,
  ) async {
    tall(tester);
    await tester.pumpWidget(
      todayHost(store, server: todayView(fromCache: true)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Night ending'), findsOneWidget);
    expect(find.text('For 2026-07-31'), findsOneWidget);
    expect(find.textContaining('it describes 2026-07-31'), findsOneWidget);
    expect(find.text('Log weight'), findsOneWidget);
  });
}
