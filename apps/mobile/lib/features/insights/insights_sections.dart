/// The ordered sections of Insights. Composition only — no widget is defined here.
///
/// **This is the v02 prototype's screen, in the prototype's order.**
/// `design/mobile-preview/screens-overview.js::H.screens.insights`, read top to
/// bottom:
///
/// ```text
///   header                    date · Insights · avatar
///   relationship grid         one pattern of your own, and the age model
///   effort & stress           one hour cursor, two labelled scales
///   context bridge            what a sensor cannot see
///   your longer patterns      the tracked metrics, and `All metrics`
///   what changed together?    the findings, the notable days, the two ways in
///   a useful question comes next
///   footer
/// ```
///
/// ## The colour rule this screen exists to keep straight
///
/// Two blocks, two different licences for `fav`/`unf`:
///
/// | block | coloured? | why |
/// |---|---|---|
/// | **Your longer patterns** | yes, where polarity is known | a metric moving against the owner's own past, with a table that says which way is better (`shared/format/metric_polarity.dart`) |
/// | **What changed together?** | never | the sign of a rank correlation is a *direction* — together or opposite — and n-of-1 observational data cannot support "good for you" |
///
/// A neutral or unknown-polarity trend gets no colour either, which
/// `trends_section.dart` argues is the load-bearing case rather than the
/// leftover one.
///
/// ## What kept its pre-v02 carrier, and why
///
/// `FindingsSection` and `NotableEvents` are lists of **server prose with
/// citations attached** — grounded markdown, the single-subject framing, the
/// statistic behind a disclosure. The prototype has no equivalent: it shows a
/// card that links away to a screen where such content would live. Rebuilding
/// them in v02 chrome would mean rebuilding the citation surface with them,
/// which is a different piece of work and is where a `[personal_finding:…]`
/// marker would most easily start leaking again. Today made exactly this call
/// for `ActionsSection` and `InsightsSection`; these two keep their carriers and
/// gain the prototype's heading around them.
///
/// ## Two things that are deliberately NOT here
///
/// **The recovery signal ladder is on Today and stays there.** It renders the
/// server's own `direction` field, and CLAUDE.md allows one definition per
/// metric: computing a second opinion here would be free to disagree with the
/// first.
///
/// **There is no "days that stood out" block fed by `/api/today`'s
/// `anomalies`.** That endpoint does not scan for shifts: the key used to ship
/// `[]`, which is indistinguishable from "nothing was anomalous", and is `null`
/// now beside a reason pointing at `/api/notable`
/// (`docs/BACKEND_GAPS_FROM_UI.md` A3). Notable events on this tab IS that
/// endpoint, so a second section keyed on the Today payload would be a heading
/// that can never have anything under it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/features/insights/widgets/notable_events.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/shared/findings_section.dart';
import 'package:healthee/shared/format/metric_polarity.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_history.dart';
import 'package:healthee/shared/v02/entry_card.dart';
import 'package:healthee/shared/v02/list_rows.dart';
import 'package:healthee/shared/v02/page_header.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:solar_icons/solar_icons.dart';

/// What Insights cannot date. `screens.insights`'s own past-day heading.
const String kInsightsPastTitle = 'Patterns for this day';

/// Everything Insights needs that is not on [ScreenData].
@immutable
class InsightsExtras {
  /// The five places this screen can go.
  const InsightsExtras({
    this.onOpenProfile,
    this.onOpenMetric,
    this.onOpenHistory,
    this.onOpenOutcomes,
    this.onOpenSleepHistory,
    this.onOpenFitness,
  });

  /// Opens settings. The avatar's destination.
  final VoidCallback? onOpenProfile;

  /// Opens one metric's own history. A trend panel's `Details`.
  final void Function(String metric)? onOpenMetric;

  /// Opens the metric explorer. The section head's `All metrics`.
  final VoidCallback? onOpenHistory;

  /// Opens the challenge outcomes.
  final VoidCallback? onOpenOutcomes;

  /// Opens the sleep history — every night in the window.
  final VoidCallback? onOpenSleepHistory;

  /// Opens the fitness detail — VO₂max and its instrument.
  final VoidCallback? onOpenFitness;
}

/// `history-screens.js::screens.insights` — `panels([…])`, in its order.
///
/// ```js
/// panels(['hrv','rhr','efficiency','regularity','vo2','steps'])
/// ```
///
/// Five of the six. `efficiency` is the night's efficiency percentage, which
/// this server keeps on the sleep session and not as a daily series — see
/// [kInsightsUnserved].
const List<HistoryMetric> kInsightsDatedMetrics = <HistoryMetric>[
  HistoryMetric.hrv,
  HistoryMetric.restingHr,
  HistoryMetric.sleepRegularity,
  HistoryMetric.fitness,
  HistoryMetric.steps,
];

/// The one panel `screens.insights` draws that has no dated series here.
const List<String> kInsightsUnserved = <String>[kUnservedSleepEfficiency];

/// Builds the ordered section list for one render of Insights.
List<PageSection> insightsSections(ScreenData data, InsightsExtras extras) {
  final past = data.view.isPast;
  // Null on a past day. Every correlation, trend window and hourly trace on
  // this screen is computed nightly for the current day and sent on
  // `/api/today`, which takes no day — so the only honest thing an older date
  // can do with this payload is not draw it. See `shared/v02/past_day.dart`.
  final snapshot = past ? null : data.snapshot;
  final findings = snapshot?.findings ?? const <Finding>[];
  final trends = trendsOf(snapshot?.sparklines ?? const {});
  final sections = SectionList()
    ..add(
      V02PageHeader(
        title: 'Insights',
        date: past ? data.view.day : (data.snapshot?.date ?? data.day.date),
        status: data.view.status,
      ),
    );
  if (past) {
    sections
      ..add(const PastDayNotice(title: kInsightsPastTitle, body: kPastDayReason))
      ..gap(PageSpacing.panel);
    // `screens.insights`'s own words: *"explore the measurements available up
    // to this day"*. The correlations are refused above and stay refused; what
    // the reader gets instead is the dated series they were computed over.
    if (data.history case final AsyncValue<DatedHistory> history) {
      addDatedPanels(
        sections,
        history: history,
        metrics: kInsightsDatedMetrics,
        day: data.view.day,
        reveals: data.reveals,
        onRetry: data.onRetryHistory,
        onOpenMetric: extras.onOpenMetric,
      );
      if (unservedNotice(kInsightsUnserved) case final Widget notice) {
        sections.gap(PageSpacing.panel);
        sections.add(notice);
      }
      sections.gap(PageSpacing.block);
    }
  }
  if (!past) {
    if (data.serverFailure case final PageSection failure) {
      sections.addSection(failure);
      sections.gap(PageSpacing.panel);
    }
    if (data.serverPending case final PageSection pending) {
      sections.addSection(pending);
      sections.gap(PageSpacing.panel);
    }
  }
  // The contribution is read off the gated snapshot, not off `data`: it is the
  // age model's own output and dated today like everything else here.
  _entries(
    sections,
    AgeEntryCard.contribution(snapshot?.biologicalAge.valueOrNull),
    findings,
  );
  if (snapshot != null &&
      EffortStressPanel.hasSomethingToDraw(
        snapshot.hourlyHeartRate,
        snapshot.hourlyStress,
      )) {
    sections.add(
      EffortStressPanel(
        heartRate: snapshot.hourlyHeartRate,
        stress: snapshot.hourlyStress,
        reveals: data.reveals,
      ),
    );
    sections.add(ContextBridge.text(kJournalBridge));
  }
  // A heading over no panels reads as breakage. The honest state is silence:
  // a trend needs two days of the same metric and the server sends the window
  // once it has one.
  if (trends.isNotEmpty) {
    sections.gap(PageSpacing.block);
    sections.add(
      SectionHead(
        title: 'Your longer patterns',
        actionLabel: extras.onOpenHistory == null ? null : 'All metrics',
        onAction: extras.onOpenHistory,
      ),
    );
    sections.add(
      TrendsGrid(
        trends: trends,
        reveals: data.reveals,
        onOpenMetric: extras.onOpenMetric,
      ),
    );
  }
  _changedTogether(sections, findings, extras);
  sections.gap(PageSpacing.block);
  sections.add(const DataFooter());
  return sections.build();
}

/// `.relationship-grid` — one pattern of the owner's own, and the age model.
///
/// Either card may be absent, so the row is built from what there is: two cards
/// make the grid, one draws full width, none draws nothing. A grid with one live
/// half is a card beside a hole.
void _entries(SectionList sections, double? age, List<Finding> findings) {
  final Finding? pattern = findings
      .where(FindingEntryCard.canDraw)
      .firstOrNull;
  final cards = <Widget>[
    if (pattern != null) FindingEntryCard(finding: pattern),
    if (age != null) AgeEntryCard(years: age),
  ];
  if (cards.isEmpty) {
    return;
  }
  sections.add(
    cards.length == 2
        ? EntryGrid(left: cards.first, right: cards.last)
        : cards.first,
  );
  sections.gap(PageSpacing.panel);
}

/// Findings, notable days and links to outcomes, sleep history and fitness.
/// The framing stays observational: what moved together, not what caused what.
void _changedTogether(
  SectionList sections,
  List<Finding> findings,
  InsightsExtras extras,
) {
  sections.gap(PageSpacing.block);
  sections.add(const SectionHead(title: 'What changed together?'));
  if (findings.isNotEmpty) {
    sections.add(FindingsSection(findings: findings));
    sections.gap(PageSpacing.panel);
  }
  sections.add(const NotableEvents());
  sections.gap(PageSpacing.panel);
  sections.add(
    FlushCard(
      rows: <Widget>[
        V02ListRow(
          icon: SolarIconsOutline.flag,
          title: 'Challenge outcomes',
          detail: 'Progress, data coverage and what changed together',
          tone: Tone.movement,
          onOpen: extras.onOpenOutcomes,
        ),
        V02ListRow(
          icon: SolarIconsOutline.moonSleep,
          title: 'Sleep history',
          detail: 'Every night in the window, and the way into one of them',
          tone: Tone.sleep,
          onOpen: extras.onOpenSleepHistory,
        ),
        V02ListRow(
          icon: SolarIconsOutline.graphUp,
          title: 'Fitness estimates',
          detail: 'VO₂max, the instrument behind it, and what it is stored as',
          tone: Tone.fitness,
          onOpen: extras.onOpenFitness,
        ),
      ],
    ),
  );
}

/// The tracked metrics that have a window worth drawing, in [kTrendMetrics]'s
/// order.
///
/// Reads the ONE list in `metric_polarity.dart` rather than keeping a second one
/// here: a metric this screen drew but that table could not judge would be a
/// colourless panel nobody chose, and the mismatch would be invisible.
List<MetricTrend> trendsOf(Map<String, List<TrendPoint>> sparklines) {
  return <MetricTrend>[
    for (final metric in kTrendMetrics)
      if (MetricTrend.from(metric, sparklines[metric] ?? const [])
          case final MetricTrend trend)
        trend,
  ];
}
