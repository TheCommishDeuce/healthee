/// `Your four sleep checks` — four independent readings, and no total.
///
/// `design/mobile-preview/screens-sleep.js::checks`, one `<li class="sleep-check">`
/// per row and the closing note:
///
/// ```js
/// ['Duration',       H.duration(minutes),        '7–9 hours',        …],
/// ['Efficiency',     efficiency + '%',           'At least 85%',     …],
/// ['Regularity · SRI', sri + ' /100',            '70 or above',      …],
/// ['Timing',         midpoint,                   'Midpoint 02:00–04:00', …],
/// H.note('Four independent checks, not a combined score. '
///        'The 7–9h check differs from the 8h sleep-need reference.')
/// ```
///
/// ## THE FOUR ARE NEVER ADDED UP
///
/// `/api/sleep` also sends `score` — how many of the four passed. It is **not
/// drawn here and must not be**: no validated instrument combines duration,
/// efficiency, regularity and timing into one number, and a reader shown `3`
/// beside four rows will take it for a mark out of four. That is the rule
/// `feedback_no_composite_score` states and the prototype's own title states it
/// too — *four* checks, not a score. `sleep_checks_test.dart` fails the build if
/// a total appears on this panel.
///
/// ## Where the mark comes from, and where the sentence comes from
///
/// The **mark** is the server's own `point_duration` / `point_efficiency` /
/// `point_timing` / `point_regularity`. That judgement is server science and is
/// not re-derived on the phone.
///
/// The **sentence under it** is arithmetic on the two numbers already on the
/// row — the reading and the published cutoff beside it — so it says how far
/// outside, in the reader's own units. If the server's mark and that distance
/// ever disagreed, this panel would show both rather than quietly picking one.
///
/// ## The cutoffs are the server's, with the prototype's wording as the fallback
///
/// `page.cutoffs` carries `duration_hours`, `efficiency_min`, `timing_hour_band`
/// and `sri_min`. A cutoff with no source is a number this app made up, so the
/// four **reference labels and the citations live in the ⓘ sheet**, off the
/// card's face, which is where the owner asked references to go.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/v02/sleep_cutoffs.dart';
import 'package:healthee/shared/format/iso_clock.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's closing note, verbatim. Says the one thing that matters.
const String kFourChecksNote =
    'Four independent checks, not a combined score. The 7–9h check differs '
    'from the 8h sleep-need reference.';

/// One row: what it is, what was read, what against, and how far outside.
@immutable
class SleepCheck {
  /// A single dimension of the night.
  const SleepCheck({
    required this.name,
    required this.reading,
    required this.target,
    required this.passed,
    required this.detail,
  });

  /// `Duration` · `Efficiency` · `Regularity · SRI` · `Timing`.
  final String name;

  /// The measurement, already formatted, or null when there was none.
  final String? reading;

  /// The published range it was read against.
  final String target;

  /// The server's own verdict, which may be withheld.
  final Reading<bool> passed;

  /// How far outside, in words.
  final String detail;
}

/// `Your four sleep checks`.
class SleepChecksPanel extends StatelessWidget {
  /// [night] is the session; [cutoffs] and [notes] are the payload's.
  const SleepChecksPanel({
    required this.night,
    required this.cutoffs,
    required this.notes,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Your four sleep checks';

  /// The night being read.
  final SleepNight night;

  /// The published cutoffs, when the server sent them.
  final SleepCutoffs? cutoffs;

  /// The research notes behind them.
  final List<String> notes;

  /// The four rows, in the prototype's order.
  List<SleepCheck> get checks {
    final bands = SleepBands(cutoffs);
    return <SleepCheck>[
      SleepCheck(
        name: 'Duration',
        reading: night.tstMin.valueOrNull == null
            ? null
            : hoursMinutes(night.tstMin.valueOrNull!),
        target: bands.durationLabel,
        passed: night.pointDuration,
        detail: bands.durationDetail(night.tstMin.valueOrNull),
      ),
      SleepCheck(
        name: 'Efficiency',
        reading: night.efficiencyPct.valueOrNull == null
            ? null
            : '${night.efficiencyPct.valueOrNull!.toStringAsFixed(1)}%',
        target: bands.efficiencyLabel,
        passed: night.pointEfficiency,
        detail: bands.efficiencyDetail(night.efficiencyPct.valueOrNull),
      ),
      SleepCheck(
        name: 'Regularity · SRI',
        reading: night.sri.valueOrNull == null
            ? null
            : '${night.sri.valueOrNull!.round()} /100',
        target: bands.sriLabel,
        passed: night.pointRegularity,
        detail: bands.sriDetail(night.sri.valueOrNull),
      ),
      SleepCheck(
        name: 'Timing',
        reading: clockOfIso(night.midpointLocal.valueOrNull),
        target: bands.timingLabel,
        passed: night.pointTiming,
        detail: bands.timingDetail(night.midpointLocal.valueOrNull),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = checks;
    return Panel(
      tone: Tone.sleep,
      label: 'Sleep checks',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep_health',
        detail: MetricDetail(
          references: <String>[
            for (final check in rows) '${check.name} — ${check.target}',
          ],
          notes: notes,
          method: const <String>[kFourChecksNote],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++)
            _CheckRow(check: rows[i], first: i == 0, last: i == rows.length - 1),
          const PanelNote(kFourChecksNote),
        ],
      ),
    );
  }
}

/// `.sleep-check` — the mark, the name, the reading, the range, the distance.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.check,
    required this.first,
    required this.last,
  });

  final SleepCheck check;
  final bool first;
  final bool last;

  /// `.sleep-check { padding:16px 0 }` with 4 at the two ends.
  static const double pad = 16;
  static const double endPad = 4;

  /// `.check-result { width:26px; height:26px; border-radius:9px }`.
  static const double mark = 26;
  static const double markRadius = 9;

  /// `.sleep-check { gap:12px }`.
  static const double gap = 12;

  /// `.check-target { margin-top:4px }` · `.check-detail { margin-top:8px }`.
  static const double targetGap = 4;
  static const double detailGap = 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = check.passed.valueOrNull;
    final row = Padding(
      padding: EdgeInsets.only(
        top: first ? endPad : pad,
        bottom: last ? endPad : pad,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Mark(passed: result),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        check.name,
                        style: SleepType.checkName.copyWith(color: colors.ink),
                      ),
                    ),
                    const SizedBox(width: gap),
                    Text(
                      check.reading ?? '—',
                      style: SleepType.checkValue.copyWith(
                        color: check.reading == null
                            ? colors.ink3
                            : colors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: targetGap),
                Text(
                  check.target,
                  style: SleepType.checkTarget.copyWith(color: colors.ink2),
                ),
                const SizedBox(height: detailGap),
                Text(
                  check.detail,
                  style: SleepType.checkDetail.copyWith(
                    // `.sleep-check.short .check-detail { color:var(--caution) }`
                    color: result == false ? colors.unf : colors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return last
        ? row
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.line, width: hairline),
              ),
            ),
            child: row,
          );
  }
}

/// The tick, the dash that is a shortfall, and the dash that is a silence.
class _Mark extends StatelessWidget {
  const _Mark({required this.passed});

  final bool? passed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color ground, Color ink) = switch (passed) {
      true => (colors.favSoft, colors.fav),
      false => (colors.unfSoft, colors.unf),
      // No reading, so no verdict. It reads as neither a pass nor a failure —
      // which is the whole claim.
      null => (colors.surface2, colors.ink3),
    };
    return Container(
      width: _CheckRow.mark,
      height: _CheckRow.mark,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(_CheckRow.markRadius),
      ),
      child: passed == true
          ? Icon(Icons.check, size: 15, color: ink)
          : Center(
              child: Text(
                '−',
                style: SleepType.checkMark.copyWith(color: ink),
              ),
            ),
    );
  }
}
