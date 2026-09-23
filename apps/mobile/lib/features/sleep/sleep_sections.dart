/// The ordered sections of Sleep. Composition only — no widget is defined here.
///
/// **This is the v02 prototype's screen, in the prototype's order.**
/// `design/mobile-preview/sleep-history-view.js::H.screens.sleep`, read top to
/// bottom at 390 px with the prototype open in a browser:
///
/// ```text
///   header                     date · Sleep · avatar
///   .sleep-reading             time asleep, and the strap's own score
///   .colour-key                bedtime · wake · time in bed
///   How your night unfolded    the stage timeline and its legend
///   Every stage, accounted for the proportion strip, then the four totals
///   Your body overnight        five overnight measurements, each with a spark
///   Your four sleep checks     four readings, four cutoffs, no total
///   Sleep need & debt          the shortfall, and what it is a shortfall against
///   Your week, stage by stage  seven nights, stacked
///   Sleep timing               bedtime and wake, and the regularity around them
///   Naps & your day            the day's own naps — only on a day with one
///   footer
/// ```
///
/// **The prototype's `Beyond a single night` chapter and everything under it
/// are gone** (F2, `DESIGN_DECISIONS.md`): the owner found the fortnight
/// trends, the tonight lever and the sleep findings redundant with the panels
/// above, Sleep history and Insights.
///
/// ## What is on this screen that the prototype has no box for
///
/// - **Sleep analysis** — `/api/sleep/insight`'s grounded reading, first.
/// - The **stale banner**, near the top: it says *everything below is from an
///   older night*, and a sentence like that is worth nothing under the thing it
///   qualifies. That is the honesty layer, which is the one place this rebuild
///   has latitude.
///
/// ## What survived the redesign
///
/// The **data wiring**, whole. Three reads that fail independently, every figure
/// still a `Reading`, every refusal still rendered as a refusal with the
/// server's own reason, and the four sleep dimensions still four.
///
/// The eleven pre-v02 cards did not survive. Their measurements did: every one
/// of them is on a panel above, and the references and citations they drew on
/// their faces now open from the ⓘ, which is where the owner asked them to live.
library;

import 'package:flutter/material.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/features/sleep/v02/checks_panel.dart';
import 'package:healthee/features/sleep/v02/naps_panel.dart';
import 'package:healthee/features/sleep/v02/need_panel.dart';
import 'package:healthee/features/sleep/v02/night_panels.dart';
import 'package:healthee/features/sleep/v02/sleep_reading.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/features/sleep/v02/vitals_panel.dart';
import 'package:healthee/features/sleep/v02/week_panel.dart';
import 'package:healthee/features/sleep/v02/withheld_night.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/page_header.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/view_day.dart';

/// The one panel a past night cannot carry, and the prototype's own heading.
const String kSleepDebtPastTitle = 'Sleep need & debt';

/// `sleep-history-view.js`'s own sentence for it, kept word for word.
const String kSleepDebtPast =
    'Historical sleep-need and debt analyses are not included. The latest debt '
    'is not carried backward.';

/// When the chosen day is older than every night the window holds.
const String kNoNightTitle = 'No night on or before this day';

/// Why that is an answer rather than an empty screen.
const String kNoNightBody =
    'Your nights are sent as a window, and this one begins after the day you '
    'chose. A later night is not shown in its place — that would be a different '
    'night under a date you did not pick.';

/// Everything Sleep needs that is not on the payloads.
@immutable
class SleepExtras {
  /// The four places this screen can go. Any of them null draws the control
  /// without its action rather than a control that leads nowhere.
  const SleepExtras({
    this.onOpenProfile,
    this.onOpenMetric,
    this.onOpenHistory,
    this.onOpenAllMetrics,
  });

  /// Opens settings. The avatar's destination.
  final VoidCallback? onOpenProfile;

  /// Opens one measurement's own history.
  final void Function(String metric)? onOpenMetric;

  /// Opens the sleep history.
  ///
  /// `H.panel('How your night unfolded', …, 'sleep-history', …)` and
  /// `H.panel('Your week, stage by stage', …, 'sleep-history', …)` — both of
  /// this screen's `Details` links go to the same place, which is the screen
  /// that holds every night rather than one metric's dated series.
  final VoidCallback? onOpenHistory;

  /// Opens the metric DIRECTORY — `H.panel('Your body overnight',…,'metrics')`.
  final VoidCallback? onOpenAllMetrics;
}

/// Builds the ordered section list for one render of Sleep.
List<PageSection> sleepSections({
  required SleepPage page,
  required SleepConsistency? consistency,
  required DateTime now,
  required RevealRegistry reveals,
  required ViewDay view,
  SleepExtras extras = const SleepExtras(),
}) {
  final past = view.isPast;
  // **The window ENDS on the day being read.** `/api/sleep` sends a dated
  // window rather than one night, so a past night is a real measurement this
  // phone already holds — which is why Sleep is the one screen where a past day
  // draws its charts instead of refusing them.
  final windows = SleepWindows.through(page, now, view.day);
  if (windows == null) {
    return _noNight(view, extras);
  }
  final night = windows.latest;
  final sections = SectionList()
    ..add(
      V02PageHeader(
        title: 'Sleep',
        date: night.date,
        status: view.status,
      ),
    );
  // **The analysis opens the screen.** It was the last panel on a page that
  // scrolls for four screens, so the one thing on Sleep written FOR the owner
  // — a grounded reading of these nights, citation-validated — was the thing
  // they were least likely to reach. It is collapsible precisely because it is
  // first: several paragraphs in the opening slot would push last night's
  // measurements below the fold for a reader who only wanted the numbers.
  //
  // Not on a past day: `sleepInsightProvider` reads the newest nights, and an
  // analysis of this week under a date the owner navigated away to would be the
  // stale-as-current lie at the top of the screen.
  if (!past) {
    sections
      ..add(const SleepAnalysisPanel())
      ..gap(PageSpacing.panel);
  }
  // "No sleep last night" is a statement about the wall clock, so it belongs to
  // the newest night only. Under an older date it would be measuring a night
  // the reader chose against an instant they did not.
  if (!past && windows.stale) {
    sections
      ..add(StaleNightNotice(label: windows.label))
      ..gap(PageSpacing.panel);
  }
  sections
    ..add(SleepReading(night: night))
    ..gap(PageSpacing.panel)
    ..add(
      NightTimelinePanel(
        night: night,
        reveals: reveals,
        onDetails: extras.onOpenHistory,
      ),
    )
    ..gap(PageSpacing.panel)
    ..add(StageTablePanel(night: night, reveals: reveals))
    ..gap(PageSpacing.panel)
    ..add(
      OvernightPanel(
        night: night,
        recent: windows.recent,
        reveals: reveals,
        onOpenMetric: extras.onOpenMetric,
        onOpenAll: extras.onOpenAllMetrics,
      ),
    )
    ..gap(PageSpacing.panel)
    ..add(
      SleepChecksPanel(
        night: night,
        cutoffs: page.cutoffs,
        notes: page.researchNotes,
      ),
    )
    ..gap(PageSpacing.panel)
    // `sleep-history-view.js` refuses exactly this panel on a past day:
    // *"Historical sleep-need and debt analyses are not included. The latest
    // debt is not carried backward."* Debt is a fourteen-night model computed
    // to now, so it is the one block on this screen that an older date cannot
    // honestly carry.
    ..add(
      past
          ? const PastDayNotice(title: kSleepDebtPastTitle, body: kSleepDebtPast)
          : SleepNeedPanel(
              night: night,
              nights: windows.debt,
              needMin: page.sleepDebt?.needMin,
              reveals: reveals,
            ),
    );
  if (windows.week.length >= SleepWindows.minimumNights) {
    sections
      ..gap(PageSpacing.panel)
      ..add(
        StageWeekPanel(
          nights: windows.week,
          span: windows.weekSpan,
          reveals: reveals,
          onDetails: extras.onOpenHistory,
        ),
      );
  }
  sections
    ..gap(PageSpacing.panel)
    ..add(
      SleepTimingPanel(
        bedtime: windows.bedtime,
        wake: windows.wake,
        dates: windows.timingDates,
        // The bedtimes and wakes are dated and re-window above; the regularity
        // FIGURE is `/api/sleep/consistency`'s single current answer, and it
        // takes no day. The chart follows the reader, the score does not
        // pretend to.
        consistency: past ? null : consistency,
        reveals: reveals,
      ),
    );
  // ⛔ **Nothing from `Beyond a single night` down** (F2, the owner): the three
  // fortnight trends, the tonight lever and the sleep findings were redundant
  // with the panels above, Sleep history and Insights.
  //
  // Only the day's NAPS stay, and only on a day that has one: the strap
  // records a nap perhaps once a month, and a card saying "no nap" on the other
  // days was noise. They are dated like the night, so a past day draws its own.
  final naps = <SleepNap>[
    for (final nap in page.naps)
      if (nap.date == night.date) nap,
  ];
  if (naps.isNotEmpty) {
    sections
      ..gap(PageSpacing.panel)
      ..add(NapsPanel(naps: naps));
  }
  sections
    ..gap(PageSpacing.block)
    ..add(const DataFooter());
  return sections.build();
}

/// The chosen day is older than every night the window holds.
///
/// A header and one sentence, not an empty frame: a screen that simply ends is
/// read as a night of no sleep, and this is a fact about the WINDOW.
List<PageSection> _noNight(ViewDay view, SleepExtras extras) => <PageSection>[
  PageSection(
    V02PageHeader(
      title: 'Sleep',
      date: view.day,
      status: view.status,
    ),
    gap: 0,
  ),
  const PageSection(
    PastDayNotice(title: kNoNightTitle, body: kNoNightBody),
    gap: PageSpacing.block,
  ),
  const PageSection(DataFooter()),
];
