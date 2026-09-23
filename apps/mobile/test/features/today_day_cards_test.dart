/// F1: Today's three day cards — steps, heart rate and stress, each its own.
///
/// What this suite holds:
///   * the hours sit on the day's clock: slot h is hour h, and a missing hour
///     is a gap, never a zero (the strap was not worn, or sent nothing);
///   * every figure is someone else's reading — the strap's latest sample, the
///     server's hourly aggregates, the server's canonical resting heart rate;
///   * a day the server sent no hours for says so instead of drawing a flat line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/device/device_metric.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/features/today/v02/day_cards.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/reveal_once.dart';

HourPoint _hour(int hour, double avg, {double? min, double? max}) =>
    HourPoint(hour: hour, average: avg, minimum: min, maximum: max, count: 4);

/// A day whose last heart-rate sample was 72 bpm at 14:05.
DeviceDay _day() {
  final empty = DeviceDay.empty('2026-07-31');
  return DeviceDay(
    date: empty.date,
    steps: const Present<int>(9264),
    distanceKm: const Present<double>(6.71),
    deviceCalories: empty.deviceCalories,
    stepsReadAt: null,
    heartRate: const Present<double>(72),
    heartRateSeries: <DevicePoint>[
      DevicePoint(DateTime(2026, 7, 31, 13, 50), 70),
      DevicePoint(DateTime(2026, 7, 31, 14, 5), 72),
    ],
    lastNight: empty.lastNight,
    metrics: empty.metrics,
    workouts: const [],
    sync: empty.sync,
    batteryPercent: null,
  );
}

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('steps', () {
    test('15-minute buckets add up into hours, midnight first', () {
      final card = StepsDayCard(
        day: _day(),
        buckets: const <StepBucket>[
          StepBucket(bucket: 0, time: '00:00', steps: 16),
          StepBucket(bucket: 8, time: '02:00', steps: 5),
          StepBucket(bucket: 9, time: '02:15', steps: 7),
        ],
        reveals: RevealRegistry(),
      );
      // Hour 1 had no bucket but the strap counted on either side of it: zero.
      expect(card.byHour, <double?>[16, 0, 12]);
    });

    testWidgets('the total is the strap’s own counter, with its distance', (
      tester,
    ) async {
      await _pump(
        tester,
        StepsDayCard(
          day: _day(),
          buckets: const <StepBucket>[
            StepBucket(bucket: 24, time: '06:00', steps: 40),
            StepBucket(bucket: 28, time: '07:00', steps: 44),
          ],
          reveals: RevealRegistry(),
        ),
      );
      expect(find.text('9,264'), findsOneWidget);
      expect(find.textContaining('6.71 km'), findsOneWidget);
      expect(find.byType(V02BarChart), findsOneWidget);
    });

    testWidgets('no buckets: says so, draws no chart', (tester) async {
      await _pump(
        tester,
        StepsDayCard(day: _day(), buckets: const [], reveals: RevealRegistry()),
      );
      expect(find.text(kNoHoursNote), findsOneWidget);
      expect(find.byType(V02BarChart), findsNothing);
    });
  });

  group('heart rate', () {
    final hourly = <HourPoint>[
      _hour(6, 64, min: 62, max: 65),
      _hour(7, 127, min: 66, max: 149),
      // 08:00 missing — not worn.
      _hour(9, 76, min: 74, max: 77),
    ];

    testWidgets('THE LAST READING, THE HOURS ON THE CLOCK, THE RANGE', (
      tester,
    ) async {
      await _pump(
        tester,
        HeartRateDayCard(
          day: _day(),
          hourly: hourly,
          resting: const Present<double>(55),
          reveals: RevealRegistry(),
        ),
      );
      expect(find.text('72'), findsOneWidget);
      expect(find.text('Last reading · 14:05'), findsOneWidget);

      final chart = tester.widget<V02LineChart>(find.byType(V02LineChart));
      expect(chart.values, <double?>[
        null, null, null, null, null, null, 64, 127, null, 76, //
      ]);
      // Resting is the server's canonical figure; the range is the extremes of
      // samples the server already bounded.
      expect(find.text('55'), findsOneWidget);
      expect(find.text('62'), findsOneWidget);
      expect(find.text('149'), findsOneWidget);
    });

    testWidgets('no hours: says so, draws no chart', (tester) async {
      await _pump(
        tester,
        HeartRateDayCard(
          day: _day(),
          hourly: const [],
          resting: const Present<double>(55),
          reveals: RevealRegistry(),
        ),
      );
      expect(find.text(kNoHoursNote), findsOneWidget);
      expect(find.byType(V02LineChart), findsNothing);
    });
  });

  group('stress', () {
    DeviceMetric stressAt(double value, DateTime at) => DeviceMetric(
      stream: kDeviceStreams.firstWhere((s) => s.metric == 'stress'),
      reading: Present<double>(value),
      measuredAt: at,
      sampleCount: 12,
    );

    testWidgets('the last reading and the peak hour', (tester) async {
      await _pump(
        tester,
        StressDayCard(
          latest: stressAt(41, DateTime(2026, 7, 31, 14, 10)),
          hourly: <HourPoint>[_hour(6, 32), _hour(11, 52), _hour(12, 37)],
          reveals: RevealRegistry(),
        ),
      );
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Last reading · 14:10'), findsOneWidget);
      expect(find.textContaining('Highest hour · 11a'), findsOneWidget);
      expect(find.text('52'), findsOneWidget);
    });

    testWidgets('no strap stream: a dash, never a zero', (tester) async {
      await _pump(
        tester,
        StressDayCard(
          latest: null,
          hourly: <HourPoint>[_hour(6, 32), _hour(7, 36)],
          reveals: RevealRegistry(),
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });
}
