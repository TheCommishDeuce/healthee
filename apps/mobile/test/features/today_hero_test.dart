// The age hero still lives on Body; removing it from Today must not break it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/bio_hero.dart';
import 'package:healthee/shared/v02/instruments/bio_halo.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

Future<bool> _settles(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 33),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 1),
    );
    return true;
    // The timeout is the observation; real application exceptions still fail tests.
    // ignore: avoid_catching_errors
  } on FlutterError {
    return false;
  }
}

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the retained Body hero contains its halo and figure', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(todayHost(store, home: const BodyScreen()));
    await tester.pumpAndSettle();
    final hero = find.byType(BioHero);
    expect(hero, findsOneWidget);
    expect(
      find.descendant(of: hero, matching: find.byType(BioHalo)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: hero, matching: find.text('34.3')),
      findsOneWidget,
    );
  });

  testWidgets('Body halo pauses when scrolled out of view', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      todayHost(store, home: const BodyScreen(), reducedMotion: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(await _settles(tester), isFalse);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pump();
    expect(await _settles(tester), isTrue);
  });

  testWidgets('reduced motion stops the Body halo', (tester) async {
    phone(tester);
    await tester.pumpWidget(todayHost(store, home: const BodyScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(BioHalo), findsOneWidget);
  });

  testWidgets(
    'Body retains the server model explanation behind its info control',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(todayHost(store, home: const BodyScreen()));
      await tester.pumpAndSettle();
      final hero = find.byType(BioHero);
      final model = tester.widget<BioHero>(hero).modelLabel!;
      await tester.tap(
        find.descendant(of: hero, matching: find.byType(MetricInfoDot)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(model), findsOneWidget);
    },
  );

  testWidgets('absent comparison inputs do not invent an age delta', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        home: const BodyScreen(),
        server: todayView(
          mutate: (json) => {
            ...json,
            'biological_age': {
              ...json['biological_age']! as Map<String, Object?>,
              'delta_years': null,
              'chronological_age': null,
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hero = find.byType(BioHero);
    expect(
      find.descendant(of: hero, matching: find.text('34.3')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hero,
        matching: find.textContaining('chronological age'),
      ),
      findsNothing,
    );
  });
}
