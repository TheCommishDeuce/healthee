/// `Every stage, accounted for` — one bar per stage, in the owner's own order.
///
/// ## What it replaced
///
/// A `Stage · Duration · Proportion` table under a stacked strip: three columns
/// of small type saying the same four facts the strip above it had just drawn,
/// and a header row spending a line on the words `Stage`, `Duration` and
/// `Proportion` to label numbers that need no labelling. Twelve cells, four
/// readings.
///
/// Now each stage is one row — a bar as long as its share, its percentage set
/// **inside** the fill, then the stage and the time it ran. The bar is the
/// proportion, so nothing has to be read off a legend and back onto a colour,
/// and the duration is the biggest thing on the row because it is the number
/// the reader came for.
///
/// ## ⛔ Do not put a decorative cap back on the bar
///
/// There was a hatched block after each fill — a fixed width on every row, in
/// the stage's hue, meaning nothing. It was there to stop a short bar ending
/// dead in the middle of the row. On a surface whose whole premise is that
/// every mark carries a reading, a mark that carries none is the one thing
/// that must not be on it, and the first question it drew was "what is that?".
///
/// **There is an honest version of it and this is not it.** The tail could
/// show the gap between this stage's share and a reference range — but that
/// needs a per-stage proportion reference, and `packages/knowledge` has no
/// note for one. Writing `Deep should be 13-23%` into a Dart string is exactly
/// the shape of the refuted `metric_info` claims the corpus exists to stop:
/// `insights/validator.py` cannot see a Dart string, so nothing would check
/// it. The note comes first, then the mark.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/format/time_labels.dart';

/// The four rows, in the order the night is read: awake at the top, deep last.
const List<String> kShareOrder = <String>['awake', 'rem', 'light', 'deep'];

/// One bar per stage, each carrying its share, its name and its duration.
class StageShares extends StatelessWidget {
  /// [minutes] is per stage; [total] is what the shares are taken against.
  const StageShares({required this.minutes, required this.total, super.key});

  /// Minutes per stage, in the app's own stage names.
  final Map<String, double> minutes;

  /// The denominator. Callers guarantee it is above zero.
  final double total;

  /// The row's bar height.
  static const double barHeight = 26;

  /// Its corner.
  static const double barRadius = 7;

  /// The gap between one row and the next.
  static const double rowGap = 14;

  /// The gap between the bar and the words after it.
  static const double textGap = 10;

  /// The most of the row's width a bar may take at 100%, leaving room for a
  /// name and a duration on the longest stage.
  static const double barShare = 0.56;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (int i, String stage) in kShareOrder.indexed) ...<Widget>[
          if (i > 0) const SizedBox(height: rowGap),
          _ShareRow(
            stage: stage,
            minutes: minutes[stage] ?? 0,
            share: (minutes[stage] ?? 0) / total,
          ),
        ],
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.stage,
    required this.minutes,
    required this.share,
  });

  final String stage;
  final double minutes;
  final double share;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hue = sleepStageColor(context.hues, stage);
    final percent = (100 * share).round();
    return LayoutBuilder(
      builder: (context, constraints) {
        // The fill is a share of the bar's own allowance, not of the row: a
        // 62% stage that ran to the row's edge would leave its name nowhere to
        // sit, and the two long rows are exactly the ones that need it.
        final allowance = constraints.maxWidth * StageShares.barShare;
        // **Offset, not clamped.** Clamping to a floor drew 15% and 31% at the
        // same length — the bar stopped encoding the share for exactly the
        // stages whose shares are closest and hardest to tell apart. Every bar
        // starts at [_minFill] so it can hold its own percentage, and the rest
        // of the allowance is divided by share, so the ORDER and the GAPS
        // between bars are the reading even though the origin is not zero.
        final fill = _minFill + share.clamp(0.0, 1.0) * (allowance - _minFill);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              height: StageShares.barHeight,
              width: fill,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: hue,
                  borderRadius: BorderRadius.circular(StageShares.barRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$percent%',
                      maxLines: 1,
                      // Ink chosen against the fill, not against the card: this
                      // label sits ON the stage hue, and every stage hue in
                      // both themes is a light one.
                      style: SleepType.tableCell.copyWith(
                        color: colors.onAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: StageShares.textGap),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    sleepStageLabel(stage),
                    maxLines: 1,
                    style: SleepType.tableCell.copyWith(color: colors.ink2),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hoursMinutes(minutes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SleepType.shareDuration.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Enough fill that the percentage inside it is still readable. A stage that
  /// ran for four minutes still has to print `1%` somewhere.
  static const double _minFill = 46;
}
