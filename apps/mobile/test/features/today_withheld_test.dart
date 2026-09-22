import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  for (final field in ['last_sleep', 'recovery_score']) {
    testWidgets(
      '$field refuses without drawing a hidden value or losing weight entry',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 2400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          todayHost(
            store,
            server: todayView(
              mutate: (json) => {
                ...json,
                field: {
                  ...json[field]! as Map<String, Object?>,
                  'withheld': {
                    'reason': 'incomplete',
                    'message': 'Wear the strap overnight to restore $field.',
                  },
                },
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final refusal = find.byType(WithheldPanel);
        expect(refusal, findsOneWidget);
        expect(
          find.text('Wear the strap overnight to restore $field.'),
          findsOneWidget,
        );
        expect(
          find.descendant(of: refusal, matching: find.text('—')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: refusal, matching: find.text('Try again')),
          findsNothing,
        );
        expect(find.text('Log weight'), findsOneWidget);
        if (field == 'recovery_score') expect(find.text('72'), findsNothing);
      },
    );

    testWidgets('missing $field says it is missing, not a fabricated zero', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(mutate: (json) => {...json, field: null}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WithheldPanel), findsOneWidget);
      expect(find.textContaining('the server did not say why'), findsOneWidget);
      expect(find.text('0h 0m'), findsNothing);
    });
  }
}
