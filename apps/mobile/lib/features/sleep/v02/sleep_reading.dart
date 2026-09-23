/// The Sleep screen's opening reading — `.sleep-reading` and its `.colour-key`.
///
/// `design/mobile-preview/sleep-history-view.js`, straight after the header:
///
/// ```js
/// <div class="sleep-reading">
///   <div><p class="small">Time asleep</p>
///        <div class="big-duration">${H.duration(night.duration_min)
///                                    .replace(/([hm])/g,'<small>$1</small>')}</div></div>
///   <div class="sleep-device"><strong>${night.zepp_score ?? '—'}</strong>
///        <span>Amazfit score<br>Device estimate</span></div>
/// </div>
/// <div class="colour-key">
///   <span data-tone="sleep"><i></i>${bedtime} bedtime</span>
///   <span data-tone="movement"><i></i>${wake} wake</span>
///   <span>${H.duration(night.tib_min)} in bed</span>
/// </div>
/// ```
///
/// ```css
/// .sleep-reading             { display:flex; align-items:end;
///                              justify-content:space-between; padding:8px 4px 20px }
/// .sleep-reading .big-duration        { font-size:64px; line-height:1;
///                              font-weight:600; letter-spacing:-3px; margin-top:10px }
/// .sleep-reading .big-duration small  { font-size:22px; font-weight:400;
///                              color:var(--sleep) }
/// .sleep-reading .sleep-device        { border-left:1px solid var(--line);
///                              padding-left:16px; text-align:right }
/// .sleep-device strong       { display:block; font-size:27px; color:var(--sleep) }
/// .sleep-device span         { display:block; font-size:9px; color:var(--muted) }
/// ```
///
/// ## `var(--sleep)`, not a parameter
///
/// The CSS names the sleep family directly on three of these elements. This
/// widget resolves it from an enclosing `ToneScope(tone: Tone.sleep)` instead,
/// which is the same hue and cannot be handed a different one.
///
/// ## The refusals are the point of this block
///
/// Both figures are `Reading`s. A withheld time asleep draws the dash the
/// prototype's own `?? '—'` draws, and the server's reason lands **under this
/// block**, attached to it, naming the field it is about. The `in bed` key is
/// dropped rather than written as `—`: it is one entry of a legend, and a legend
/// entry for a value nobody has is not a smaller truth, it is noise.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/v02/colour_key.dart';

/// What the strap's own number is, said where the number is.
const String kDeviceScoreCaption = 'Amazfit score\nDevice estimate';

/// The night's headline: time asleep, and the strap's own score beside it.
class SleepReading extends StatelessWidget {
  /// [night] is the most recent session on the payload.
  const SleepReading({required this.night, super.key});

  /// The night being read.
  final SleepNight night;

  /// `padding: 8px 4px 20px`.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(4, 8, 4, 20);

  /// `.sleep-device { padding-left:16px }`.
  static const double devicePad = 16;

  /// `.big-duration { margin-top:10px }`.
  static const double figureGap = 10;

  /// The gap between the reading and its key.
  static const double keyGap = 4;

  /// The gap between the key and a refusal note under it.
  static const double noteGap = 10;

  @override
  Widget build(BuildContext context) => ToneScope(
    tone: Tone.sleep,
    child: Builder(builder: _body),
  );

  Widget _body(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: _Asleep(night: night)),
              const SizedBox(width: devicePad),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors.line, width: hairline),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: devicePad),
                  child: _DeviceScore(reading: night.deviceScore),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: keyGap),
        ColourKey(keys(night)),
        if (refusals(night) case final List<String> lines when lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: noteGap),
            child: Text(
              lines.join('\n'),
              style: TypeScale.panelNote.copyWith(color: colors.ink2),
            ),
          ),
      ],
    );
  }

  /// `bedtime`, `wake`, `in bed` — each dropped when it was not recorded.
  static List<ColourKeyEntry> keys(SleepNight night) => <ColourKeyEntry>[
    if (night.start case final DateTime start)
      ColourKeyEntry('${clock(start)} bedtime', tone: Tone.sleep),
    if (night.end case final DateTime end)
      ColourKeyEntry('${clock(end)} wake', tone: Tone.movement),
    if (night.tibMin.valueOrNull case final double minutes)
      ColourKeyEntry.plain('${hoursMinutes(minutes)} in bed'),
  ];

  /// The server's own reason for every field this block could not draw.
  static List<String> refusals(SleepNight night) => <String>[
    for (final field in <String, Reading<double>>{
      'Time asleep': night.tstMin,
      "The strap's sleep score": night.deviceScore,
      'Time in bed': night.tibMin,
    }.entries)
      if (field.value case Withheld<double>(:final disclosure))
        '${field.key}: ${disclosure.message}',
  ];
}

/// `Time asleep` over the big duration, with `h` and `m` in the family.
class _Asleep extends StatelessWidget {
  const _Asleep({required this.night});

  final SleepNight night;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    final narrow = MediaQuery.sizeOf(context).width < SleepType.narrowWidth;
    final figure = narrow ? SleepType.durationNarrow : SleepType.duration;
    final minutes = night.tstMin.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Time asleep',
          style: TypeScale.small.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: SleepReading.figureGap),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: minutes == null
              ? Text('—', style: figure.copyWith(color: colors.ink3))
              : Text.rich(
                  _spans(minutes, figure.copyWith(color: colors.ink), family),
                  maxLines: 1,
                ),
        ),
      ],
    );
  }

  /// `6h 20m` — the digits at figure size, the two letters at 22 in the family.
  static TextSpan _spans(double minutes, TextStyle figure, Color family) {
    final unit = SleepType.durationUnit.copyWith(color: family);
    final whole = minutes.round();
    return TextSpan(
      style: figure,
      children: <InlineSpan>[
        TextSpan(text: '${whole ~/ 60}'),
        TextSpan(text: 'h', style: unit),
        const TextSpan(text: ' '),
        TextSpan(text: (whole % 60).toString().padLeft(2, '0')),
        TextSpan(text: 'm', style: unit),
      ],
    );
  }
}

/// The strap's own score, named as the strap's.
class _DeviceScore extends StatelessWidget {
  const _DeviceScore({required this.reading});

  final Reading<double> reading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = reading.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          score == null ? '—' : score.round().toString(),
          style: SleepType.deviceScore.copyWith(
            color: score == null ? colors.ink3 : context.family,
          ),
        ),
        Text(
          kDeviceScoreCaption,
          textAlign: TextAlign.right,
          style: SleepType.deviceCaption.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}
