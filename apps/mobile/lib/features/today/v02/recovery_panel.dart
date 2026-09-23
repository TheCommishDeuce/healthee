/// `Recovery, explained` — the number, how the model divides, and its four bars.
///
/// `panels.js::H.recoveryPanel`, in order: the figure over 100 with the
/// overnight/remaining split beside it, the weight stack, the colour key, the
/// factor bars, and the note.
///
/// ## The components are the licence to show the number at all
///
/// `feedback_no_composite_score` is the rule and this card is the reason it
/// survives the redesign: a single 0–100 score with nothing under it is a
/// verdict, and the four bars are what turn it back into a model. They are
/// beside the number rather than behind a tap, exactly as the pre-v02 card had
/// them.
///
/// **They are the payload's factors, not a fixed four.** The prototype hard-codes
/// Sleep/HRV/Resting heart/Breathing at 40/30/20/10; a server that drops a term
/// or reweights one must show that, so the stack, the key and the bars are all
/// built from `recovery.factors` in the payload's own order. A factor with no
/// weight is left out of the stack and the key and still draws its bar — its
/// share is unknown, its score is not.
///
/// ## The framing sentence is not the server's guidance, and both are shown
///
/// `guidance` is the model's prose about today. The sentence under it is about
/// what the four bars **are** — "model components, not four additional health
/// scores" — and it is true on every payload, including the ones that carry no
/// guidance at all. Folding one into the other would lose whichever the day did
/// not happen to have.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/v02/colour_key.dart';
import 'package:healthee/shared/v02/labels.dart';
import 'package:healthee/shared/v02/meters.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// What the stacked bar is — how much each factor counts.
///
/// **The label is what makes the percentages safe to print.** Two numeric
/// columns against the same four names is a collision: the key reads `HRV 42%`
/// directly above a bar reading `HRV 30`, and nothing said that one is a fixed
/// share of the model and the other is last night — they look like they should
/// reconcile, and they cannot. Taking the percentages out fixed the collision
/// and cost the reader the most useful fact on the card, which is WHICH factor
/// is driving the number. Naming the two groups fixes it without that cost, so
/// the shares are back: under this heading, `42%` can only mean the share.
const String kRecoveryWeightsLabel = 'How much each counts';

/// What the four bars are — last night, scored.
const String kRecoveryScoresLabel = 'How each scored last night';

/// What the four bars ARE. Method, so it lives behind the ⓘ.
const String kRecoveryComponentsNote =
    'Model components, not four additional health scores.';

/// What the stacked bar is, and what happens to a missing factor's share.
///
/// The weights are `derive/recovery.py`'s `RECOVERY_WEIGHTS`, transcribed. The
/// renormalising clause is that file's `score = sum(w*sub)/tw` — `tw` is the sum
/// of the weights actually PRESENT, so an absent reading is not scored zero.
const String kRecoveryWeightsNote =
    'The bar above them is how much each one counts: heart-rate variability '
    '42%, resting heart 28%, sleep 20%, breathing 10%. Those shares are fixed. '
    'When a reading is missing its share is spread across the others rather '
    'than counted as a zero.';

/// **The four bars are not on one scale**, and nothing else on the card says so.
///
/// Three are z-scores recentred on 50 against the owner's own trailing window
/// (`_personal_factor`: `50 ± k*z`, k = 20 for HRV and RHR, 15 for breathing,
/// over `_BASELINE_DAYS = 42`); the fourth is a plain percentage of stored sleep
/// need (`_sleep_factor`: `100 * tst / need`). Drawn as four identical bars they
/// invite a comparison the arithmetic does not support — the owner asked what
/// they meant, which is the evidence that the drawing alone does not say.
const String kRecoveryScalesNote =
    'They are not on the same scale as each other. Heart-rate variability, '
    'resting heart and breathing are scored against your own trailing 42 days, '
    'where 50 is a normal night for you — one standard deviation away from that '
    'moves the bar about 20 points, or 15 for breathing. Resting heart and '
    'breathing are inverted, so a lower reading draws a higher bar.';

/// The exception, named, with the comparison it makes unsafe.
const String kRecoverySleepScaleNote =
    'Sleep is the exception: a straight percentage of your own sleep need, so '
    '100 means you met it. Sleep 70 and resting heart 70 are therefore not the '
    'same news — one is 70% of the sleep you needed, the other is a night about '
    'a standard deviation better than your usual.';

/// KEPT ON THE CARD, deliberately.
///
/// This is clinical routing, not teaching copy: it tells an owner that a symptom
/// outranks the number they are looking at. The sweep that moved method text off
/// the cards is explicitly not allowed to take a sentence like this with it —
/// deleting one to reduce clutter is the one failure that would make the screen
/// worse rather than tidier.
const String kRecoveryPriorityNote =
    'How you feel and any illness signal take priority.';

/// Whether this factor is the one measured against need rather than a baseline.
///
/// The wire names it `sleep` on `recovery_score.factors`; `factorLabel` renders
/// it `Sleep`. Matched on either, for the same reason `recoveryFactorTone` is.
bool _isSleep(String name) => name.toLowerCase().startsWith('sleep');

/// The family a recovery factor or signal belongs to, from its id or its name.
///
/// It matches on either, because the two carriers of the same four things are
/// named differently on the wire: `recovery_score.factors` is keyed `hrv` /
/// `rhr` / `rr` / `sleep`, and `recovery.signals` names them in words. An
/// unrecognised name takes [Tone.fitness] — the `:root` default — rather than a
/// colour picked to look distinct, because a hue that means nothing is worse
/// than a hue that means "uncategorised".
Tone recoveryFactorTone(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('sleep')) {
    return Tone.sleep;
  }
  if (lower.contains('hrv') || lower.contains('variability')) {
    return Tone.fitness;
  }
  if (lower.contains('heart') || lower.contains('rhr')) {
    return Tone.heart;
  }
  if (lower == 'rr' ||
      lower.contains('breath') ||
      lower.contains('respir') ||
      lower.contains('oxygen') ||
      lower.contains('spo')) {
    return Tone.oxygen;
  }
  return Tone.fitness;
}

/// The recovery model, opened up.
class RecoveryPanel extends StatelessWidget {
  /// [score] is the payload's block; nothing here is computed from raw samples.
  const RecoveryPanel({required this.score, this.onDetails, super.key})
    : overviewDate = null;

  /// Today's stable overnight view; live readiness stays on the detail page.
  const RecoveryPanel.overview({
    required this.score,
    required String date,
    this.onDetails,
    super.key,
  }) : overviewDate = date;

  final String? overviewDate;

  /// The prototype's title for this card.
  static const String title = 'Recovery, explained';

  /// `.weight-stack { margin: 12px 0 }`.
  static const double stackGap = 12;

  /// Between a group's label and the group.
  static const double labelGap = 8;

  /// `.factor-bars { margin-block: 16px }`.
  static const double barsGap = 16;

  /// The model's output and its components.
  final RecoveryScore score;

  /// Opens the recovery detail screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final weighted = <RecoveryFactor>[
      for (final factor in score.factors)
        if (factor.weight != null) factor,
    ];
    return Panel(
      tone: Tone.recovery,
      label: 'Recovery',
      onOpen: overviewDate == null ? null : onDetails,
      head: PanelHead(
        title: overviewDate == null ? title : 'Recovery',
        icon: SolarIconsOutline.heartPulse,
        infoKey: 'recovery_score',
        detail: MetricDetail(
          method: <String>[
            kRecoveryComponentsNote,
            if (overviewDate == null) kRecoveryWeightsNote,
            kRecoveryScalesNote,
            kRecoverySleepScaleNote,
          ],
          notes: <String>[if (score.noteId case final String id) id],
        ),
        actionLabel: onDetails == null || overviewDate != null ? null : 'Details',
        onAction: overviewDate == null ? onDetails : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue('${score.recovery}', unit: '/100', context_: overviewDate == null
              ? _side(score) : 'Overnight estimate'),
          if (overviewDate case final String date)
            PanelNote('For ${score.date ?? date}'),
          if (overviewDate == null && weighted.isNotEmpty) ...<Widget>[
            const SizedBox(height: stackGap),
            const TinyLabel(kRecoveryWeightsLabel),
            const SizedBox(height: labelGap),
            WeightStack(<WeightSegment>[
              for (final factor in weighted)
                WeightSegment(recoveryFactorTone(factor.name), factor.weight!),
            ]),
            const SizedBox(height: stackGap),
            ColourKey(<ColourKeyEntry>[
              for (final factor in weighted)
                ColourKeyEntry(
                  '${factorLabel(factor.name)} ${_share(factor.weight!)}',
                  tone: recoveryFactorTone(factor.name),
                ),
            ]),
          ],
          if (score.factors.isNotEmpty) ...<Widget>[
            const SizedBox(height: barsGap),
            const TinyLabel(kRecoveryScoresLabel),
            const SizedBox(height: labelGap),
            FactorBars(<Factor>[
              for (final factor in score.factors)
                Factor(
                  factorLabel(factor.name),
                  factor.subScore == null ? null : factor.subScore! / 100,
                  tone: recoveryFactorTone(factor.name),
                  reading: factor.subScore?.toString(),
                  // 50 is a normal night for the three personal-baseline
                  // factors (`derive/recovery.py::_personal_factor`, `50 ± k*z`).
                  // Sleep is a percentage of need and has no such midpoint, so
                  // it gets no tick — see `Factor.reference`.
                  // No reading, no reference: a tick on an empty track marks
                  // where a normal night would sit for a night nothing scored,
                  // which reads as a reading that is simply very low.
                  reference: factor.subScore == null || _isSleep(factor.name)
                      ? null
                      : 0.5,
                ),
            ]),
          ],
          if (overviewDate == null && score.guidance != null)
            PanelNote(score.guidance!),
          const PanelNote(kRecoveryPriorityNote),
        ],
      ),
    );
  }

  /// `Overnight estimate` and, when the server sent one, what is left of today.
  static String _side(RecoveryScore score) {
    const overnight = 'Overnight estimate';
    return score.readiness == null
        ? overnight
        : '$overnight\n${score.readiness} / 100 remaining';
  }

  /// `0.4` → `40%`. A weight the server sent as a percentage already is left
  /// alone: anything above 1 is read as one.

  /// A weight as a percentage, whether the wire sent 0.42 or 42.
  static String _share(double weight) =>
      '${(weight <= 1 ? weight * 100 : weight).round()}%';
}
