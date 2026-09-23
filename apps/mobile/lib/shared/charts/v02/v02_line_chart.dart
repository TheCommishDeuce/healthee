/// The workhorse: a value over time, with an axis you can read and a finger you
/// can put on it.
///
/// Heart rate across a day, HRV across a fortnight, temperature across a night —
/// any metric history. It is the chart the owner sees most, so it is the one
/// where the small things are worth doing: round ticks, a body that fades rather
/// than wipes, a glow on a ground that can carry one, a last-point dot ringed in
/// the surface so it reads over the fill, and a cursor that reports the sample
/// it is actually on.
///
/// ## It takes no colour, and it takes no baseline it was not given
///
/// The tone of the enclosing card decides the hue (`chart_ink.dart`), and
/// [references] are the server's lines — the client never computes a baseline of
/// its own, because `CLAUDE.md`'s one-definition-per-metric rule is exactly what
/// a second, on-device definition would break.
///
/// ## Two states, one height
///
/// A series with fewer than two measured samples draws **nothing** and keeps its
/// slot (`chart_void.dart`). The card's own words explain the absence; a flat
/// line at zero would not be an explanation, it would be a reading that never
/// happened.
library;

import 'package:flutter/material.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_scrub.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';
import 'package:healthee/shared/charts/v02/chart_void.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';

/// A line/area chart over [values], scrubbable, revealed by [progress].
class V02LineChart extends StatelessWidget {
  /// [values] is oldest first; a `null` is an unmeasured sample and breaks the
  /// line rather than being interpolated across.
  const V02LineChart(
    this.values, {
    required this.progress,
    this.height = 168,
    this.unit = '',
    this.digits = 0,
    this.format,
    this.curve = SeriesCurve.monotone,
    this.references = const <ChartReference>[],
    this.captions = const <String>[],
    this.sampleLabels = const <String>[],
    this.zeroBased = false,
    this.strokeWidth = 2.4,
    this.fill = true,
    this.semanticLabel,
    super.key,
  });

  /// The series, oldest first. Nulls are holes.
  final List<double?> values;

  /// 0–1 from `RevealOnce`. See `reveal_once.dart` for why it is a parameter.
  final double progress;

  /// The plot's height, excluding the readout line under it.
  final double height;

  /// The unit, shown in the bubble and the readout.
  final String unit;

  /// Decimal places in the bubble and the readout.
  final int digits;

  /// Writes a reading in the bubble and the readout, replacing [digits] and
  /// [unit] there — for a value no decimal reads naturally in, like a sleep
  /// duration (`6h 56m`, not `6.9 h`). The axis ticks stay plain numbers.
  final String Function(double value)? format;

  /// [SeriesCurve.monotone] for a continuous signal — the default, because that
  /// is what this chart is usually given. A daily total or a nightly minimum
  /// must pass [SeriesCurve.straight]; `chart_curve.dart` says why.
  final SeriesCurve curve;

  /// The lines this series is read against, named underneath.
  final List<ChartReference> references;

  /// The two edge captions — typically the first and last timestamp.
  final List<String> captions;

  /// One label per sample, for the readout. Shorter than [values] is fine; the
  /// readout falls back to the bare value.
  final List<String> sampleLabels;

  /// Whether the axis is pinned to zero. False for anything measured.
  final bool zeroBased;

  /// Trace weight.
  final double strokeWidth;

  /// Whether to lay a gradient body under the trace.
  final bool fill;

  /// What a screen reader is told the chart is.
  final String? semanticLabel;

  /// The height this widget occupies, drawn or withheld. They are equal, and
  /// that is the point — see `chart_void.dart`.
  double get slotHeight => height + ChartScrub.readoutHeight;

  @override
  Widget build(BuildContext context) {
    if (!canDrawSeries(values)) {
      return ChartVoid(height: slotHeight);
    }
    final ink = ChartInk.of(context);
    final ticks = ChartTicks.nice(
      values.whereType<double>(),
      include: <double>[for (final line in references) line.value],
      zeroBased: zeroBased,
    );
    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ChartScrub(
          sampleCount: values.length,
          height: height,
          metrics: ChartMetrics.series,
          chart: (context, index) => CustomPaint(
            painter: SeriesPainter(
              values: values,
              ticks: ticks,
              metrics: ChartMetrics.series,
              ink: ink,
              progress: progress,
              curve: curve,
              strokeWidth: strokeWidth,
              fill: fill,
              captions: captions,
              references: references,
              labelled: true,
              touch: index,
              bubbleText: _bubble(index),
              lastPointDot: true,
            ),
          ),
          readout: (context, index) => ChartReadoutText(_readout(index)),
        ),
        if (references.isNotEmpty) ChartReferenceCaption(references),
      ],
    );
    final label = semanticLabel;
    return label == null ? chart : Semantics(label: label, child: chart);
  }

  /// What the bubble says, or null when there is nothing under the finger.
  String? _bubble(int? index) {
    final value = _valueAt(index);
    return value == null ? null : _reading(value);
  }

  /// The sentence under the chart. The resting state is the instruction, ported
  /// from the prototype's `.chart-readout`: a chart that does not say it is
  /// interactive is a chart nobody touches.
  String _readout(int? index) {
    if (index == null) {
      return unit.isEmpty
          ? 'Touch the chart to explore'
          : 'Touch the chart to explore · $unit';
    }
    final value = _valueAt(index);
    final reading = value == null ? 'not measured' : _reading(value);
    final label = index < sampleLabels.length ? sampleLabels[index] : null;
    return label == null ? reading : '$label · $reading';
  }

  double? _valueAt(int? index) {
    if (index == null || index < 0 || index >= values.length) {
      return null;
    }
    final value = values[index];
    return value != null && value.isFinite ? value : null;
  }

  String _reading(double value) =>
      format?.call(value) ??
      '${value.toStringAsFixed(digits)}${unit.isEmpty ? '' : ' $unit'}';
}
