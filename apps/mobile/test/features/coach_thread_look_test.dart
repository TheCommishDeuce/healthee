// The coach thread, rendered — the lead's look loop without a device.
//
// Opt-in: goldens depend on the host's font rasteriser, so CI never compares
// them. Run `HEALTHEE_LOOK=1 flutter test test/features/coach_thread_look_test.dart
// --update-goldens` and open test/goldens/coach_*.png.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/v02/coach_waiting.dart';
import 'package:healthee/features/coach/widgets/coach_thread.dart';

const String _draftSoFar =
    'Your last seven nights averaged 6 h 20 of sleep against an 8-hour '
    'need, so the debt you are carrying is real rather than a rounding '
    'error. Timing is not the';

final bool _look = Platform.environment['HEALTHEE_LOOK'] == '1';

const String _question =
    'How did I sleep this week and is there one thing to change tonight?';

const CoachAnswer _answer = CoachAnswer(
  reply:
      'Your last seven nights averaged 6 h 20 of sleep against an 8-hour '
      'need, so the debt you are carrying is real rather than a rounding '
      'error [sleep_need_debt]. Timing is not the problem: bedtime and wake '
      'time barely moved all week [sleep_regularity_index].\n\n'
      'The one thing worth changing tonight is the caffeine cut-off. Your own '
      'log shows worse sleep on days with a late coffee, and the evidence '
      'puts a 400 mg dose six hours before bed at about an hour of lost '
      'sleep [caffeine_sleep]. Move the last one before 2 pm and hold the '
      'wake time where it is.',
  citations: <String>[
    'sleep_need_debt',
    'sleep_regularity_index',
    'caffeine_sleep',
  ],
  gradeFloor: 'Probable',
  refused: false,
  validated: true,
);

Widget _thread(List<Widget> children, {required bool dark}) => MaterialApp(
  theme: dark ? AppTheme.dark : AppTheme.light,
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: children,
      ),
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, Widget app, String name) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('../goldens/$name.png'),
  );
}

void main() {
  setUpAll(() async {
    // The real face, so the shot shows words rather than the test font's boxes.
    final loader = FontLoader('Figtree')
      ..addFont(rootBundle.load('assets/fonts/Figtree.ttf'));
    await loader.load();
  });

  for (final dark in <bool>[false, true]) {
    final String mode = dark ? 'dark' : 'light';

    testWidgets('typing — $mode', (tester) async {
      await _shoot(
        tester,
        _thread(<Widget>[
          const CoachEntryView(entry: OwnerQuestion(_question)),
          const CoachWaiting(
            progress: CoachStageEvent(
              stage: CoachStage.tool,
              round: 1,
              detail: 'query_metric',
            ),
          ),
        ], dark: dark),
        'coach_typing_$mode',
      );
    }, skip: !_look);

    testWidgets('drafting — $mode', (tester) async {
      await _shoot(
        tester,
        _thread(<Widget>[
          const CoachEntryView(entry: OwnerQuestion(_question)),
          const CoachWaiting(
            progress: CoachStageEvent(stage: CoachStage.thinking, round: 1),
            draft: CoachDraft(round: 1, text: _draftSoFar),
          ),
        ], dark: dark),
        'coach_drafting_$mode',
      );
    }, skip: !_look);

    testWidgets('answered — $mode', (tester) async {
      await _shoot(
        tester,
        _thread(<Widget>[
          const CoachEntryView(entry: OwnerQuestion(_question)),
          const CoachEntryView(entry: CoachReply(_answer)),
          const CoachEntryView(entry: OwnerQuestion('And what about naps?')),
          const CoachWaiting(
            progress: CoachStageEvent(stage: CoachStage.thinking, round: 1),
          ),
        ], dark: dark),
        'coach_answered_$mode',
      );
    }, skip: !_look);
  }
}
