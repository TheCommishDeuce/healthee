/// One metric's history, rebuilt to v02 — its order, its geometry, its refusals.
///
/// The claims here are the ones a "does the screen render" test cannot make:
///
///   * **The order is the prototype's**, asserted on the rendered strings rather
///     than on a widget list, because a section that landed below the fold is
///     still in the tree.
///   * **A gap breaks the line**, asserted on the recorded canvas. This is the
///     rule the whole window type exists for.
///   * **A polarity-unknown metric gets no verdict colour.** The load-bearing
///     one: a colour that appears for every metric teaches the owner that no
///     colour on the screen is a judgement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/history/history_screen.dart';
import 'package:healthee/features/history/v02/dated_readings.dart';
import 'package:healthee/features/history/v02/history_panel.dart';
import 'package:healthee/features/history/v02/metric_hero.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';

import '../shared/_chart_probe.dart';
import '../shared/_v02_chart_probe.dart';
import '../shared/_v02_harness.dart';
import '_history_host.dart';

/// A fortnight of HRV with two nights missing, ending on the host's today.
const List<TrendPoint> _hrv = <TrendPoint>[
  TrendPoint(date: '2026-07-29', value: 41),
  TrendPoint(date: '2026-07-30', value: 44),
  // 07-31 and 08-01 are missing.
  TrendPoint(date: '2026-08-02', value: 46),
  TrendPoint(date: '2026-08-03', value: 45),
  TrendPoint(date: '2026-08-04', value: 48),
];

/// The same shape on a metric the polarity table has never heard of.
const List<TrendPoint> _steps = <TrendPoint>[
  TrendPoint(date: '2026-08-02', value: 6100),
  TrendPoint(date: '2026-08-03', value: 8200),
  TrendPoint(date: '2026-08-04', value: 9400),
];

Future<void> _pump(
  WidgetTester tester, {
  HistoryMetric metric = HistoryMetric.hrv,
  List<TrendPoint> series = _hrv,
  String? viewDate,
  double width = 390,
}) async {
  tester.view
    ..physicalSize = Size(width, 3200)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    historyHost(
      HistoryScreen(initialMetric: metric.id),
      metric: metric,
      series: series,
      width: width,
    ),
  );
  await tester.pumpAndSettle();
  if (viewDate case final String day) {
    await selectDay(tester, day);
  }
}

void main() {
  useRealFonts();

  group('the order is the prototype’s', () {
    testWidgets('SEGMENT · HERO · CARD · CONTEXT · EVIDENCE · FOOTER', (
      tester,
    ) async {
      await _pump(tester);
      final texts = textsOn(tester);
      // `screens-explore.js::H.screens.metric`, read top to bottom — with ONE
      // departure from the prototype, and it is load-bearing.
      //
      // **The segment sits above the hero, not below it.** The prototype puts
      // it after, and this screen built it inside the `AsyncView` that renders
      // the fetched window — so selecting a period built a new provider family
      // member with no cached value, the view swapped to its loading state, and
      // the control the owner had just pressed was destroyed and rebuilt along
      // with everything under it. Above the fetch it depends only on local
      // state and survives the request it starts.
      final order = <String>[
        'Overnight HRV.', // the detail head's h1
        '30 days', // .segment — see above
        'Latest · 4 Aug', // .metric-hero p
        'Mean', // .three
        'Range', // H.note
        'See dated readings', // <details>
        'Put this in context', // H.section
        'Ask about this trend',
        kEvidenceLabel, // H.evidence
        'Your data. A little better understood.', // the footer
      ];
      var previous = -1;
      for (final line in order) {
        final at = indexOfText(texts, line);
        expect(at, greaterThan(previous), reason: '"$line" is out of order');
        previous = at;
      }
    });

    testWidgets('the head names the day and whether it is the latest', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.textContaining('· Latest'), findsOneWidget);

      await _pump(tester, viewDate: '2026-08-02');
      expect(find.textContaining('· Selected day'), findsOneWidget);
    });

    testWidgets('the four periods are the prototype’s, in its order', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        kHistoryPeriods.map((option) => option.$2).toList(),
        <String>['30 days', '90 days', '1 year', '5 years'],
      );
      for (final (_, label) in kHistoryPeriods) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('the chart is honest about what was measured', () {
    testWidgets('A GAP BREAKS THE LINE RATHER THAN BRIDGING IT', (
      tester,
    ) async {
      await _pump(tester);
      final chart = find.byType(V02LineChart);
      final painter = painterFor<SeriesPainter>(tester, chart);
      // Two measured stretches either side of 31 Jul–1 Aug.
      expect(seriesRuns(painter.values).length, 2);
      expect(painter.values, <double?>[41, 44, null, null, 46, 45, 48]);
    });

    testWidgets('the trace really lands inside its own plot', (tester) async {
      await _pump(tester);
      final chart = find.byType(V02LineChart);
      final marks = markRectsOf(paintedAt(tester, chart));
      expect(marks, isNotEmpty);
      final size = paintSize(tester, chart);
      final drawn = marks.reduce((a, b) => a.expandToInclude(b));
      expect(drawn.width, greaterThan(size.width * 0.5));
      expect(drawn.height, greaterThan(0));
    });

    testWidgets('a daily total is joined straight, never splined', (
      tester,
    ) async {
      // A curve between two daily totals is a claim about a value nobody
      // measured; `chart_curve.dart` argues it and `metric_series.dart` keys it.
      await _pump(tester, metric: HistoryMetric.steps, series: _steps);
      final painter = painterFor<SeriesPainter>(
        tester,
        find.byType(V02LineChart),
      );
      expect(painter.curve, SeriesCurve.straight);
    });
  });

  group('the verdict colour', () {
    testWidgets('A POLARITY-UNKNOWN METRIC GETS NO VERDICT COLOUR', (
      tester,
    ) async {
      // **Breathing rate is not in `metric_polarity.dart`.** Steps used to be
      // the example here and no longer is: `steps_mortality` is Established and
      // monotonic upward over the range a person walks, so the table now makes
      // that claim and the trends grid colours it. Overnight respiratory rate
      // has no such note, so it keeps the original point — the ordinary ink IS
      // the assertion, because colouring by the sign of a delta would be the
      // app finding good news in a number it cannot judge.
      await _pump(
        tester,
        metric: HistoryMetric.breathing,
        series: _steps,
      );
      final change = tester.widget<Text>(
        find.descendant(of: find.byType(ChangeStat), matching: find.byType(Text)).last,
      );
      // One decimal: the metric decides its own resolution, and a breathing
      // rate carries a tenth where a step count does not.
      expect(change.data, '+3300.0');
      expect(change.style!.color, kColors.ink);
      expect(change.style!.color, isNot(kColors.fav));
      expect(change.style!.color, isNot(kColors.unf));
    });

    testWidgets('a metric the table knows is coloured by its own polarity', (
      tester,
    ) async {
      // HRV is higherIsBetter and rose 41 → 48.
      await _pump(tester);
      final change = tester.widget<Text>(
        find.descendant(of: find.byType(ChangeStat), matching: find.byType(Text)).last,
      );
      expect(change.data, '+7.0');
      expect(change.style!.color, kColors.fav);
    });
  });

  group('what a screen must never print', () {
    testWidgets('NO RAW ID AND NO CITATION MARKER ON ANY SURFACE', (
      tester,
    ) async {
      await _pump(tester);
      for (final text in textsOn(tester)) {
        expect(text, isNot(contains('hrv_sleep_avg')));
        expect(text, isNot(contains('[')));
      }
      // The metric is named, in the words the rest of the app uses for it.
      expect(find.textContaining('Overnight HRV'), findsWidgets);
    });

    testWidgets('a day with no reading draws no figure and says why', (
      tester,
    ) async {
      await _pump(tester, viewDate: '2026-08-01');
      final hero = tester.widget<MetricHero>(find.byType(MetricHero));
      expect(hero.value, isNull);
      expect(hero.unit, isNotNull);
      expect(find.textContaining('No reading on this day'), findsOneWidget);
      // And the unit is dropped with the figure — a dash carries no `ms`.
      expect(find.text('— ms'), findsNothing);
    });

    testWidgets('an empty period draws no figures at all', (tester) async {
      await _pump(tester, series: const <TrendPoint>[]);
      expect(find.byType(ChangeStat), findsNothing);
      expect(find.textContaining('Range'), findsNothing);
      // The disclosure is in the tree and draws nothing: an empty table behind
      // a summary is a control that lies about having something behind it.
      expect(find.text('See dated readings'), findsNothing);
      for (final disclosure in tester.widgetList<DatedReadings>(
        find.byType(DatedReadings),
      )) {
        expect(disclosure.rows, isEmpty);
      }
    });
  });

  group('layout', () {
    testWidgets('nothing overflows at any phone width', (tester) async {
      for (final width in kPhoneWidths) {
        await _pump(tester, width: width);
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
    });
  });
}
