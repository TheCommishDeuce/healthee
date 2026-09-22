/// **Every surface that draws model prose hands that prose's sources to an ⓘ.**
///
/// The sweep in `citation_sweep_test.dart` proves no card draws a chip. Alone,
/// it is satisfied by deleting the grounding — which is the outcome this product
/// exists to prevent, and the reason `grounded_text.dart` spends four paragraphs
/// arguing that a strip helper makes dropping the evidence one character cheaper
/// than keeping it.
///
/// This file is the other half, and it is per call site rather than per screen.
/// A screen-level suite can only cover screens somebody wrote a suite for, and
/// the surfaces here are the ones the sweep just took chips off: Sleep's lever,
/// its timing action and its analysis, Insights' notable days, Today's rows
/// and every disclosure. (Actions' suggestion and challenge cards went with the
/// Actions tab.)
///
/// The assertion is the same everywhere: **whatever `parseGrounded` finds in the
/// prose the surface drew, its ⓘ is carrying.** Not a fixed list — the parse
/// itself, so a surface cannot pass by citing a hard-coded id it does not
/// actually render.
///
/// The three things this move could lose quietly are in
/// `prose_grounding_loss_test.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/insights/generated_insight.dart';
import 'package:healthee/data/insights/insight_repository.dart';
import 'package:healthee/data/insights/notable_event.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_insight.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/features/insights/widgets/notable_events.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/shared/insight_card.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/reasoning_note.dart';
import '_citation_probe.dart';
import '_prose_fixtures.dart';

void main() {
  group('every prose surface hands its sources to an ⓘ', () {
    testWidgets('Sleep’s tonight lever', (tester) async {
      await pumpAt(tester, 390, TonightPanel(lever: kLever));

      expectGrounds(tester, TonightPanel, kLever.prose);
    });

    testWidgets('Sleep’s timing panel, for the server’s own action line', (
      tester,
    ) async {
      const action = 'Shift lights out earlier [sleep_regularity_index].';
      await pumpAt(
        tester,
        390,
        SleepTimingPanel(
          bedtime: const <double>[5, 5.5],
          wake: const <double>[13, 13.5],
          dates: const <String>['1 Aug', '2 Aug'],
          consistency: SleepConsistency.fromJson(const <String, Object?>{
            'nights': 2,
            'action': action,
          }),
          reveals: RevealRegistry(),
        ),
      );

      expectGrounds(tester, SleepTimingPanel, action);
    });

    testWidgets('Sleep’s analysis panel', (tester) async {
      const analysis = '**Your nights**\n\nSteady [sleep_regularity_index].';
      await pumpAt(
        tester,
        390,
        ProviderScope(
          overrides: [
            sleepInsightProvider.overrideWith(
              (ref) async => SleepInsight.fromJson(const <String, Object?>{
                'insight': analysis,
                'citations': <String>['vo2max'],
                'grade_floor': 'Probable',
              }),
            ),
          ],
          child: const SleepAnalysisPanel(),
        ),
      );

      expectGrounds(
        tester,
        SleepAnalysisPanel,
        analysis,
        alsoCites: const <String>['vo2max'],
      );
      expect(
        detailIn(tester, find.byType(SleepAnalysisPanel)).grade,
        'Probable',
      );
    });

    testWidgets('Insights’ notable days', (tester) async {
      const meaning = 'Your HRV dipped [recovery_readiness].';
      await pumpAt(
        tester,
        390,
        ProviderScope(
          overrides: [
            notableEventsProvider.overrideWith(
              (ref) => Stream<ServerSnapshot<List<NotableEvent>>>.value(
                ServerSnapshot<List<NotableEvent>>(<NotableEvent>[
                  const NotableEvent(
                    day: '2026-08-05',
                    metric: 'hrv_sleep_avg',
                    label: 'Overnight HRV',
                    value: 41,
                    median: 55,
                    meaning: meaning,
                    notes: <String>['vo2max'],
                  ),
                ], fetchedAt: DateTime(2026, 8, 5)),
              ),
            ),
          ],
          child: const NotableEvents(),
        ),
      );
      await tester.tap(find.text(NotableEvents.title));
      await tester.pumpAndSettle();

      expectGrounds(
        tester,
        NotableEvents,
        meaning,
        alsoCites: const <String>['vo2max'],
      );
    });

    testWidgets('the shared insight card, once opened', (tester) async {
      const analysis = 'Your week held steady [sleep_regularity_index].';
      await pumpAt(
        tester,
        390,
        ProviderScope(
          overrides: [
            generatedInsightProvider('activity', '').overrideWith(
              (ref) async => GeneratedInsight.fromJson(const <String, Object?>{
                'insight': analysis,
                'citations': <String>['vo2max'],
                'grade_floor': 'Probable',
                'validated': true,
              }),
            ),
          ],
          child: const InsightCard(scope: 'activity'),
        ),
      );
      await tester.tap(find.text('Coach analysis'));
      await tester.pumpAndSettle();

      expectGrounds(
        tester,
        InsightCard,
        analysis,
        alsoCites: const <String>['vo2max'],
      );
      expect(detailIn(tester, find.byType(InsightCard)).grade, 'Probable');
    });

    testWidgets('a disclosure whose answer is server prose', (tester) async {
      const answer = 'Because your debt is 120 minutes [sleep_need_debt].';
      await pumpAt(
        tester,
        390,
        const ReasoningNote(question: 'Why this, today', answer: answer),
      );

      expectGrounds(tester, ReasoningNote, answer);
    });

    testWidgets('a disclosure composed in Dart draws NO ⓘ', (tester) async {
      // An ⓘ opening an empty sheet is a control promising grounding there is
      // none of. Most disclosures in this app are of this kind.
      await pumpAt(
        tester,
        390,
        const ReasoningNote(
          question: 'The statistic behind this',
          answer: 'Computed over 105 days on which both were recorded.',
        ),
      );

      expect(dotIn(find.byType(ReasoningNote)), findsNothing);
    });
  });
}
