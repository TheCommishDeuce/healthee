/// Insights — where the owner's own history is read back to them.
///
/// Composition only: the frame, the two data sources and the reveal registry are
/// `shared/instrument_screen.dart`'s, and `insights_sections.dart` decides what
/// this screen shows and in what order. This file is the wiring — the six places
/// the screen can reach — and nothing else.
///
/// This is `docs/APP_DESIGN.md` §2's fourth tab and legacy's (Today · Sleep ·
/// Activity · **Insights** · Actions). It holds the two things that are about
/// the *history* rather than about today: how each tracked metric has been
/// moving, and the correlations the analytics layer found in this one person's
/// data.
///
/// The findings used to be on a tab called Coach. That was wrong twice over —
/// the coach was never a tab in legacy (the interactive coach has since been
/// removed entirely), and the findings are not the coach: they are evidence
/// read from the owner's own history. The prototype ended this screen on a
/// coach prompt, `A useful question comes next`; that panel went with the coach.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/insights/notable_event.dart';
import 'package:healthee/features/insights/insights_sections.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/instrument_screen.dart';

/// The Insights tab.
class InsightsScreen extends ConsumerWidget {
  /// [now] is injected by tests so the freshness labels are deterministic.
  const InsightsScreen({this.now, super.key});

  /// The instant every "x min ago" is measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InstrumentScreen(
      now: now,
      onRefreshed: () => ref.invalidate(notableEventsProvider),
      sections: (ScreenData data) => insightsSections(
        data,
        InsightsExtras(
          // Pushed, never `go`: `go` REPLACES the location, which leaves the
          // destination with nothing beneath it and the next Back leaves the
          // app. `back_navigation_test.dart` owns that rule.
          onOpenProfile: () => unawaited(context.push(Routes.settings)),
          onOpenMetric: (metric) => openMetricHistory(context, metric),
          onOpenHistory: () => unawaited(context.push(Routes.history)),
          onOpenOutcomes: () => unawaited(context.push(Routes.outcomes)),
          onOpenSleepHistory: () =>
              unawaited(context.push(Routes.sleepHistory)),
          onOpenFitness: () => unawaited(context.push(Routes.fitness)),
        ),
      ),
    );
  }
}
