/// The panels the recovery screen adds under `Recovery, explained`.
///
/// `design/mobile-preview/screens-daily.js::H.screens.recovery`:
///
/// ```js
/// H.panel('Compared with your baseline','recovery', signals + note, 'metrics')
/// H.bridge('sleep','Sleep contributes 40% of the model. …','sleep','Explore your sleep')
/// H.panel('Capacity changes through the day','movement',
///         two stats + load bars + note, 'activity','walk')
/// ```
///
/// ## The ladder carries the three honesty fields it used to drop
///
/// `recovery.signals[].n`, `.direction_basis` and `.population_floor_min` were on the
/// wire, each added deliberately with its reason written beside it, and none of them was
/// parsed. [directionBasisNote] and [baselineDepthNote] are where they reach the owner.
/// They are NOTES rather than chart furniture on purpose: `signal_chart.dart` argues
/// that a marker's position is where the number is and not where the reasoning is, and
/// the same argument keeps a count and a limb out of a 56-pixel reading column.
///
/// ## The baseline ladder is the payload's, and a share is never assumed
///
/// The prototype hard-codes three rows at dead centre and writes *"Sleep
/// contributes 40%"* into the bridge. Both come off `recovery` here: the rows
/// are `recovery.signals[]` with their own standard scores, and the bridge names
/// a share only when the sleep factor carried a weight. A model that reweights
/// itself has to be able to say so, and a sentence that states a share the
/// payload did not send is the one number on this screen that would be ours.
///
/// ## The two capacity figures are not one number twice
///
/// `recovery` is the overnight estimate and `readiness` is what is left of it
/// after today's effort. They are drawn side by side because the panel exists to
/// say they differ; when the server sends no readiness the panel draws the
/// overnight figure alone rather than repeating it under a second label.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/models/recovery_signals.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/signal_chart.dart';
import 'package:solar_icons/solar_icons.dart';

/// What a baseline IS. True on every payload, including one with no summary.
const String kBaselineNote =
    'A baseline is personal, not a population target.';

/// How many days of the owner's own history each baseline rests on.
///
/// `recovery.signals[].n` was on the wire and parsed by nobody. It exists because the
/// RHR and HRV signals once had **no count gate at all** — with two mornings the MAD is
/// the half-distance, so a finite z shipped with a direction attached, a verdict on this
/// owner's autonomic state from two days. `read/recovery_signals.py` added
/// `_SIGNAL_MIN_DAYS = 5` and shipped the count *"so a reader can weigh a direction
/// rather than take it"*. This is the reader being able to.
///
/// Per signal rather than as a range, because which marker is thin is the whole content:
/// "7 to 30 days" tells nobody which verdict to discount. Null when no signal carried a
/// count — an older server, and then the line is absent rather than invented.
String? baselineDepthNote(RecoverySignals signals) {
  final counted = <String>[
    for (final signal in signals.signals)
      if (signal.n case final int n) '${signal.name} $n',
  ];
  if (counted.isEmpty) {
    return null;
  }
  return 'Days of your own history behind each baseline: ${counted.join(', ')}.';
}

/// WHICH limb produced an unfavourable verdict, said in a sentence.
///
/// `recovery.signals[].direction_basis` and `.population_floor_min` were both on the
/// wire and both dropped, and this is the one that matters most **to this owner**. The
/// sleep signal calls itself "vs personal usual" and then decides its direction from an
/// absolute floor as well as from the personal z, so `read/recovery_signals.py` says
/// plainly: *"for a chronic short sleeper the population floor decides every night and
/// the personal number beside it cannot change the verdict."*
///
/// Without this the ladder draws a personal z beside a verdict that z did not produce.
/// The chart is not the place to say so — a marker's position is where the number is,
/// not where the reasoning is — so it is a note under it, in words.
///
/// Null when no signal carried a basis, which is every payload where nothing is
/// unfavourable: only that branch has two independent limbs to disambiguate.
String? directionBasisNote(RecoverySignals signals) {
  final lines = <String>[
    for (final signal in signals.signals)
      if (_basisLine(signal) case final String line) line,
  ];
  return lines.isEmpty ? null : lines.join(' ');
}

String? _basisLine(RecoverySignal signal) {
  final floor = _floor(signal);
  return switch (signal.directionBasis) {
    'population' =>
      '${signal.name} is called unfavourable by $floor, not by your own '
          'baseline beside it.',
    'personal' =>
      '${signal.name} is called unfavourable by your own baseline, not by $floor.',
    'both' =>
      '${signal.name} is called unfavourable by your own baseline and by '
          '$floor alike.',
    _ => null,
  };
}

/// `the population floor of 5h 00m`, or the unqualified phrase when none was sent.
String _floor(RecoverySignal signal) {
  final floor = signal.populationFloorMin;
  return floor == null
      ? 'the population floor'
      : 'the population floor of ${_figure(floor, signal.unit)}';
}

/// A signal's number in its unit: `45 ms`, `48.8 bpm`, and minutes as
/// `6h 56m` — the way every other screen writes a duration (the baseline row
/// read `416 min` beside Sleep's `6h 56m` for the same night).
String _figure(double value, String? unit) {
  if (unit == 'min') {
    return hoursMinutes(value);
  }
  final figure = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return unit == null ? figure : '$figure $unit';
}

/// The prototype's own line under the capacity chart.
const String kCapacityNote =
    'Today’s recorded effort changes remaining readiness. The overnight number '
    'does not update to erase that context.';

/// `H.bridge('sleep', …)` — sleep's share of the model, and what a night holds.
const String kNightBridge =
    'The full night includes its stages, its efficiency and its overnight '
    'physiology.';

/// The same bridge with the share the payload actually sent in front of it.
String sleepShareBridge(double? weight) => weight == null
    ? kNightBridge
    : 'Sleep contributes ${_share(weight)} of the model. $kNightBridge';

String _share(double weight) =>
    '${(weight <= 1 ? weight * 100 : weight).round()}%';

/// The sleep factor's weight, or null when the model did not send one.
double? sleepWeight(RecoveryScore score) {
  for (final factor in score.factors) {
    if (factor.name.toLowerCase().contains('sleep')) {
      return factor.weight;
    }
  }
  return null;
}

/// `Compared with your baseline` — each signal against its own normal.
class BaselinePanel extends StatelessWidget {
  /// [signals] is `recovery.signals[]`, in the payload's own order.
  const BaselinePanel({required this.signals, this.onDetails, super.key});

  /// The prototype's title.
  static const String title = 'Compared with your baseline';

  /// The ladder and its summary.
  final RecoverySignals signals;

  /// Opens the metric explorer.
  final VoidCallback? onDetails;

  /// One row per signal, with its position when it has one.
  List<SignalRow> get rows => <SignalRow>[
    for (final signal in signals.signals)
      SignalRow(signal.name, reading(signal), z: signal.z),
  ];

  /// `45 ms`, `6h 56m`, or an em dash when today's reading did not arrive.
  static String reading(RecoverySignal signal) {
    final value = signal.value;
    return value == null ? '—' : _figure(value, signal.unit);
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.recovery,
      label: 'Recovery signals',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.heartPulse,
        infoKey: 'recovery_score',
        detail: MetricDetail(
          notes: <String>[
            for (final signal in signals.signals)
              if (signal.researchNoteId case final String id) id,
          ],
        ),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SignalChart(rows),
          if (signals.summary case final String summary) PanelNote(summary),
          // Which limb produced the verdict, before what a baseline is: the first
          // qualifies a judgement already on screen, the second is background.
          if (directionBasisNote(signals) case final String basis) PanelNote(basis),
          const PanelNote(kBaselineNote),
          if (baselineDepthNote(signals) case final String depth) PanelNote(depth),
        ],
      ),
    );
  }
}

/// `Capacity changes through the day` — the overnight estimate, what is left of
/// it, and the effort that spent the difference.
class CapacityPanel extends StatelessWidget {
  /// [load] of null draws the two figures and no chart.
  const CapacityPanel({
    required this.score,
    required this.reveals,
    this.load,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Capacity changes through the day';

  /// The gap above the chart.
  static const double chartGap = 12;

  /// The model's output, and what remains of it.
  final RecoveryScore score;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The fortnight of effort behind the change.
  final CardioLoad? load;

  /// Opens the activity tab.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final trend = load?.trend30d ?? const <TrendPoint>[];
    return Panel(
      tone: Tone.movement,
      label: 'Recovery · remaining readiness',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.walking,
        infoKey: 'recovery_score',
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatRow(<Stat>[
            Stat('Overnight recovery', '${score.recovery}', unit: '/100'),
            if (score.readiness case final int readiness)
              Stat('Remaining readiness', '$readiness', unit: '/100'),
          ]),
          if (trend.length > 1) ...<Widget>[
            const SizedBox(height: chartGap),
            RevealOnce(
              id: 'recovery.capacity-load',
              registry: reveals,
              builder: (context, t) => V02BarChart(
                <double?>[for (final point in trend) point.value],
                progress: t,
                labels: <String>[
                  for (final point in trend) _dayOfMonth(point.date),
                ],
                semanticLabel: 'Training load over the recent days',
              ),
            ),
          ],
          const PanelNote(kCapacityNote),
        ],
      ),
    );
  }

  /// `2026-07-31` → `31`. A bar label, not a date.
  static String _dayOfMonth(String date) =>
      date.length >= 10 ? date.substring(8, 10) : date;
}
