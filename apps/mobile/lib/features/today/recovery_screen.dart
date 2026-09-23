/// `Recovery, in context.` — the prototype's `#recovery`, opened from Today's
/// hero summary row.
///
/// `design/mobile-preview/screens-daily.js`, read top to bottom:
///
/// ```text
///   header                       Recovery, in context.
///   Recovery, explained          the number, the weights, the four factor bars
///   Compared with your baseline  each signal against its own normal
///   context bridge               sleep's share, and what a night holds
///   Capacity changes …           overnight against remaining, and the effort
///   ⓘ                            method, weighting and limitations
///   footer
/// ```
///
/// The prototype's `Your body overnight` is not drawn here: Sleep draws the
/// same five measurements, and the bridge above it already leads there (R2,
/// `DESIGN_DECISIONS.md`).
///
/// ## Nothing here is a second reading
///
/// Every figure comes off the same `/api/today` payload Today draws, and
/// `RecoveryPanel` is literally Today's widget. A detail screen that re-derived
/// the number it exists to explain could disagree with the card that opened it,
/// which is the one failure a "details" screen must not have.
///
/// The prototype's `Details` link on `Recovery, explained` points at `#recovery`
/// — this screen — so it is dropped here rather than drawn as a control that
/// reloads what is already on screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/models/recovery_signals.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/today/v02/recovery_detail_panels.dart';
import 'package:healthee/features/today/v02/recovery_panel.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_history.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/view_day.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

/// The prototype's own title, full stop included.
const String kRecoveryTitle = 'Recovery, in context.';

/// `screens.recovery`'s past-day heading, with the app's own reason under it.
const String kRecoveryPastTitle = 'Recovery & readiness';

/// The recovery detail screen.
class RecoveryScreen extends ConsumerStatefulWidget {
  /// [now] is injected by tests so the derived labels are deterministic.
  const RecoveryScreen({this.now, super.key});

  /// The instant this render is measured against.
  final DateTime? now;

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  /// Outlives every panel, which is the whole reveal-once mechanism.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final ViewDay day = watchViewDay(ref);
    // The SCORE is `/api/today`'s and that endpoint takes no day, so a past
    // date still gets the refusal — before the read is even consulted, because
    // a spinner here would be waiting for an answer that could not be about the
    // day in the header.
    //
    // What a past day now also gets is `screens.recovery`'s dated panels: the
    // four measurements the model is computed FROM, each on the calendar it was
    // measured on. They are readings, not judgements, so they are as true of
    // 24 July as of today — and having them under the refusal is the difference
    // between "we will not say" and "there is nothing here".
    if (day.isPast) {
      return _Frame(
        date: day.day,
        status: day.status,
        children: pastDayDetail(
          refusalTitle: kRecoveryPastTitle,
          history: ref.watch(datedHistoryProvider),
          // `panels(['hrv','rhr','breathing','sleep','load'])`, less the one
          // this server keeps no dated series for.
          metrics: const <HistoryMetric>[
            HistoryMetric.hrv,
            HistoryMetric.restingHr,
            HistoryMetric.breathing,
            HistoryMetric.cardioLoad,
          ],
          unserved: const <String>[kUnservedSleepDuration],
          day: day.day,
          reveals: _reveals,
          onRetry: () => ref.invalidate(datedHistoryProvider),
          onOpenMetric: (metric) => openMetricHistory(context, metric),
        ),
      );
    }
    final view = currentAccountValue(ref.watch(todaySnapshotProvider));
    return view.when(
      skipLoadingOnRefresh: true,
      loading: () => const _Frame(
        children: <Widget>[LoadingState(label: 'Reading your recovery')],
      ),
      error: (error, stackTrace) => _Frame(
        children: <Widget>[
          ErrorState(
            message: "Couldn't reach your server for your recovery",
            detail: 'This is a connection problem, not a gap in your data.',
            onRetry: () => ref.invalidate(todaySnapshotProvider),
          ),
        ],
      ),
      data: (value) => RecoveryDetail(
        snapshot: value.snapshot,
        now: widget.now ?? DateTime.now(),
        reveals: _reveals,
      ),
    );
  }
}

/// The screen's body. Public so the screen tests can host it directly.
class RecoveryDetail extends StatelessWidget {
  /// Builds the detail for one render of `/api/today`.
  const RecoveryDetail({
    required this.snapshot,
    required this.now,
    required this.reveals,
    super.key,
  });

  /// The payload every figure on this screen comes off.
  final TodaySnapshot snapshot;

  /// The instant the labels are measured against.
  final DateTime now;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final score = snapshot.recovery.valueOrNull;
    return _Frame(
      date: snapshot.date,
      children: <Widget>[
        ReadingView<RecoveryScore>(
          reading: snapshot.recovery,
          label: 'Recovery',
          caveatCarrier: CaveatCarrier.insideCard,
          withheldBuilder: (context, disclosure) =>
              WithheldPanel(disclosure: disclosure, label: 'Recovery'),
          builder: (context, value) => RecoveryPanel(score: value),
        ),
        if (snapshot.recoverySignals.valueOrNull case final RecoverySignals s)
          ...<Widget>[
            const SizedBox(height: _Frame.panelGap),
            BaselinePanel(
              signals: s,
              onDetails: () => unawaited(context.push(Routes.history)),
            ),
          ],
        if (score != null) ...<Widget>[
          ContextBridge.link(
            sleepShareBridge(sleepWeight(score)),
            label: 'Explore your sleep',
            onOpen: () => unawaited(context.push(Routes.sleep)),
          ),
        ],
        if (score != null) ...<Widget>[
          const SizedBox(height: _Frame.panelGap),
          CapacityPanel(
            score: score,
            load: snapshot.cardioLoad.valueOrNull,
            reveals: reveals,
            onDetails: () => unawaited(context.push(Routes.activity)),
          ),
        ],
        const SizedBox(height: _Frame.blockGap),
        Align(
          alignment: Alignment.centerLeft,
          child: MetricInfoDot(
            'recovery_score',
            detail: MetricDetail(
              notes: <String>[if (score?.noteId case final String id) id],
            ),
            fallbackTitle: 'Recovery',
          ),
        ),
        const SizedBox(height: _Frame.blockGap),
        const DataFooter(),
      ],
    );
  }
}

/// The page every state of this screen is drawn in, so the head and the gutter
/// cannot differ between them.
class _Frame extends StatelessWidget {
  const _Frame({required this.children, this.date, this.status = kLatestSample});

  /// `.panel { margin-top: 12px }`.
  static const double panelGap = 12;

  /// `.section { margin-top: 24px }`.
  static const double blockGap = 24;

  final List<Widget> children;
  final String? date;

  /// `Latest sample` unless the caller says otherwise: the only body below is
  /// `/api/today`'s, which is the current day by construction.
  final String? status;

  @override
  Widget build(BuildContext context) => DetailPage(
    title: kRecoveryTitle,
    eyebrow: dayEyebrow(date, status),
    children: children,
  );
}
