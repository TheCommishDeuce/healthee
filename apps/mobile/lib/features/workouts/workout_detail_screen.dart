/// One recorded session, on the v02 detail frame.
///
/// Composition and wiring only. `workout_detail_sections.dart` decides what this
/// screen shows and in what order, and it carries the argument for that order;
/// `history_screen.dart` has the same shape for the same reason.
///
/// **Stateful for one field.** `RevealRegistry` must outlive the widget that
/// reads it, or a chart in a `ListView` replays its reveal every time it scrolls
/// back into view — `CLAUDE.md` names that failure and `reveal_once.dart` is the
/// fix. The registry belongs to the screen, not to the card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/workouts/workout_detail.dart';
import 'package:healthee/data/workouts/workout_repository.dart';
import 'package:healthee/features/workouts/workout_detail_sections.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/detail_page.dart';

/// The workout screen.
class WorkoutDetailScreen extends ConsumerStatefulWidget {
  /// [start] is the session's start instant, as it came in on the route.
  const WorkoutDetailScreen({required this.start, super.key});

  /// The route's `start` parameter, passed to the provider unchanged.
  final String start;

  @override
  ConsumerState<WorkoutDetailScreen> createState() =>
      _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends ConsumerState<WorkoutDetailScreen> {
  /// The screen's own registry — see the library docstring.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final provider = workoutDetailProvider(widget.start);
    final view = currentAccountValue(ref.watch(provider));
    final loaded = view.value;
    return DetailPage(
      // The session's own name and instant, once they are known. Until then the
      // frame still opens with a back control and a heading, rather than a bare
      // spinner on a page with no way off it.
      title: loaded == null ? 'Workout.' : '${loaded.workout.sportName}.',
      eyebrow: loaded == null ? null : sessionInstant(loaded),
      children: <Widget>[
        AsyncView<WorkoutDetail>(
          value: view,
          onRetry: () => ref.invalidate(provider),
          builder: (context, detail) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: workoutDetailSections(detail, _reveals),
          ),
        ),
      ],
    );
  }
}

/// `31 Jul · 07:00` — the day and the clock the session started on, local.
///
/// [shortDate] and [clockLabel] are the app's own two forms, so this screen's
/// header reads the same way as every other dated header in the build. The
/// prototype writes `31 July · 07:00`; a third date format would be a third
/// opinion about the same instant (`session_rows.dart` records the same call).
String sessionInstant(WorkoutDetail detail) {
  final local = detail.workout.start.toLocal();
  return '${shortDate(local.toIso8601String())} · ${clockLabel(local)}';
}
