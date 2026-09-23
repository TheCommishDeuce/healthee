import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/recovery_panel.dart';
import 'package:healthee/features/today/widgets/sleep_summary.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/citation_row.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  Future<void> pump(WidgetTester tester, {bool caveated = false}) async {
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
            if (caveated)
              'recovery_score': {
                ...json['recovery_score']! as Map<String, Object?>,
                'caveats': [
                  {
                    'reason': 'test',
                    'message': 'This recovery has limited coverage.',
                  },
                ],
              },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Today keeps clinical routing but not inline research essays', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(CitationRow), findsNothing);
    expect(find.text(kRecoveryPriorityNote), findsOneWidget);
    expect(find.text(kRecoveryScalesNote), findsNothing);
  });

  for (final panel in [SleepSummary, RecoveryPanel]) {
    testWidgets('$panel retains a usable explanation', (tester) async {
      await pump(tester);
      final dot = find.descendant(
        of: find.byType(panel),
        matching: find.byType(MetricInfoDot),
      );
      expect(dot, findsOneWidget);
      await tester.tap(dot, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      // The sheet is where the card's sources went when they left its face; an
      // ⓘ that opens onto no sources has lost them rather than moved them.
      final sources = <String>[
        for (final row in tester.widgetList<CitationRow>(
          find.byType(CitationRow),
        ))
          ...row.noteIds,
      ];
      expect(sources, isNotEmpty, reason: 'the sheet carries no sources');
      if (panel == RecoveryPanel) {
        expect(find.textContaining(kRecoveryScalesNote), findsOneWidget);
      }
    });
  }

  testWidgets('recovery caveats remain inside its own info control', (
    tester,
  ) async {
    await pump(tester, caveated: true);
    final dot = find.descendant(
      of: find.byType(RecoveryPanel),
      matching: find.byType(MetricInfoDot),
    );
    expect(tester.widget<MetricInfoDot>(dot).detail.disclosures, isNotEmpty);
    expect(find.text('This recovery has limited coverage.'), findsNothing);
    await tester.tap(dot, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This recovery has limited coverage.'),
      findsOneWidget,
    );
  });
}
