/// The ordered sections of one workout. Composition only — no widget is here.
///
/// **This is the v02 prototype's screen, in the prototype's order.**
/// `design/mobile-preview/screens-explore.js::H.screens.workout`, top to bottom:
///
/// ```text
///   header (detail)             31 Jul · 07:00        Outdoor run.
///   .card                       distance · duration · pace, and the source
///   Your effort through the run  the average, the peak, the minute trace
///   Time in heart-rate zones     five buckets, and what they are cut against
///   Session details              energy · load · speed · drift
///   workout analysis             this app's own — the prototype has no surface
///   footer
/// ```
///
/// ## What survived the redesign, and what did not
///
/// The **data wiring** survived whole: the same provider, the same parse, the
/// same fields. What replaced them is `workout_readings.dart`, which turns each
/// nullable into a [Reading] so an absent figure carries the reason it is absent
/// — the one thing the pre-v02 screen could not do, because
/// `/api/activity/workout` is the app's only payload with no honesty envelope.
///
/// Every figure the old screen listed is still on this one. `intensity` and
/// `avg_pct_hrmax` moved into the trace card's own sentence (`effort_cards.dart`
/// says why), `dominant_zone` is visible as the tallest bar rather than restated
/// underneath it, and `min_hr` is the one field that is gone: it was a third
/// heart rate beside an average and a peak, and the trace it was read off is now
/// drawn in full with a cursor that reports any minute on it.
///
/// ## The one section the prototype has no equivalent for
///
/// `InsightCard(scope: 'workout')` is a grounded, server-written reading of this
/// session. `activity_sections.dart` keeps its own for the reason this one is
/// kept: deleting a reachable server surface because the mock-up has no box for
/// it is a feature removal wearing a redesign's clothes. It sits after the
/// prototype's last control and renders nothing when the server has nothing.
library;

import 'package:flutter/material.dart';
import 'package:healthee/data/workouts/workout_detail.dart';
import 'package:healthee/data/workouts/workout_readings.dart';
import 'package:healthee/features/workouts/v02/effort_cards.dart';
import 'package:healthee/features/workouts/v02/session_cards.dart';
import 'package:healthee/shared/insight_card.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/section_head.dart';

/// `.section { margin-top: 24px }`.
const double kWorkoutSectionGap = 24;

/// The screen's body, in the prototype's order, without the prototype's
/// "Discuss this workout" control: the interactive coach was removed
/// (DESIGN_DECISIONS P3).
List<Widget> workoutDetailSections(
  WorkoutDetail detail,
  RevealRegistry reveals,
) {
  final readings = WorkoutReadings(detail);
  return <Widget>[
    SessionSummaryCard(readings: readings),
    const SizedBox(height: kWorkoutSectionGap),
    const SectionHead(title: EffortCard.title),
    EffortCard(readings: readings, reveals: reveals),
    const SizedBox(height: kWorkoutSectionGap),
    const SectionHead(title: ZonesCard.title),
    ZonesCard(readings: readings),
    const SizedBox(height: kWorkoutSectionGap),
    const SectionHead(title: SessionDetailsCard.title),
    SessionDetailsCard(readings: readings),
    const SizedBox(height: kWorkoutSectionGap),
    InsightCard(
      scope: 'workout',
      target: detail.workout.start.toIso8601String(),
      title: 'Workout analysis',
    ),
    const SizedBox(height: kWorkoutSectionGap),
    const DataFooter(),
  ];
}
