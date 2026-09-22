/// **One metric's own history** — the figure for the day, the series behind it,
/// and every plotted reading.
///
/// `screens-explore.js::H.screens.metric`, read top to bottom:
///
/// ```text
///   header (detail)        <date> · Latest        Heart-rate variability.
///   .metric-hero           Latest · 31 July / 45 ms
///   .segment.section       30 days · 90 days · 1 year · 5 years
///   .card.section          the chart, Mean/Median/Change, the readings
///   section                Put this in context   (removed with journal and coach)
///   evidence               Source & limitations
///   footer
/// ```
///
/// ## The date follows the reader, and the chart stops on it
///
/// `history-data.js::H.historySeries` filters every history view to
/// `date <= viewDate`, which is what makes a past day a past day rather than
/// today's chart under an older heading. This screen does the same, and it is
/// the one place in this app that can honestly do it: `/api/history` is dated
/// per day, unlike `/api/today`, which answers for the current day only and is
/// why `today_sections.dart` refuses the past-day judgement half outright.
///
/// ## Three things the prototype draws that this screen does not
///
///   * **The hero's sentence.** The prototype writes a paragraph per metric
///     into `H.metricDefinitions[key].copy`. This app already has that prose,
///     graded and cited, behind the ⓘ (`shared/metric_info/`), and printing it
///     on the hero as well would be the same words twice — with the copy on the
///     card being the one nothing validates.
///   * **The dashed personal median and its legend.** `history_panel.dart`
///     argues it: a baseline is the server's, never the client's.
///   * **The `.source` line.** The prototype's says *"Helio Strap · sample day,
///     31 Jul"*, which is provenance for its own fixture. Real provenance
///     differs per metric and lives in `MetricDetail`, behind the ⓘ — the
///     surface the owner asked us to move exactly this material to.
///
/// ## What the redesign kept
///
/// The data wiring, whole. `metricHistoryProvider` and its parse rules are
/// untouched, the period control offers the same four windows, and the log
/// markers `HistoryExplorer` used to draw on the chart's foot are still
/// reachable — as their own disclosure, under the readings, rather than as
/// ticks nobody could read a date off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/history/history_marker.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/history/history_repository.dart';
import 'package:healthee/data/history/history_window.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/history/v02/dated_readings.dart';
import 'package:healthee/features/history/v02/history_panel.dart';
import 'package:healthee/features/history/v02/metric_hero.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/insight_card.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/choices.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/view_day.dart';
import 'package:solar_icons/solar_icons.dart';

/// The four windows `H.segment` offers, in its order.
const List<(int, String)> kHistoryPeriods = <(int, String)>[
  (30, '30 days'),
  (90, '90 days'),
  (365, '1 year'),
  (1825, '5 years'),
];

/// `H.evidence(metric.note, 'Source & limitations')`.
const String kEvidenceLabel = 'Source & limitations';

/// One metric's dated series, on the v02 detail frame.
class HistoryScreen extends ConsumerStatefulWidget {
  /// [initialMetric] is the canonical id the caller came in with.
  const HistoryScreen({this.initialMetric, super.key});

  /// The metric to open. An unknown id falls back to the table's first entry
  /// rather than drawing an empty screen for a name nothing serves.
  final String? initialMetric;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final HistoryMetric _metric =
      HistoryMetric.values
          .where((m) => m.id == widget.initialMetric)
          .firstOrNull ??
      HistoryMetric.hrv;
  int _days = 90;

  /// The height the body is held at while a new period loads.
  ///
  /// The hero, the chart and its figures — enough that nothing below moves
  /// between one period and the next. It is a floor rather than a fixed height:
  /// a long window with many dated readings is taller, and being taller than
  /// the floor costs nothing.
  static const double bodyFloor = 420;

  /// The screen's own registry, so a chart reveals once per visit and not once
  /// per scroll. `CLAUDE.md`: a scrollable chart screen either does this or
  /// replays every animation on the way back up.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final provider = metricHistoryProvider(_metric, _days);
    // One wording for the whole app. This screen had `· Latest` while the
    // prototype and every other date-aware head say `· Latest sample`, which is
    // exactly the drift `shared/format/` exists to stop.
    final ViewDay day = watchViewDay(ref);
    final String viewDate = day.day;
    final bool past = day.isPast;
    return DetailPage(
      title: '${metricTitle(_metric.id)}.',
      eyebrow: day.line,
      children: <Widget>[
        // **The period control is OUTSIDE the async body it drives.** It used
        // to live inside `_body`, under the `AsyncView` — so selecting a new
        // period built a new `metricHistoryProvider(_metric, _days)` family
        // member with no cached value, the view swapped to its loading state,
        // and the segment the owner had just pressed was destroyed and rebuilt
        // along with the hero, the chart and the markers. Every tap re-rendered
        // the whole screen and the control vanished under the finger.
        //
        // Up here it depends on `_days` alone, which is local state, so it
        // survives the fetch it starts.
        Segment<int>(
          options: kHistoryPeriods,
          selected: _days,
          onSelect: (days) => setState(() => _days = days),
        ),
        const SizedBox(height: HistoryPanel.sectionGap),
        // **The slot is held while the new period loads.** Without the floor
        // the body collapses to a one-line `Loading…`, and the context card,
        // the evidence link and the analysis below it jump up half a screen
        // and back down again — which is what made changing the period feel
        // like the whole screen re-rendering rather than one chart changing.
        //
        // Same argument as `ChartVoid`'s, and the same refusal: the previous
        // period's series is NOT held over under the new period's label. A
        // 90-day line under `1 year` is stale-as-current, and the reader has
        // no way to tell it from the real one.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: bodyFloor),
          child: AsyncView<List<TrendPoint>>(
            value: currentAccountValue(ref.watch(provider)),
            onRetry: () => ref.invalidate(provider),
            builder: (context, points) =>
                _body(HistoryWindow(points).through(viewDate), past, viewDate),
          ),
        ),
        // Drawn only when there is something behind it. `showMetricInfo` is a
        // no-op for a metric with neither an explainer nor payload provenance,
        // and a labelled control that opens nothing is worse than no control.
        if (kMetricInfo.containsKey(explainerKeyFor(_metric.id))) ...<Widget>[
          const SizedBox(height: HistoryPanel.sectionGap),
          TextLink(
            label: kEvidenceLabel,
            icon: SolarIconsOutline.infoCircle,
            iconLeading: true,
            onPressed: () => showMetricInfo(
              context,
              explainerKeyFor(_metric.id),
              detail: MetricDetail(title: metricTitle(_metric.id)),
              fallbackTitle: metricTitle(_metric.id),
            ),
          ),
        ],
        // Not a prototype section. A grounded, server-written reading of this
        // metric's own numbers, kept for the reason `activity_sections.dart`
        // keeps its own: a reachable server surface is not deleted because the
        // mock-up has no box for it. Draws nothing when the server has nothing.
        InsightCard(scope: 'metric', target: _metric.id),
        const SizedBox(height: HistoryPanel.sectionGap),
        const DataFooter(),
      ],
    );
  }

  /// The hero, the period control and the card, in the prototype's order.
  Widget _body(HistoryWindow window, bool past, String viewDate) {
    final reading = window.on(viewDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MetricHero(
          label: past
              ? shortDate(viewDate)
              : 'Latest · ${shortDate(viewDate)}',
          value: reading == null ? null : decimalLabel(reading),
          unit: _metric.unit,
          context_: reading == null ? kNoReadingOnDay : null,
        ),
        const SizedBox(height: HistoryPanel.sectionGap),
        HistoryPanel(
          metric: _metric.id,
          unit: _metric.unit,
          window: window,
          reveals: _reveals,
        ),
        _markers(),
      ],
    );
  }

  /// `Your logs in this period` — the journal entries that fall in the window.
  ///
  /// The pre-v02 screen drew these as 4×6 px ticks along the chart's foot,
  /// which said a log existed on some day near there. The same rows behind a
  /// disclosure say which day and how many, and the chart keeps its own axis.
  Widget _markers() {
    final provider = historyMarkersProvider(_days);
    final markers = currentAccountValue(ref.watch(provider)).value;
    return DatedReadings(
      summary: 'Your logs in this period',
      columns: ('Day', 'Entries'),
      rows: <ReadingRow>[
        for (final marker in markers ?? const <HistoryMarker>[])
          ReadingRow(
            '${shortDate(marker.day)} · ${marker.kind}',
            marker.count.toString(),
          ),
      ],
    );
  }
}

/// What an empty day means. The prototype's `'No reading on this day'`.
const String kNoReadingOnDay =
    'No reading on this day. The chart below stops on it, and missing days stay '
    'gaps rather than being joined up.';
