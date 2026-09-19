/// The waiting state is the screen for up to five minutes, so what it claims matters.
///
/// The defect it replaced was a 16 px spinner and the words "Asking your coach",
/// held through a wait measured at 80-304 s. These pin the two things that could
/// go wrong in the other direction: a clock that is unreadable at the durations
/// that actually occur, and a screen that starts inventing what the server is doing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/features/coach/v02/coach_waiting.dart';

/// The widget under a theme, which is all it needs — it reads tokens and nothing else.
Future<void> pumpApp(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('the elapsed clock', () {
    test('reads as seconds under a minute', () {
      expect(coachElapsedLabel(const Duration(seconds: 0)), '0s');
      expect(coachElapsedLabel(const Duration(seconds: 45)), '45s');
      expect(coachElapsedLabel(const Duration(seconds: 59)), '59s');
    });

    test('reads as m:ss at the durations this wait actually reaches', () {
      // The measured distribution: 80 · 82 · 132 · 169 · 277 · 304 s. Every one
      // of them has to be readable at a glance — "304" is a number the owner has
      // to convert at the moment they are least inclined to.
      expect(coachElapsedLabel(const Duration(seconds: 80)), '1:20');
      expect(coachElapsedLabel(const Duration(seconds: 132)), '2:12');
      expect(coachElapsedLabel(const Duration(seconds: 169)), '2:49');
      expect(coachElapsedLabel(const Duration(seconds: 304)), '5:04');
    });

    test('pads the seconds, so 4:03 never renders as 4:3', () {
      expect(coachElapsedLabel(const Duration(seconds: 243)), '4:03');
      expect(coachElapsedLabel(const Duration(minutes: 2)), '2:00');
    });
  });

  group('what it says while it waits', () {
    testWidgets('describes the work without claiming a stage', (tester) async {
      await pumpApp(tester, const CoachWaiting());

      expect(find.text('Your coach is working'), findsOneWidget);
      expect(
        find.textContaining('Reading your own data and the graded research'),
        findsOneWidget,
      );
      // THE rule for this widget. The app holds one synchronous request and
      // cannot know which round the server is on, so any of these would be the
      // screen inventing server state and drawing it as fact.
      for (final String invented in <String>[
        'Checking the research',
        'Reading your sleep',
        'Writing your answer',
        'Step 1',
        'Almost done',
      ]) {
        expect(
          find.textContaining(invented),
          findsNothing,
          reason: 'the app cannot know this, so it must not say it',
        );
      }
    });

    testWidgets('tells the owner the request survives leaving', (tester) async {
      // True by construction: `CoachController` is keepAlive, so the request is
      // the provider's and not the route's. If that ever stops being true this
      // sentence becomes a lie, which is why it is asserted here.
      await pumpApp(tester, const CoachWaiting());

      expect(find.textContaining('You can leave this screen'), findsOneWidget);
    });

    testWidgets('says nothing about a long wait before one has happened', (
      tester,
    ) async {
      await pumpApp(tester, const CoachWaiting());
      await tester.pump(const Duration(seconds: 5));

      expect(find.textContaining('longer than most questions'), findsNothing);
    });

    testWidgets(
      'admits a long wait once it is one, and says it has not failed',
      (tester) async {
        await pumpApp(tester, const CoachWaiting());
        await tester.pump(const Duration(seconds: 80));

        expect(
          find.textContaining('longer than most questions'),
          findsOneWidget,
        );
        expect(find.textContaining('has not failed'), findsOneWidget);
      },
    );
  });

  group('the stage, once the wire has said one', () {
    // One case per line of the copy spec — a stage this widget shows is a
    // stage the server actually reported, and the wording is fixed, not
    // freely worded per call site.
    const cases = <(CoachStageEvent, String)>[
      (
        CoachStageEvent(stage: CoachStage.context, round: 1),
        'Reading your data',
      ),
      (
        CoachStageEvent(stage: CoachStage.thinking, round: 1),
        'Thinking it through',
      ),
      (
        CoachStageEvent(
          stage: CoachStage.tool,
          round: 1,
          detail: 'query_metric',
        ),
        'Looking at your numbers',
      ),
      (
        CoachStageEvent(
          stage: CoachStage.tool,
          round: 1,
          detail: 'compare_event',
        ),
        'Comparing your days',
      ),
      (
        CoachStageEvent(
          stage: CoachStage.tool,
          round: 1,
          detail: 'get_knowledge',
        ),
        'Checking the research',
      ),
      (
        CoachStageEvent(
          stage: CoachStage.tool,
          round: 1,
          detail: 'sleep_consistency',
        ),
        'Looking at your sleep pattern',
      ),
      (
        CoachStageEvent(stage: CoachStage.tool, round: 1, detail: 'log_entry'),
        'Looking something up',
      ),
      (
        CoachStageEvent(stage: CoachStage.tool, round: 1, detail: 'a_new_tool'),
        'Looking something up',
      ),
      (
        CoachStageEvent(stage: CoachStage.checking, round: 1),
        'Checking the citations',
      ),
      (
        CoachStageEvent(stage: CoachStage.revising, round: 1),
        'Rewording to match the evidence',
      ),
    ];

    for (final (progress, label) in cases) {
      testWidgets('${progress.stage.name}/${progress.detail} reads "$label"', (
        tester,
      ) async {
        await pumpApp(tester, CoachWaiting(progress: progress));

        expect(find.text(label), findsOneWidget);
        expect(
          find.textContaining('Reading your own data and the graded research'),
          findsNothing,
          reason: 'a known stage replaces the pre-streaming sentence',
        );
      });
    }

    testWidgets('coachStageLabel is the same mapping the widget renders', (
      tester,
    ) async {
      const progress = CoachStageEvent(
        stage: CoachStage.tool,
        round: 4,
        detail: 'get_knowledge',
      );

      expect(coachStageLabel(progress), 'Checking the research');
    });
  });
}
