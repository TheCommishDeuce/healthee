/// Bars, intraday buckets and the linked dual-axis chart — on painted geometry.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_scrub.dart';
import 'package:healthee/shared/charts/v02/column_painter.dart';
import 'package:healthee/shared/charts/v02/linked_painter.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';

import '_chart_probe.dart';
import '_v02_chart_probe.dart';

const List<double?> _week = <double?>[
  8200, 11400, 6100, 9800, 12600, 4300, 10500,
];
const List<String> _days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

const List<double?> _hr = <double?>[
  62, 65, 71, 88, 96, 84, 77, 92, 105, 88, 74, 68,
];
const List<double?> _stress = <double?>[
  22, 25, 34, 51, 62, 48, 40, 55, 71, 52, 33, 28,
];
const List<String> _clock = <String>[
  '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
  '12:00', '13:00', '14:00', '15:00', '16:00', '17:00',
];

void main() {
  group('bars', () {
    final bars = find.byType(V02BarChart);

    testWidgets('stand on zero, because a bar means its length', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(_week, progress: 1, labels: _days),
        tone: Tone.movement,
      );
      expect(painterFor<ColumnPainter>(tester, bars).ticks.low, 0);
    });

    testWidgets('emphasise the current bar by weight, not by hue', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(_week, progress: 1, labels: _days),
        tone: Tone.movement,
        dark: false,
      );
      final columns = columnsOf(paintedAt(tester, bars));
      expect(columns.length, _week.length);
      final current = columns.last.$2;
      for (final column in columns.take(columns.length - 1)) {
        expect(column.$2.a, lessThan(current.a));
        // Same hue, quieter — a past day is not a different kind of thing.
        expect(column.$2.r, closeTo(current.r, 0.001));
      }
      expect(current.a, 1);
    });

    testWidgets('a measured zero marks the baseline; a null draws nothing', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(
          <double?>[0, null, 5000],
          progress: 1,
          labels: <String>['M', 'T', 'W'],
        ),
        tone: Tone.movement,
        dark: false,
      );
      final columns = columnsOf(paintedAt(tester, bars));
      expect(columns.length, 2);
      expect(columns.first.$1.height, greaterThan(0));
      expect(columns.first.$1.height, lessThan(4));
    });

    testWidgets('a target is a line in the plot and words underneath', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(
          _week,
          progress: 1,
          labels: _days,
          target: ChartReference.convention(
            value: 8000,
            label: 'A published convention, not your own number',
          ),
        ),
        tone: Tone.movement,
      );
      expect(find.byType(ChartReferenceCaption), findsOneWidget);
      final box = ChartMetrics.framed.box(paintSize(tester, bars));
      final dashes = linesOf(paintedAt(tester, bars))
          .where((line) => line.$1.dy == line.$2.dy)
          .where((line) => line.$2.dx - line.$1.dx < box.plot.width / 2);
      expect(dashes, isNotEmpty, reason: 'the convention was drawn solid');
    });

    testWidgets('captions clear the bars and each other', (tester) async {
      await pumpChart(
        tester,
        V02BarChart(
          List<double?>.filled(28, 9000),
          progress: 1,
          labels: List<String>.filled(28, 'Mon'),
        ),
        tone: Tone.movement,
        dark: false,
      );
      final calls = paintedAt(tester, bars);
      final glyphs = glyphRectsOf(calls);
      expect(glyphs.length, lessThan(28), reason: 'labels were not thinned');
      expect(glyphs, isNotEmpty);
      for (var i = 0; i < glyphs.length; i++) {
        for (final mark in markRectsOf(calls)) {
          expect(clearsBy(glyphs[i], mark, ChartMetrics.clearance), isTrue);
        }
        for (var j = i + 1; j < glyphs.length; j++) {
          expect(
            glyphs[i].overlaps(glyphs[j]),
            isFalse,
            reason: '${glyphs[i]} vs ${glyphs[j]}',
          );
        }
      }
    });

    testWidgets('withholds at full height when nothing was measured', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(<double?>[null, null], progress: 1, height: 150),
      );
      expect(
        find.descendant(of: bars, matching: find.byType(CustomPaint)),
        findsNothing,
      );
      expect(tester.getSize(bars).height, 150);
    });
  });

  group('the linked chart', () {
    final linked = find.byType(V02LinkedChart);

    Widget dayTogether({List<double?> stress = _stress}) => V02LinkedChart(
      <LinkedPane>[
        const LinkedPane(
          tone: Tone.heart,
          label: 'Heart rate',
          values: _hr,
          unit: 'bpm',
        ),
        LinkedPane(
          tone: Tone.stress,
          label: 'Stress',
          values: stress,
        ),
      ],
      progress: 1,
      captions: const <String>['06:00', '17:00'],
      sampleLabels: _clock,
    );

    testWidgets('gives each signal its own labelled scale', (tester) async {
      await pumpChart(tester, dayTogether());
      final lanes = painterFor<LinkedPainter>(tester, linked).lanes;
      expect(lanes.length, 2);
      expect(lanes.first.ticks.high, isNot(lanes.last.ticks.high));
      expect(lanes.first.ink.family, isNot(lanes.last.ink.family));
      // Both axes are written, and the pane names with them.
      expect(glyphRectsOf(paintedAt(tester, linked)).length, greaterThan(6));
    });

    testWidgets('runs one cursor through both plots and the gap', (
      tester,
    ) async {
      await pumpChart(tester, dayTogether());
      final size = paintSize(tester, linked);
      final boxes = linkedBoxes(size, 2);
      final origin = tester.getTopLeft(painterOf(linked));
      await tester.tapAt(
        origin + Offset(boxes.first.x(6, _hr.length), boxes.first.plot.center.dy),
      );
      await tester.pump();

      final vertical = linesOf(
        paintedAt(tester, linked),
      ).where((line) => line.$1.dx == line.$2.dx).toList();
      expect(vertical, hasLength(1));
      expect(vertical.single.$1.dy, boxes.first.plot.top);
      expect(vertical.single.$2.dy, boxes.last.plot.bottom);
      expect(painterFor<LinkedPainter>(tester, linked).touch, 6);
      expect(find.text('77 bpm'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      await tester.pump(ChartScrub.linger * 2);
    });

    testWidgets('says a coincidence is not a cause, without being asked', (
      tester,
    ) async {
      await pumpChart(tester, dayTogether());
      expect(
        find.text(V02LinkedChart.coincidenceCaveat),
        findsOneWidget,
      );
    });

    testWidgets('withholds both panes when either is too short', (
      tester,
    ) async {
      await pumpChart(
        tester,
        dayTogether(stress: const <double?>[22, null, null]),
      );
      expect(
        find.descendant(of: linked, matching: find.byType(CustomPaint)),
        findsNothing,
      );
      expect(tester.getSize(linked).height, 236 + ChartScrub.readoutHeight);
    });

    testWidgets('keeps every label out of both plots', (tester) async {
      await pumpChart(tester, dayTogether(), dark: false);
      final calls = paintedAt(tester, linked);
      final boxes = linkedBoxes(paintSize(tester, linked), 2);
      for (final glyph in glyphRectsOf(calls)) {
        for (final box in boxes) {
          expect(glyph.overlaps(box.plot), isFalse, reason: '$glyph');
        }
        for (final mark in markRectsOf(calls)) {
          expect(clearsBy(glyph, mark, ChartMetrics.clearance), isTrue);
        }
      }
    });
  });

  group('the no-colour rule', () {
    /// A chart that accepted a `Color` could be handed one that disagrees with
    /// the card it sits in, and nothing would catch it — which is how legacy
    /// drew cardio load red on one screen and green on another. The tone
    /// cascade is the fix; this is what keeps it.
    test('no v02 chart widget takes or holds a Color', () {
      final widgets = Directory('lib/shared/charts/v02')
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('v02_'));
      expect(widgets, isNotEmpty);
      for (final file in widgets) {
        expect(
          RegExp(r'\bColor\b').hasMatch(file.readAsStringSync()),
          isFalse,
          reason: '${file.path} names a Color; it should read its tone',
        );
      }
    });
  });
}
