/// `Your body overnight` — five measurements, each with its own fortnight.
///
/// `design/mobile-preview/panels.js::H.overnightVitals`:
///
/// ```js
/// `<div class="vitals-table">${[
///   ['heart','Resting heart', n.rhr,'bpm','heart',   rhr14,        [40,70], 'rhr'],
///   ['fitness','HRV',         n.hrv_sleep_avg,'ms','activity', hrv14, [25,65], 'hrv'],
///   ['oxygen','Blood oxygen', n.spo2_avg,'%','drop',  spo2_14,      [90,100],'spo2'],
///   ['oxygen','Breathing',    n.respiratory_rate,'/min','activity', br14, [10,20],'breathing'],
///   ['stress','Skin temperature', n.skin_temp_c,'°C','sun', temp14, [30,36],'temperature'],
/// ].map(…)}</div>`
/// ```
///
/// **The table itself is `shared/v02/vitals_table.dart`.** The same five rows are
/// drawn by `H.screens.recovery`, and the second caller is what moved the row
/// widget out of this file; this panel is now the Sleep screen's reading of
/// `/api/sleep` and the frame around it, which is what it always was on paper.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/vitals_table.dart';
import 'package:solar_icons/solar_icons.dart';

/// `Your body overnight` — the five overnight measurements.
class OvernightPanel extends StatelessWidget {
  /// [night] is the session; [recent] is the fortnight, newest first.
  const OvernightPanel({
    required this.night,
    required this.recent,
    required this.reveals,
    this.onOpenMetric,
    this.onOpenAll,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Your body overnight';

  /// The reveal-id namespace for this screen's rows.
  static const String revealPrefix = 'sleep.vital';

  /// The night being read.
  final SleepNight night;

  /// The fortnight, newest first — the order `/api/sleep` sends.
  final List<SleepNight> recent;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens one measurement's own history.
  final void Function(String metric)? onOpenMetric;

  /// `H.panel(…,'metrics')` — the DIRECTORY of every signal, which is where the
  /// prototype's `Details` on this card goes. It used to open the first row's
  /// own metric: a card of five measurements whose Details silently picked one
  /// of them, and the one it picked depended on row order.
  final VoidCallback? onOpenAll;

  /// The five rows, in the prototype's order.
  ///
  /// Each `metric` is the CANONICAL history id, not the sleep payload's own key
  /// (`rhr`, `spo2_avg`, …): the history screen knows canonical ids only and fell
  /// back to HRV for the rest, so four rows in five opened HRV (F2). Skin
  /// temperature keeps its payload key — there is no history series for it,
  /// and `VitalsTable` draws that row as no link at all.
  List<Vital> get vitals => <Vital>[
    Vital(
      label: 'Resting heart',
      tone: Tone.heart,
      icon: SolarIconsOutline.heart,
      unit: 'bpm',
      reading: night.restingHr,
      series: _series((night) => night.restingHr.valueOrNull),
      metric: HistoryMetric.restingHr.id,
    ),
    Vital(
      label: 'HRV',
      tone: Tone.fitness,
      icon: SolarIconsOutline.chart_2,
      unit: 'ms',
      reading: night.hrvSleepAvg,
      series: _series((night) => night.hrvSleepAvg.valueOrNull),
      metric: HistoryMetric.hrv.id,
    ),
    Vital(
      label: 'Blood oxygen',
      tone: Tone.oxygen,
      icon: SolarIconsOutline.waterdrop,
      unit: '%',
      reading: night.spo2Avg,
      series: _series((night) => night.spo2Avg.valueOrNull),
      metric: HistoryMetric.oxygen.id,
    ),
    Vital(
      label: 'Breathing',
      tone: Tone.oxygen,
      icon: SolarIconsOutline.wind,
      unit: '/min',
      reading: night.respiratoryRate,
      series: _series((night) => night.respiratoryRate.valueOrNull),
      metric: HistoryMetric.breathing.id,
    ),
    Vital(
      label: 'Skin temperature',
      tone: Tone.stress,
      icon: SolarIconsOutline.sun,
      unit: '°C',
      reading: night.skinTempC,
      series: _series((night) => night.skinTempC.valueOrNull),
      metric: 'skin_temp_c',
      digits: 1,
    ),
  ];

  /// Oldest first, with a night the strap did not measure kept as a gap.
  List<double?> _series(double? Function(SleepNight night) read) =>
      <double?>[for (final night in recent.reversed) read(night)];

  /// The server's own reason for each measurement it did not send.
  static List<String> refusals(List<Vital> rows) => VitalsTable.refusals(rows);

  @override
  Widget build(BuildContext context) {
    final rows = vitals;
    return Panel(
      tone: Tone.oxygen,
      label: 'Overnight vitals',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.heart,
        infoKey: 'sleep',
        actionLabel: onOpenAll == null ? null : 'Details',
        onAction: onOpenAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          VitalsTable(
            vitals: rows,
            reveals: reveals,
            revealPrefix: revealPrefix,
            onOpenMetric: onOpenMetric,
          ),
          if (VitalsTable.refusals(rows) case final List<String> lines
              when lines.isNotEmpty)
            PanelNote(lines.join('\n')),
        ],
      ),
    );
  }
}
