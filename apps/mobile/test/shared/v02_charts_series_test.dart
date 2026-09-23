/// The line chart and the sparkline, asserted on what they PAINTED.
///
/// Every check here reads a recorded canvas rather than a widget tree. Two
/// charts on this project shipped at zero height because their tests asked
/// whether the widget existed, and three shipped with the caption lying across
/// the trace because "the label goes outside the plot" was a rule rather than a
/// measurement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_scrub.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/charts/v02/v02_sparkline.dart';
import 'package:healthee/shared/reveal_once.dart';

import '_chart_probe.dart';
import '_v02_chart_probe.dart';

/// One of the owner's own days, hour by hour.
const List<double?> _hrDay = <double?>[
  58, 56, 55, 54, 55, 57, 62, 71,
  78, 74, 69, 72, 80, 76, 70, 68,
  73, 79, 72, 66, 63, 61, 60, 59,
];

final List<String> _hours = <String>[
  for (var hour = 0; hour < 24; hour++)
    '${hour.toString().padLeft(2, '0')}:00',
];

V02LineChart _day({
  List<double?> values = _hrDay,
  double progress = 1,
  bool fill = true,
  List<ChartReference> references = const <ChartReference>[],
}) => V02LineChart(
  values,
  progress: progress,
  unit: 'bpm',
  fill: fill,
  captions: const <String>['00:00', '23:00'],
  sampleLabels: _hours,
  references: references,
);

void main() {
  final chart = find.byType(V02LineChart);

  group('the line chart draws a chart', () {
    testWidgets('at its real height, with real geometry in it', (tester) async {
      await pumpChart(tester, _day());
      final size = paintSize(tester, chart);
      expect(size.height, 168);
      expect(size.width, kChartWidth);

      final marks = markRectsOf(paintedAt(tester, chart));
      expect(marks, isNotEmpty);
      final plot = ChartMetrics.series.box(size).plot;
      final drawn = marks.reduce((a, b) => a.expandToInclude(b));
      // A trace using a third of its own box is a chart about its padding.
      expect(drawn.height, greaterThan(plot.height * 0.4));
      expect(drawn.width, greaterThan(plot.width * 0.9));
      for (final mark in marks) {
        expect(plot.inflate(6).contains(mark.topLeft), isTrue);
        expect(plot.inflate(6).contains(mark.bottomRight), isTrue);
      }
    });

    testWidgets('with a reference the axis was widened to hold', (tester) async {
      await pumpChart(
        tester,
        _day(
          references: const <ChartReference>[
            ChartReference.personalBaseline(value: 41, label: 'Your resting'),
          ],
        ),
      );
      final painter = painterFor<SeriesPainter>(tester, chart);
      expect(painter.ticks.low, lessThanOrEqualTo(41));
      // The words are a widget under the chart, never ink in the plot.
      expect(find.byType(ChartReferenceCaption), findsOneWidget);
    });
  });

  group('a label is never ink in the plot', () {
    for (final dark in <bool>[true, false]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('$theme: no glyph is inside the plot', (tester) async {
        await pumpChart(tester, _day(), dark: dark);
        final calls = paintedAt(tester, chart);
        final glyphs = glyphRectsOf(calls);
        expect(glyphs.length, greaterThanOrEqualTo(4));
        final plot = ChartMetrics.series
            .box(paintSize(tester, chart))
            .plot;
        for (final glyph in glyphs) {
          expect(
            glyph.overlaps(plot),
            isFalse,
            reason: '$glyph is inside the plot $plot',
          );
        }
      });

      testWidgets('$theme: every glyph clears every mark', (tester) async {
        await pumpChart(tester, _day(), dark: dark);
        final calls = paintedAt(tester, chart);
        for (final glyph in glyphRectsOf(calls)) {
          for (final mark in markRectsOf(calls)) {
            expect(
              clearsBy(glyph, mark, ChartMetrics.clearance),
              isTrue,
              reason: '$glyph is within 2 px of the mark $mark',
            );
          }
        }
      });

      testWidgets('$theme: no glyph touches another glyph', (tester) async {
        await pumpChart(tester, _day(), dark: dark);
        final glyphs = glyphRectsOf(paintedAt(tester, chart));
        for (var i = 0; i < glyphs.length; i++) {
          for (var j = i + 1; j < glyphs.length; j++) {
            expect(glyphs[i].overlaps(glyphs[j]), isFalse);
          }
        }
      });
    }

    testWidgets('the scrub bubble stays out of the plot too', (tester) async {
      await pumpChart(tester, _day());
      final size = paintSize(tester, chart);
      final box = ChartMetrics.series.box(size);
      final origin = tester.getTopLeft(painterOf(chart));
      await tester.tapAt(
        origin + Offset(box.x(12, _hrDay.length), box.plot.center.dy),
      );
      await tester.pump();
      final calls = paintedAt(tester, chart);
      for (final glyph in glyphRectsOf(calls)) {
        expect(glyph.overlaps(box.plot), isFalse, reason: '$glyph');
      }
      await tester.pump(ChartScrub.linger * 2);
    });
  });

  group('honesty', () {
    testWidgets('a null breaks the line rather than bridging it', (
      tester,
    ) async {
      final holed = List<double?>.from(_hrDay)..[10] = null;
      // Light, so the dark-only glow does not add a second stroke per run.
      await pumpChart(tester, _day(values: holed, fill: false), dark: false);
      expect(countOf(paintedAt(tester, chart), #drawPath), 2);

      await pumpChart(tester, _day(fill: false), dark: false);
      expect(countOf(paintedAt(tester, chart), #drawPath), 1);
    });

    testWidgets('a withheld series paints nothing and keeps its slot', (
      tester,
    ) async {
      await pumpChart(tester, _day(values: const <double?>[68, null, null]));
      expect(
        find.descendant(of: chart, matching: find.byType(CustomPaint)),
        findsNothing,
      );
      expect(
        tester.getSize(chart).height,
        168 + ChartScrub.readoutHeight,
      );
    });

    testWidgets('the gridline is the token, not a re-derived alpha', (
      tester,
    ) async {
      await pumpChart(tester, _day());
      expect(
        coloursOf(paintedAt(tester, chart)),
        contains(const HealtheeColors.dark().grid.toARGB32()),
      );
    });
  });

  group('the scrubber', () {
    testWidgets('reports the value under the cursor', (tester) async {
      await pumpChart(tester, _day());
      final box = ChartMetrics.series.box(paintSize(tester, chart));
      final origin = tester.getTopLeft(painterOf(chart));
      expect(find.text('Touch the chart to explore · bpm'), findsOneWidget);

      await tester.tapAt(
        origin + Offset(box.x(12, _hrDay.length), box.plot.center.dy),
      );
      await tester.pump();
      expect(find.text('12:00 · 80 bpm'), findsOneWidget);
      expect(painterFor<SeriesPainter>(tester, chart).touch, 12);
      expect(painterFor<SeriesPainter>(tester, chart).bubbleText, '80 bpm');

      await tester.pump(ChartScrub.linger * 2);
      expect(find.text('Touch the chart to explore · bpm'), findsOneWidget);
    });

    testWidgets('a format writes the reading instead of digits and unit', (
      tester,
    ) async {
      await pumpChart(
        tester,
        V02LineChart(
          _hrDay,
          progress: 1,
          unit: 'bpm',
          format: (value) => '${value.round()} beats',
          sampleLabels: _hours,
        ),
      );
      final box = ChartMetrics.series.box(paintSize(tester, chart));
      final origin = tester.getTopLeft(painterOf(chart));
      await tester.tapAt(
        origin + Offset(box.x(12, _hrDay.length), box.plot.center.dy),
      );
      await tester.pump();
      expect(find.text('12:00 · 80 beats'), findsOneWidget);
      expect(painterFor<SeriesPainter>(tester, chart).bubbleText, '80 beats');
      await tester.pump(ChartScrub.linger * 2);
    });

    testWidgets('says "not measured" rather than inventing one', (tester) async {
      final holed = List<double?>.from(_hrDay)..[12] = null;
      await pumpChart(tester, _day(values: holed));
      final box = ChartMetrics.series.box(paintSize(tester, chart));
      final origin = tester.getTopLeft(painterOf(chart));
      await tester.tapAt(
        origin + Offset(box.x(12, holed.length), box.plot.center.dy),
      );
      await tester.pump();
      expect(find.text('12:00 · not measured'), findsOneWidget);
      await tester.pump(ChartScrub.linger * 2);
    });
  });

  group('the reveal', () {
    testWidgets('plays once and never replays', (tester) async {
      final registry = RevealRegistry();
      Widget build() => RevealOnce(
        id: 'heart-rate-day',
        registry: registry,
        builder: (context, t) =>
            V02Sparkline(_hrDay, progress: t, key: const Key('spark')),
      );
      final spark = find.byType(V02Sparkline);

      await pumpChart(tester, build());
      expect(painterFor<SeriesPainter>(tester, spark).progress, lessThan(0.2));
      await tester.pumpAndSettle();
      expect(painterFor<SeriesPainter>(tester, spark).progress, 1);

      // Scrolled away and back: a fresh element, the same registry.
      await pumpChart(tester, const SizedBox.shrink());
      await pumpChart(tester, build());
      expect(
        painterFor<SeriesPainter>(tester, spark).progress,
        1,
        reason: 'the chart animated again on its second build',
      );
    });
  });

  group('the sparkline', () {
    testWidgets('is the plot and nothing else, and keeps its dot', (
      tester,
    ) async {
      await pumpChart(tester, const V02Sparkline(_hrDay, progress: 1));
      final spark = find.byType(V02Sparkline);
      final size = paintSize(tester, spark);
      expect(size.height, 26);
      final calls = paintedAt(tester, spark);
      expect(glyphRectsOf(calls), isEmpty);
      expect(countOf(calls, #drawCircle), 2);
      final box = ChartMetrics.bare.box(size);
      for (final mark in markRectsOf(calls)) {
        expect(box.plot.inflate(6).contains(mark.center), isTrue);
      }
    });

    testWidgets('withholds at full height', (tester) async {
      await pumpChart(
        tester,
        const V02Sparkline(<double?>[68], progress: 1, height: 30),
      );
      expect(
        find.descendant(
          of: find.byType(V02Sparkline),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(tester.getSize(find.byType(V02Sparkline)).height, 30);
    });
  });
}
