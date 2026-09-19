/// What the owner looks at while the coach thinks — for up to five minutes.
///
/// It replaced `LoadingState(label: 'Asking your coach')`: one 16 px spinner and
/// four words, held for a wait that was **measured at 80–304 seconds** on the
/// owner's own broad question. A spinner is a fine way to say "a moment"; held
/// for four minutes it says "this has hung", and the owner's own report was that
/// the coach "takes insane amount of time" — which was true, and the screen was
/// doing nothing to make the time legible.
///
/// ## The stage shown is the wire's, never invented
///
/// `POST /api/coach/stream` names its own progress (`data/coach/coach_stream_
/// event.dart`'s `CoachStage`), so this widget can say what the server is
/// actually doing instead of a description of the whole operation. The rule
/// this file was built to keep is unchanged, only its instrument improved: a
/// stepper advancing on a TIMER would be inventing server state and showing it
/// as fact, which is the exact move the honesty contract forbids. [progress]
/// is null until the first `stage` event lands — before that, and against an
/// older server that falls back to the non-streaming call, this widget says
/// exactly what it always said, because that is still all it knows.
///
/// So what is shown is only what is actually known:
///
/// * the elapsed time, counted here and true by construction;
/// * [progress]'s own stage, worded by [coachStageLabel] — or, before the
///   first one arrives, the same whole-operation sentence this screen showed
///   before streaming existed;
/// * after [_longAfter], a second sentence saying the wait is longer than usual
///   and that broad questions take more rounds. That is a statement about the
///   distribution, not about this request, and it is the honest way to say
///   "still working" without pretending to know why.
///
/// ## "You can leave this screen"
///
/// The one piece of genuinely useful news, and it is checked rather than hoped:
/// `CoachController` is `@Riverpod(keepAlive: true)`, so the request is owned by
/// the provider and not by this widget. Popping the route does not cancel it and
/// the answer is in the thread on return. Told to the owner because a four-minute
/// wait they are required to sit through is a different product from one they can
/// walk away from.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';

/// The panel shown while a question is in flight.
class CoachWaiting extends StatefulWidget {
  /// [progress] is the latest stage `CoachController` has seen for this
  /// question, or null before the first one arrives.
  const CoachWaiting({this.progress, super.key});

  /// The stage to describe. Null draws the pre-streaming sentence.
  final CoachStageEvent? progress;

  @override
  State<CoachWaiting> createState() => _CoachWaitingState();
}

/// The default description, before any [CoachStageEvent] has arrived — the
/// exact sentence this screen showed before streaming existed, and what it
/// still shows against a server old enough to fall back to the plain call.
const String _beforeAnyStage =
    'Reading your own data and the graded research, then writing an answer '
    'that cites both.';

/// [progress]'s own words, in this app's copy — never the wire's raw name.
///
/// Public so a test can pin the mapping directly rather than only through the
/// widget it feeds.
String coachStageLabel(CoachStageEvent progress) => switch (progress.stage) {
  CoachStage.context => 'Reading your data',
  CoachStage.thinking => 'Thinking it through',
  CoachStage.tool => _toolLabel(progress.detail),
  CoachStage.checking => 'Checking the citations',
  CoachStage.revising => 'Rewording to match the evidence',
};

/// The named tools get their own sentence; anything else is still true and
/// still honest without naming a tool the owner has never heard of.
String _toolLabel(String? tool) => switch (tool) {
  'query_metric' => 'Looking at your numbers',
  'compare_event' => 'Comparing your days',
  'get_knowledge' => 'Checking the research',
  'sleep_consistency' => 'Looking at your sleep pattern',
  _ => 'Looking something up',
};

/// When the wait stops being ordinary. The measured distribution on the owner's
/// own broad question was 80 · 82 · 132 · 169 · 277 · 304 s, so a minute is well
/// inside "normal" and saying so early would be crying wolf at the median.
const Duration _longAfter = Duration(seconds: 75);

class _CoachWaitingState extends State<CoachWaiting>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late final AnimationController _pulse;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // One second is the coarsest tick that still reads as a live clock. Anything
    // finer would repaint sixty times a minute to move a digit that changes once.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bool long = _elapsed >= _longAfter;
    return Container(
      padding: const EdgeInsets.all(Insets.xl),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(
          Radii.card,
          side: BorderSide(color: colors.line, width: hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              FadeTransition(
                opacity: _pulse.drive(Tween<double>(begin: 0.35, end: 1)),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  'Your coach is working',
                  style: TypeScale.panelTitle.copyWith(color: colors.ink),
                ),
              ),
              Text(
                _clock(_elapsed),
                style: TypeScale.panelUnit.copyWith(
                  color: colors.ink3,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Text(
            widget.progress == null
                ? _beforeAnyStage
                : coachStageLabel(widget.progress!),
            style: TypeScale.panelNote.copyWith(color: colors.ink2),
          ),
          if (long) ...<Widget>[
            const SizedBox(height: Insets.sm),
            Text(
              'This is taking longer than most questions. Broad questions need '
              'more rounds — it has not failed.',
              style: TypeScale.panelNote.copyWith(color: colors.ink2),
            ),
          ],
          const SizedBox(height: Insets.md),
          Text(
            'You can leave this screen. The answer will be here when you come '
            'back.',
            style: TypeScale.panelNote.copyWith(color: colors.ink3),
          ),
        ],
      ),
    );
  }
}

/// Elapsed time as `m:ss`, or `s` under a minute.
///
/// Public for the test, which asserts the format rather than pumping a clock:
/// the thing worth pinning is that a four-minute wait reads as `4:03` and not as
/// `243` — the second is a number the owner has to convert before it means
/// anything, at the moment they are least inclined to.
String coachElapsedLabel(Duration elapsed) => _clock(elapsed);

String _clock(Duration elapsed) {
  final int seconds = elapsed.inSeconds;
  if (seconds < 60) {
    return '${seconds}s';
  }
  final String rest = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$rest';
}
