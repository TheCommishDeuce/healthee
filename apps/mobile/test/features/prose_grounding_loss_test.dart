/// The three things the move off the card faces could lose without a trace.
///
/// `prose_grounding_test.dart` proves each surface's ⓘ carries the note ids.
/// That is the loud half: a missing source name is visible the moment anyone
/// opens the sheet. These three are the quiet half — each of them leaves a sheet
/// that looks complete and a card that looks correct:
///
///   * **an unresolved marker**, dropped on the way into `MetricDetail`. A
///     citation we cannot read is our failure, not a fact about the owner's
///     body, and nothing else on the screen would say it was ever there;
///   * **a personal finding merged into the note ids**, which gives an n-of-1
///     correlation from this owner's own history the standing of a literature
///     review and loses `kSingleSubjectFraming` with it;
///   * **a grade that was never sent**. `citation_row.dart` has the argument: a
///     grade derived from an id is a second grade that can disagree with the
///     corpus, which is #83 rebuilt one layer down.
///
/// They are driven through `ReasoningNote` and the shared insight card because
/// both are thin — the payload reaches `MetricDetail` through almost nothing, so
/// a failure here is about the routing and not about a card. (The grade case
/// used the coach bubble until the interactive coach was removed; the insight
/// card is the surviving surface that carries a server `grade_floor`.)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/insights/generated_insight.dart';
import 'package:healthee/data/insights/insight_repository.dart';
import 'package:healthee/shared/format/note_names.dart';
import 'package:healthee/shared/insight_card.dart';
import 'package:healthee/shared/states/citation_row.dart';
import 'package:healthee/shared/states/reasoning_note.dart';
import '_citation_probe.dart';

void main() {
  group('what the ⓘ must not lose on the way', () {
    testWidgets('AN UNRESOLVED MARKER REACHES THE SHEET AND IS VISIBLE', (
      tester,
    ) async {
      // A broken citation is our failure, not a fact about the owner's body.
      // Routing only `noteIds` into `MetricDetail` would drop it silently.
      const answer = 'Walk today [see the sleep tab].';
      await pumpAt(
        tester,
        390,
        const ReasoningNote(question: 'Why this, today', answer: answer),
      );

      final dot = dotIn(find.byType(ReasoningNote));
      expect(
        detailIn(tester, find.byType(ReasoningNote)).unresolved,
        contains('see the sleep tab'),
      );
      await tester.tap(dot);
      await tester.pumpAndSettle();

      expect(find.textContaining('no source we can resolve'), findsOneWidget);
    });

    testWidgets('A PERSONAL FINDING IS STILL LABELLED SINGLE-SUBJECT', (
      tester,
    ) async {
      // It arrives in the same brackets as a corpus citation and it is not one.
      // Merging it into `noteIds` would give an n-of-1 correlation the standing
      // of a literature review — silently, and only in the sheet.
      const answer =
          'Your HRV moved with it [personal_finding:hrv_sleep_avg, vo2max].';
      await pumpAt(
        tester,
        390,
        const ReasoningNote(question: 'Why this, today', answer: answer),
      );

      final detail = detailIn(tester, find.byType(ReasoningNote));
      expect(detail.personalFindings, <String>['hrv_sleep_avg']);
      expect(
        detail.notes,
        isNot(contains('hrv_sleep_avg')),
        reason: 'a pattern in one person’s history is not a research note',
      );
      await tester.tap(dotIn(find.byType(ReasoningNote)));
      await tester.pumpAndSettle();

      expect(find.text('your own data · overnight HRV'), findsOneWidget);
      expect(find.text(kSingleSubjectFraming), findsOneWidget);
    });

    testWidgets('THE GRADE IS SHOWN ONLY WHERE THE PAYLOAD SENT ONE', (
      tester,
    ) async {
      // Never derived from an id. `citation_row.dart` has the argument: a second
      // grade that can disagree with the corpus is #83 rebuilt one layer down.
      await pumpAt(
        tester,
        390,
        ProviderScope(
          overrides: [
            generatedInsightProvider('activity', '').overrideWith(
              (ref) async => GeneratedInsight.fromJson(const <String, Object?>{
                'insight': 'Your recovery supports it [recovery_readiness].',
                'citations': <String>[],
                'grade_floor': null,
                'validated': true,
              }),
            ),
          ],
          child: const InsightCard(scope: 'activity'),
        ),
      );
      await tester.tap(find.text('Coach analysis'));
      await tester.pumpAndSettle();

      expect(detailIn(tester, find.byType(InsightCard)).grade, isNull);
      await tester.tap(dotIn(find.byType(InsightCard)));
      await tester.pumpAndSettle();

      expect(find.text(noteName('recovery_readiness')!), findsOneWidget);
      for (final grade in <String>['ESTABLISHED', 'PROBABLE', 'EMERGING']) {
        expect(
          find.text(grade),
          findsNothing,
          reason: 'the payload sent no grade and the sheet invented "$grade"',
        );
      }
    });
  });
}
