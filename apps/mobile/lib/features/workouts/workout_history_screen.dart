/// **Every session this server holds** — the days and
/// the week's strength.
///
/// **This is the v02 prototype's screen, in the prototype's order.**
/// `design/mobile-preview/screens-explore.js::H.screens.workouts`, top to
/// bottom:
///
/// ```text
///   header (detail)          Activity history        Your workouts.
///   <p class="small">        what this list is, and what it leaves out
///   .tiny-label + .card      one caption and one flush card per day
///   Weekly strength          the minutes, and what they are not counted against
///   footer
/// ```
///
/// ## What survived the redesign
///
/// The data wiring, whole: `workoutHistoryProvider` and its parse are untouched,
/// and so is the empty state's promise about what the list contains. The
/// `ListTile` subtitle that carried *"Latest 100 uploaded sessions · at least 10
/// minutes"* is now a sentence above the sessions, because it is a **limit on this
/// list** rather than a row in it — a reader who meets the rows first has no way
/// to know the list is bounded.
///
/// ## Why the strength card reads the Today payload
///
/// `read/activity.py` does not carry a `strength` block — only `/api/today`
/// does, and `IntensityPanel` on Activity already draws it. So this card reads
/// **the same field from the same provider**: one definition of the week's
/// strength minutes, drawn on two screens, rather than a second one computed
/// from this screen's own session list. A payload with no strength block draws
/// no card at all, because there is then no band for a figure to sit against
/// (`strength.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/models/strength.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/data/workouts/workout_repository.dart';
import 'package:healthee/data/workouts/workout_summary.dart';
import 'package:healthee/features/workouts/v02/session_rows.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/surface_cards.dart' show SmallProse;
import 'package:healthee/shared/v02/surface_panels.dart' show Notice;
import 'package:healthee/shared/v02/view_day.dart';

/// `.section { margin-top: 24px }`.
const double kWorkoutsSectionGap = 24;

/// What this list is bounded by. The server's own limit, said out loud.
const String kHistoryBounds =
    'The latest 100 uploaded sessions of at least ten minutes. A shorter '
    'session is recorded on the strap and is not listed here.';

/// The empty state's heading and its remedy.
const String kNoSessionsTitle = 'No uploaded sessions yet';

/// Its sentence.
/// What Workouts cannot date. `screens.workouts` refuses the same block.
const String kStrengthPastTitle = 'This week’s strength work';

/// The empty state on a past day, which is a different claim.
const String kNoSessionOnDayTitle = 'No session on or before this day';

/// And what it does not mean.
const String kNoSessionOnDayBody =
    'This does not mean you were inactive. It means the server holds no '
    'uploaded session dated on or before the day you are viewing.';

const String kNoSessionsBody =
    'Start a workout on the strap and sync. This list shows what the server '
    'holds, so a session still on the strap has not reached it yet.';

/// The recorded-workouts list.
class WorkoutHistoryScreen extends ConsumerWidget {
  /// Builds the screen.
  const WorkoutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workoutHistoryProvider;
    final ViewDay day = watchViewDay(ref);
    return DetailPage(
      title: 'Your workouts.',
      eyebrow: day.line,
      children: <Widget>[
        const SmallProse(kHistoryBounds),
        const SizedBox(height: kWorkoutsSectionGap),
        AsyncView<List<WorkoutSummary>>(
          value: currentAccountValue(ref.watch(provider)),
          onRetry: () => ref.invalidate(provider),
          builder: (context, sessions) => _days(context, sessions, day),
        ),
        // `/api/today`'s week-to-date strength block, and it takes no day. On
        // an older date it would be this week's sets under last week's heading,
        // so it is replaced by the reason it is not there.
        if (day.isPast)
          const PastDayNotice(title: kStrengthPastTitle, body: kPastDayReason)
        else if (_strength(ref) case final Strength week) ...<Widget>[
          const SizedBox(height: kWorkoutsSectionGap),
          const SectionHead(title: StrengthCard.title),
          StrengthCard(strength: week),
        ],
        const DataFooter(),
      ],
    );
  }

  /// One caption and one flush card per local day, newest day first.
  Widget _days(BuildContext context, List<WorkoutSummary> raw, ViewDay day) {
    // The list ends on the day being read, the way every history view in the
    // prototype does (`H.historySeries` filters `date <= viewDate`). A session
    // recorded after the chosen day is not evidence about it.
    final sessions = <WorkoutSummary>[
      for (final session in raw)
        if (session.start.toLocal().toIso8601String().substring(0, 10)
                .compareTo(day.day) <=
            0)
          session,
    ];
    if (sessions.isEmpty) {
      return Notice(
        title: day.isPast ? kNoSessionOnDayTitle : kNoSessionsTitle,
        body: day.isPast ? kNoSessionOnDayBody : kNoSessionsBody,
      );
    }
    final days = byDay(sessions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < days.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: kWorkoutsSectionGap),
          WorkoutDayGroup(
            date: days[i].date,
            sessions: days[i].sessions,
            onOpen: (workout) => unawaited(
              context.push(
                '${Routes.workout}?start='
                '${Uri.encodeComponent(workout.start.toUtc().toIso8601String())}',
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// This week's strength block, or null when Today has not answered yet.
  ///
  /// Read off the value rather than through an `AsyncView`: the Today payload's
  /// failure is reported on the screens that are ABOUT it, and a workouts list
  /// that showed a retry card for a block it merely borrows would be reporting
  /// somebody else's error twice. `metric_explorer_screen.dart` reads the same
  /// provider the same way.
  Strength? _strength(WidgetRef ref) =>
      currentAccountValue(ref.watch(todaySnapshotProvider))
          .value
          ?.snapshot
          .strength;
}
