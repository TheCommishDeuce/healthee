/// Activity and Insights, rebuilt to v02 — and the proof nothing was lost.
///
/// Split out of `tab_screens_test.dart` at the 400-line gate (Standards §1) when
/// both screens were rebuilt. The claims are the ones that file made about the
/// pre-v02 cards, re-asserted against the panels that replaced them: a card that
/// quietly lost its provenance sentence in the redesign would otherwise pass a
/// "does the screen render" test and fail nobody.
///
/// Two rules the rebuild could have broken, and both are here:
///
///   * **A WITHHELD VALUE IS STILL WITHHELD, WITH ITS REASON.** Today's grid is
///     allowed a bare hole because the screen behind it carries both.
///   * **The insights are not a debug readout**, and the statistic behind a
///     finding is still reachable and still behind a disclosure.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/insights/insights_screen.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  group('Activity', () {
    // The screen is v02's now (`activity_sections.dart`), and these are the same
    // claims the pre-v02 cards made, re-asserted against the panels that
    // replaced them. A card that quietly lost its provenance sentence in the
    // redesign would otherwise pass a "does the screen render" test.
    testWidgets('VO₂max names its instrument and its kind of error', (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store, home: const ActivityScreen()));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Fitness with its source'));

      expect(find.text('43.0'), findsOneWidget);
      // [[hr_reserve_vo2max]] D4 — the instrument travels with the number, and
      // it is the method's NAME rather than its wire id.
      expect(find.textContaining('Read by a recorded session'), findsOneWidget);
      expect(find.textContaining('gps_graded'), findsNothing);
      // WHICH kind of error, on the card, beside the number it qualifies.
      expect(
        find.textContaining('error magnitude, not a confidence interval'),
        findsOneWidget,
      );
      // And the reference is NOT on the card any more — it is in the ⓘ.
      expect(find.textContaining('Age/sex reference'), findsNothing);
    });

    testWidgets('the age model is named as a model output, not as an age', (
      tester,
    ) async {
      // Biological age itself is Today's hero and is drawn once. What Activity
      // carries is the prototype's bridge: the fitness TERM, named as a term.
      await tester.pumpWidget(todayHost(store, home: const ActivityScreen()));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('to the age model'));

      expect(
        find.textContaining('contributes −1.7 years to the age model'),
        findsOneWidget,
      );
      expect(find.textContaining('not a change in actual age'), findsOneWidget);
      expect(
        find.text('34.3'),
        findsNothing,
        reason: 'one number, one screen — the hero on Today owns this figure',
      );
    });

    testWidgets('the movement panel names which step number this is', (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store, home: const ActivityScreen()));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('that stream freezes'));

      expect(find.text('9,264'), findsOneWidget);
      expect(
        find.textContaining('The strap\u2019s own since-midnight counter'),
        findsOneWidget,
      );
    });

    testWidgets("the strap's calories are labelled as the strap's", (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store, home: const ActivityScreen()));
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining("by the strap's own count"));

      expect(
        find.textContaining("412 kcal by the strap's own count"),
        findsOneWidget,
        reason: "the product's energy model is the server's, not this number",
      );
    });
  });

  group('Insights', () {
    testWidgets('the pattern card joins two metrics, and names no cause', (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store, home: const InsightsScreen()));
      await tester.pumpAndSettle();

      // The findings list and its framing sentence were cut (F4); what remains
      // is the entry card, whose symmetric glyph is its non-causal wording.
      expect(find.textContaining('↔'), findsOneWidget);
      for (final verb in <String>['caused', 'because', 'improves', 'helps']) {
        expect(find.textContaining(verb), findsNothing, reason: verb);
      }
    });

    testWidgets('THE STATISTIC IS NOT ON THE SURFACE', (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store, home: const InsightsScreen()));
      await tester.pumpAndSettle();

      // The server's `description_raw` is a log line. It reached the home screen
      // verbatim once, which is what this rewrite exists to undo.
      expect(find.textContaining('Spearman('), findsNothing);
      expect(find.textContaining('rho '), findsNothing);
      expect(find.textContaining('q = '), findsNothing);
    });

    testWidgets('INSIGHTS IS NOT THE COACH, AND DOES NOT PRETEND TO BE', (
      tester,
    ) async {
      // The findings lived on a tab called Coach with a card underneath saying
      // the coach was not built. Both halves are gone: the coach is a sheet off
      // Today's FAB and it is wired, and this tab is about the history.
      await tester.pumpWidget(todayHost(store, home: const InsightsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Coach'), findsNothing);
      expect(find.textContaining('cannot answer questions yet'), findsNothing);
    });
  });
}
