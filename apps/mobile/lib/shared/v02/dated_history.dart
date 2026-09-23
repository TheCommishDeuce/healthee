/// The dated panels a past day draws, and the three states behind them.
///
/// `history-screens.js` builds every past-day screen out of one call:
///
/// ```js
/// const panels = keys => keys.map(key => H.historyPanel(key)).join('');
/// screens.insights = () => `… ${panels(['hrv','rhr','efficiency','regularity','vo2','steps'])} …`;
/// ```
///
/// Six screens do it, so it is one function six times (Standards section 1).
/// Each names its own metrics at its own call site, in the prototype's order —
/// the list is the design, and hiding six lists inside this file would put the
/// screens' content somewhere nobody reading a screen would look.
///
/// ## Measurements, never judgements
///
/// Everything drawable here is a **dated measurement**: a row `derive` wrote
/// under a calendar day, which is as true of 24 July as it is of today. That is
/// the whole reason a past day may gain these charts while it still refuses
/// recovery, biological age, VO₂max's estimate, the written analysis and the
/// day's findings — those are worked out for the current day and no other, and
/// `past_day.dart` is where each screen says so.
///
/// `vo2max_estimate` is on this list and is not a counter-example. The dated
/// series is the row the derive layer stored on each day; the **estimate**, with
/// its instrument, its freshness gate and its caveats, is `/api/today`'s and
/// still refuses. The panel draws the stored history and names nothing about
/// today.
///
/// ## Three states, because an async consumer owes all three
///
/// Loading, failed-with-a-retry and drawn. A screen that rendered nothing while
/// the batch was in flight would read as a day with no measurements, which is
/// the one thing this feature exists to stop saying.
///
/// ## What the prototype draws here and this server cannot answer for
///
/// Sleep duration, sleep efficiency and skin temperature are panels in
/// `history-screens.js` and have **no daily series on this server** —
/// `BACKEND_GAPS_FROM_UI.md` C3 checked both sides and lists all three. The
/// nightly values exist, on the sleep session; what does not exist is a
/// `derived_daily` metric a dated chart could be drawn from, so a tile for one
/// would be a door onto a 422. [unservedNotice] says which ones, by name, on the
/// screens the prototype puts them on. Silently drawing five panels where the
/// design has eight would leave the gap invisible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/api/not_signed_in.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/history/history_window.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/screen_data.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_panel.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/surface_cards.dart';

/// What the loading card says while the batched read is in flight.
const String kDatedHistoryLoading = 'Reading your dated measurements';

/// What the failure card says. A connection problem, said as one.
const String kDatedHistoryError =
    "Couldn't reach your server for this day's measurements";

/// The second line of it — the distinction the whole screen turns on.
const String kDatedHistoryErrorDetail =
    'This is a connection problem, not a gap in your measurements.';

/// The prototype panels this server keeps no dated daily series for.
///
/// Named rather than numbered so the sentence stays true if one of them gains a
/// series: the note is built from this list, so serving `skin_temp_c` and
/// listing it in `HistoryMetric` is all it would take to drop it from the
/// apology and add it to the panels.
const String kUnservedSleepDuration = 'sleep duration';

/// See [kUnservedSleepDuration].
const String kUnservedSleepEfficiency = 'sleep efficiency';

/// See [kUnservedSleepDuration].
const String kUnservedSkinTemperature = 'skin temperature';

/// The heading over the missing-series note.
const String kUnservedTitle = 'Not kept as a dated series';

/// One sentence naming the prototype panels this build cannot draw dated.
///
/// [names] is the screen's own subset, in the order the design puts them.
///
/// It ends by pointing at Sleep rather than by pointing up or down the page.
/// All three of these ARE on that screen per night (`v02/vitals_panel.dart`,
/// `v02/checks_panel.dart`), so the sentence sends the reader somewhere real —
/// and a direction would have been wrong anyway: this notice sits after the
/// panels on every screen that draws it, and a card that says "below" while
/// everything it means is above is a small lie that nothing would catch.
String unservedBody(List<String> names) {
  final list = switch (names.length) {
    0 => '',
    1 => names.single,
    2 => '${names.first} and ${names.last}',
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
  final one = names.length == 1;
  return 'Your $list ${one ? 'is' : 'are'} measured on the night itself, but '
      'your server keeps no day-by-day series for ${one ? 'it' : 'them'}, so '
      'there is nothing dated to chart. Sleep holds this night’s own '
      '${one ? 'reading' : 'readings'}.';
}

/// The note itself, or nothing at all when a screen has no unserved panels.
Widget? unservedNotice(List<String> names) => names.isEmpty
    ? null
    : PastDayNotice(title: kUnservedTitle, body: unservedBody(names));

/// The dated panels for [metrics], or the one card that stands in for them.
///
/// Returned rather than added to a list, because the two hosts differ: a tab
/// screen wants one [PageSection] per panel so the sliver list can build them
/// lazily, and a detail screen wants widgets in a `ListView`. [addDatedPanels]
/// is the first; a detail screen spreads this with its own spacers.
List<Widget> datedPanels({
  required AsyncValue<DatedHistory> history,
  required List<HistoryMetric> metrics,
  required String day,
  required RevealRegistry reveals,
  required VoidCallback onRetry,
  void Function(String metric)? onOpenMetric,
  Map<HistoryMetric, String> notes = const <HistoryMetric, String>{},
}) {
  return history.when(
    skipLoadingOnRefresh: true,
    loading: () => const <Widget>[LoadingState(label: kDatedHistoryLoading)],
    error: (error, stackTrace) => <Widget>[
      if (isNotSignedIn(error))
        signInNeededCard()
      else
        ErrorState(
          message: kDatedHistoryError,
          detail: kDatedHistoryErrorDetail,
          onRetry: onRetry,
        ),
    ],
    data: (series) => <Widget>[
      for (final metric in metrics) ...<Widget>[
        DatedPanel(
          metric: metric.id,
          unit: metric.unit,
          day: day,
          // The fortnight ENDING ON THE CHOSEN DAY. Windowing on today would
          // draw the newest readings there are under an older date, which is
          // the stale-as-current failure with a chart instead of a figure.
          window: HistoryWindow.endingOn(
            series[metric.id],
            day,
            kDatedPanelDays,
          ),
          reveals: reveals,
          onDetails: onOpenMetric == null
              ? null
              : () => onOpenMetric(metric.id),
        ),
        // `H.note(...)` between two panels — a sentence about the SERIES rather
        // than about a reading, which is why it is not inside the card.
        if (notes[metric] case final String note) SmallProse(note),
      ],
    ],
  );
}

/// A detail screen's whole past-day body: the refusal, the panels, the footer.
///
/// Recovery, Biological age and Fitness are the same page three times — a
/// `PastDayNotice` for the judgement that cannot be dated, then the
/// measurements that can. [unserved] names the prototype panels this server
/// keeps no dated series for, and draws nothing when there are none.
List<Widget> pastDayDetail({
  required String refusalTitle,
  required AsyncValue<DatedHistory> history,
  required List<HistoryMetric> metrics,
  required String day,
  required RevealRegistry reveals,
  required VoidCallback onRetry,
  List<String> unserved = const <String>[],
  void Function(String metric)? onOpenMetric,
  Map<HistoryMetric, String> notes = const <HistoryMetric, String>{},
}) {
  final panels = datedPanels(
    history: history,
    metrics: metrics,
    day: day,
    reveals: reveals,
    onRetry: onRetry,
    onOpenMetric: onOpenMetric,
    notes: notes,
  );
  return <Widget>[
    PastDayNotice(title: refusalTitle, body: kPastDayReason),
    for (final panel in panels) ...<Widget>[
      const SizedBox(height: PageSpacing.panel),
      panel,
    ],
    if (unservedNotice(unserved) case final Widget notice) notice,
    const SizedBox(height: PageSpacing.block),
    const DataFooter(),
  ];
}

/// [datedPanels], appended to a tab screen's section list with v02's own gap.
void addDatedPanels(
  SectionList sections, {
  required AsyncValue<DatedHistory> history,
  required List<HistoryMetric> metrics,
  required String day,
  required RevealRegistry reveals,
  required VoidCallback onRetry,
  void Function(String metric)? onOpenMetric,
}) {
  final panels = datedPanels(
    history: history,
    metrics: metrics,
    day: day,
    reveals: reveals,
    onRetry: onRetry,
    onOpenMetric: onOpenMetric,
  );
  for (var i = 0; i < panels.length; i++) {
    sections.add(panels[i]);
    if (i < panels.length - 1) {
      sections.gap(PageSpacing.panel);
    }
  }
}
