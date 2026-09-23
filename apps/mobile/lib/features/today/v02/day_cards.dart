/// The day on Today: steps, heart rate and stress, each its own card (F1).
///
/// Owner: Today should carry "day's steps, heart rate, stress", as **separate**
/// detailed overviews, beside last night's sleep, recovery and the weigh-in.
/// This partly reverses U11/U20, which cut Today to those three
/// (`DESIGN_DECISIONS.md`).
///
/// ## Today is the day, Activity is the week
///
/// Activity already draws the week behind the step count and a linked heart
/// rate & stress chart. These cards are the DAY, hour by hour, so the two
/// screens answer different questions rather than repeating each other.
///
/// ## Nothing here is a new metric
///
/// Every figure is a reading someone else produced: the strap's own counters
/// and latest samples (`DeviceDay`), the server's hourly aggregates and its
/// canonical resting heart rate (`/api/today`). The only arithmetic is placing
/// hours on a clock, summing the server's 15-minute step buckets into hours,
/// and picking the extreme of samples the server already bounded.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/device/device_metric.dart';
import 'package:healthee/data/honesty/device_absence.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// Under the steps chart.
const String kStepsByHourNote =
    'Bars add up the strap’s per-minute steps by hour; the total above is its '
    'own since-midnight counter, and the two can differ.';

/// Under the heart-rate chart.
const String kHeartRateDayNote =
    'Hourly averages of the strap’s samples. Lowest and highest are single '
    'samples; resting is the lowest 5-minute average inside your sleep, so a '
    'single sample can dip below it.';

/// Under the stress chart. Matches the `stress` explainer behind the ⓘ.
const String kStressDayNote =
    'The strap’s own 0–100 index, hourly. It tracks how switched-on your body '
    'was, not how you felt.';

/// When the server sent no hours for the day.
const String kNoHoursNote = 'No hourly readings for this day yet.';

/// `Last reading · 12:41`, or the reason there is none.
String? _lastReading(Reading<double> reading, DateTime? at) {
  if (reading case Withheld<double>(:final disclosure)) {
    return disclosure.message;
  }
  return at == null ? null : 'Last reading · ${clockLabel(at)}';
}

/// [points] placed on the day's clock: slot `h` is hour `h`, from midnight to
/// the last hour sent, and an hour with no samples is a gap, never a zero.
List<double?> _byHour(
  List<HourPoint> points,
  double? Function(HourPoint) pick,
) {
  if (points.isEmpty) return const <double?>[];
  final last = points.map((point) => point.hour).reduce(math.max);
  final byHour = <int, double?>{
    for (final point in points) point.hour: pick(point),
  };
  return <double?>[for (var hour = 0; hour <= last; hour++) byHour[hour]];
}

List<String> _hourLabels(int count) => <String>[
  for (var hour = 0; hour < count; hour++) shortClock(hour),
];

List<String> _edges(int count) => count < 2
    ? const <String>[]
    : <String>[shortClock(0), shortClock(count - 1)];

/// The day's steps: the strap's total, and the day by hour.
class StepsDayCard extends StatelessWidget {
  /// [buckets] are the server's 15-minute step buckets for the day.
  const StepsDayCard({
    required this.day,
    required this.buckets,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The card's title.
  static const String title = 'Steps';

  /// The strap's own counters for the day.
  final DeviceDay day;

  /// `/api/today`'s `today_step_buckets`.
  final List<StepBucket> buckets;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the steps history.
  final VoidCallback? onDetails;

  /// Steps per hour of the day, midnight first; an hour with no bucket is 0
  /// only when a later hour has steps — the strap was counting, and counted none.
  List<double?> get byHour {
    if (buckets.isEmpty) return const <double?>[];
    final hours = <int, double>{};
    for (final bucket in buckets) {
      hours.update(
        bucket.bucket ~/ 4,
        (sum) => sum + bucket.steps,
        ifAbsent: () => bucket.steps,
      );
    }
    final last = hours.keys.reduce(math.max);
    return <double?>[for (var hour = 0; hour <= last; hour++) hours[hour] ?? 0];
  }

  @override
  Widget build(BuildContext context) {
    final steps = day.steps.valueOrNull;
    final bars = byHour;
    return Panel(
      tone: Tone.movement,
      label: 'Steps today',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.walking,
        infoKey: 'steps_total',
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            steps == null ? '—' : groupedInt(steps),
            unit: 'steps',
            context_: switch (day.steps) {
              Withheld<int>(:final disclosure) => disclosure.message,
              _ when day.distanceKm.valueOrNull != null =>
                '${day.distanceKm.valueOrNull!.toStringAsFixed(2)} km\n'
                    'Daily total',
              _ => 'Daily total',
            },
          ),
          if (bars.isEmpty)
            const PanelNote(kNoHoursNote)
          else ...<Widget>[
            RevealOnce(
              id: 'today.steps-by-hour',
              registry: reveals,
              builder: (context, t) => V02BarChart(
                bars,
                progress: t,
                labels: _hourLabels(bars.length),
                semanticLabel: 'Steps by hour today',
              ),
            ),
            const PanelNote(kStepsByHourNote),
          ],
        ],
      ),
    );
  }
}

/// The day's heart rate: the last reading, the day by hour, and its range.
class HeartRateDayCard extends StatelessWidget {
  /// [hourly] is the server's hourly heart rate; [resting] its canonical RHR.
  const HeartRateDayCard({
    required this.day,
    required this.hourly,
    required this.resting,
    required this.reveals,
    super.key,
  });

  /// The card's title.
  static const String title = 'Heart rate';

  /// The strap's own samples for the day — the last reading comes from here.
  final DeviceDay day;

  /// `/api/today`'s `today_hr_series`.
  final List<HourPoint> hourly;

  /// `rhr_daily`, the one definition of resting heart rate.
  final Reading<double> resting;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The lowest and highest single samples the server kept, or nulls.
  (double?, double?) get range {
    final lows = hourly.map((p) => p.minimum).whereType<double>();
    final highs = hourly.map((p) => p.maximum).whereType<double>();
    return (
      lows.isEmpty ? null : lows.reduce(math.min),
      highs.isEmpty ? null : highs.reduce(math.max),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = day.heartRate.valueOrNull;
    final at = day.heartRateSeries.isEmpty ? null : day.heartRateSeries.last.at;
    final series = _byHour(hourly, (point) => point.average);
    final (low, high) = range;
    final rest = resting.valueOrNull;
    return Panel(
      tone: Tone.heart,
      label: 'Heart rate today',
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.heart,
        infoKey: 'rhr_daily',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            latest == null ? '—' : latest.round().toString(),
            unit: 'bpm',
            context_: _lastReading(day.heartRate, at),
          ),
          if (series.isEmpty)
            const PanelNote(kNoHoursNote)
          else ...<Widget>[
            RevealOnce(
              id: 'today.heart-rate-by-hour',
              registry: reveals,
              builder: (context, t) => V02LineChart(
                series,
                progress: t,
                unit: 'bpm',
                height: 140,
                captions: _edges(series.length),
                sampleLabels: _hourLabels(series.length),
                semanticLabel: 'Heart rate by hour today',
              ),
            ),
            StatRow(<Stat>[
              if (rest != null)
                Stat('Resting', rest.round().toString(), unit: 'bpm'),
              if (low != null)
                Stat('Lowest', low.round().toString(), unit: 'bpm'),
              if (high != null)
                Stat('Highest', high.round().toString(), unit: 'bpm'),
            ]),
            const PanelNote(kHeartRateDayNote),
          ],
        ],
      ),
    );
  }
}

/// The day's stress: the last reading, the day by hour, and its peak hour.
class StressDayCard extends StatelessWidget {
  /// [latest] is the strap's stress stream for the day, if it has one.
  const StressDayCard({
    required this.latest,
    required this.hourly,
    required this.reveals,
    super.key,
  });

  /// The card's title.
  static const String title = 'Stress';

  /// The strap's `stress` stream — its latest reading and when.
  final DeviceMetric? latest;

  /// `/api/today`'s `today_stress_series`.
  final List<HourPoint> hourly;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The hour with the highest hourly average, or null.
  HourPoint? get peak => hourly.isEmpty
      ? null
      : hourly.reduce((a, b) => b.average > a.average ? b : a);

  @override
  Widget build(BuildContext context) {
    final reading = latest?.reading ?? notMeasured<double>('stress');
    final value = reading.valueOrNull;
    final series = _byHour(hourly, (point) => point.average);
    final top = peak;
    return Panel(
      tone: Tone.stress,
      label: 'Stress today',
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.pulse,
        infoKey: 'stress',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            value == null ? '—' : value.round().toString(),
            unit: '/100',
            context_: _lastReading(reading, latest?.measuredAt),
          ),
          if (series.isEmpty)
            const PanelNote(kNoHoursNote)
          else ...<Widget>[
            RevealOnce(
              id: 'today.stress-by-hour',
              registry: reveals,
              builder: (context, t) => V02LineChart(
                series,
                progress: t,
                height: 140,
                zeroBased: true,
                captions: _edges(series.length),
                sampleLabels: _hourLabels(series.length),
                semanticLabel: 'Stress by hour today',
              ),
            ),
            if (top != null)
              StatRow(<Stat>[
                Stat(
                  'Highest hour · ${shortClock(top.hour)}',
                  top.average.round().toString(),
                ),
              ]),
            const PanelNote(kStressDayNote),
          ],
        ],
      ),
    );
  }
}
