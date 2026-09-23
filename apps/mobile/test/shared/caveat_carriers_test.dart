/// **A card claims the disclosures it was handed, or they vanish in silence.**
///
/// `CaveatCarrier.insideCard` makes `ReadingView` draw NOTHING itself and pass
/// its disclosures down a `CaveatScope` instead. `states/caveat_scope.dart`
/// records why: a signpost rendered as a sibling *beneath* a whole card lands in
/// the gutter between two of them and stops naming which number it is about, and
/// a misattributed disclosure is a new false claim produced entirely by layout.
///
/// The cost of that fix is a second failure mode, and it is the worse one: a
/// card that does not read the scope shows the value with its qualification
/// dropped, and **nothing looks wrong**. `caveat_attribution_test.dart` walks the
/// real screens and cannot see it — its assertions are about where a carrier
/// sits, so a screen with no carrier at all passes both of them. That is not
/// hypothetical; it is how two mutations against `InstrumentModule` survived
/// until this file existed.
///
/// So the contract is asserted here, at the widget level, where no screen's
/// composition can make it vacuous. Split out of `reading_view_test.dart` at the
/// 400-line gate (Standards §1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/caveat_disclosure.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/v02/bio_hero.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';

void main() {
  group('the two carriers a card can be', () {
    // `CaveatCarrier.insideCard` makes `ReadingView` draw NOTHING itself and
    // hand its disclosures down a `CaveatScope` instead. That only works if the
    // card claims the scope — a card that does not is a disclosure vanishing in
    // silence, which `caveat_scope.dart` records as worse than the orphaned
    // note it replaced. Both carriers are asserted here rather than through a
    // screen, because a screen test passes vacuously the day the screen stops
    // rendering the card.
    const tilt = Disclosure(
      reason: 'overnight_session_mean',
      message: 'A plain average over the session, not the daily figure.',
    );

    Widget carrier(Widget card) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ReadingView<double>(
          reading: const Caveated<double>(14, <Disclosure>[tilt]),
          label: 'Breathing',
          caveatCarrier: CaveatCarrier.insideCard,
          builder: (context, value) => card,
        ),
      ),
    );

    testWidgets('the retained hero carries its disclosure inside its info control', (tester) async {
      await tester.pumpWidget(carrier(const BioHero(
        eyebrow: 'Estimate', value: '14', infoKey: 'biological_age',
      )));
      await tester.pumpAndSettle();
      final dot = tester.widget<MetricInfoDot>(find.descendant(
        of: find.byType(BioHero), matching: find.byType(MetricInfoDot),
      ));
      expect(dot.detail.disclosures, [tilt]);
    });

    testWidgets('A V02 PANEL HANDS THE NOTE TO ITS OWN ⓘ', (tester) async {
      // **The claim did not weaken, it moved.** A panel used to print the
      // sentence under its content; it now publishes the same disclosures to
      // its head, which folds them into the ⓘ's detail. What must still be
      // impossible is a card that shows the value and drops the qualification —
      // so this asserts the dot EXISTS and is carrying them, on a head given no
      // explainer of its own.
      await tester.pumpWidget(
        carrier(
          const Panel(
            head: PanelHead(title: 'Overnight HRV'),
            child: Text('14'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Panel),
          matching: find.byType(CaveatNote),
        ),
        findsNothing,
        reason: 'the sentence is in the sheet, not under the number',
      );
      final dot = find.descendant(
        of: find.byType(Panel),
        matching: find.byType(MetricInfoDot),
      );
      expect(dot, findsOneWidget, reason: "v02's carrier is the ⓘ");
      expect(
        tester.widget<MetricInfoDot>(dot).detail.disclosures,
        isNotEmpty,
        reason: 'a dot drawn with nothing behind it is the silent drop',
      );
    });

    testWidgets('A NESTED CARD DOES NOT DISCLOSE THE SAME THING TWICE', (
      tester,
    ) async {
      // Each carrier shadows the scope for its own subtree, so the inner panel
      // sees an empty one and its head has nothing to carry.
      await tester.pumpWidget(
        carrier(
          const Panel(
            head: PanelHead(title: 'Overnight HRV'),
            child: Panel(
              head: PanelHead(title: 'Inner'),
              child: Text('14'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final carrying = tester
          .widgetList<MetricInfoDot>(find.byType(MetricInfoDot))
          .where((dot) => dot.detail.disclosures.isNotEmpty);
      expect(carrying, hasLength(1));
    });
  });
}
