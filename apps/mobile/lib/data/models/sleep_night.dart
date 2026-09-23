/// One night of `/api/sleep` — every field that can be absent, typed as absent.
///
/// `read/sleep_page.py` assembles a night from three sources that fail
/// independently: the strap's own **session** (stage minutes, the hypnogram, the
/// device score), the server's **derived** metrics (the 4-dim score, efficiency,
/// SRI, resting HR, HRV) and the **physiology** averaged over the sleep window
/// (SpO₂, breathing, skin temperature). A night can have any one of the three and
/// not the others, so [SleepGap] is read off which one is missing rather than
/// guessed — see `data/honesty/sleep_gap.dart`.
///
/// **Nothing here is nullable that the screen renders.** Legacy read the same
/// payload as `Map` and printed `—` for every null; every such field is a
/// [Reading] here, so the screen has to decide what an absence looks like and the
/// compiler will not let it forget one.
library;

import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/honesty/sleep_gap.dart';
import 'package:healthee/data/models/last_sleep.dart';
import 'package:meta/meta.dart';

/// The four stage totals of one night, in minutes — or NOTHING, when the strap
/// staged nothing.
///
/// This used to be "always present": the server defaulted the map to zeros rather
/// than nulling it, because `sleep_session`'s four stage columns were `NOT NULL
/// DEFAULT 0` and had no way to say "not measured". So an unstaged night arrived
/// as four honest-looking zeros, [SleepNight.tstMin]'s fallback replaced a correct
/// server withhold with their sum, and the stacked chart painted four zero-height
/// bars — pixel-identical to a night of literal zero sleep.
///
/// Migration `0018` made those columns nullable and `read/sleep_common.py` now
/// sends `null` for the whole map. [SleepNight.stages] is therefore nullable, and
/// the compiler is what makes every screen answer the question rather than
/// summing its way past it.
@immutable
class StageMinutes {
  /// Builds a stage split.
  const StageMinutes({
    required this.deep,
    required this.light,
    required this.rem,
    required this.awake,
  });

  /// Parses `nights[].stages`, or null when the server sent no breakdown.
  ///
  /// Null in, null out — deliberately not a zeroed object. Building one here would
  /// put the defect back one layer up, where it is harder to see.
  static StageMinutes? maybe(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    double minutes(String key) => (raw[key] as num?)?.toDouble() ?? 0;
    return StageMinutes(
      deep: minutes('deep'),
      light: minutes('light'),
      rem: minutes('rem'),
      awake: minutes('awake'),
    );
  }

  /// Deep-sleep minutes.
  final double deep;

  /// Light (the server's `light`, legacy's `Core`) minutes.
  final double light;

  /// REM minutes.
  final double rem;

  /// Awake-in-bed minutes.
  final double awake;

  /// Deep + light + REM + awake. Legacy's `stageTotal`.
  double get total => deep + light + rem + awake;

  /// Whether the strap staged anything at all for this night.
  bool get isEmpty => total == 0;
}

/// One night, as `/api/sleep` sends it.
@immutable
class SleepNight {
  /// Builds a night. Prefer [SleepNight.fromJson].
  const SleepNight({
    required this.date,
    required this.start,
    required this.end,
    required this.deviceScore,
    required this.tstMin,
    required this.tibMin,
    required this.efficiencyPct,
    required this.healthScore,
    required this.pointDuration,
    required this.pointEfficiency,
    required this.pointTiming,
    required this.pointRegularity,
    required this.midpointLocal,
    required this.sri,
    required this.restingHr,
    required this.hrvSleepAvg,
    required this.respiratoryRate,
    required this.spo2Avg,
    required this.spo2Min,
    required this.skinTempC,
    required this.stages,
    required this.timeline,
  });

  /// Parses one entry of `nights[]`.
  factory SleepNight.fromJson(Map<String, Object?> json) {
    final hasSession = json['session_source'] != null || json['start_iso'] != null;
    // Which gap applies is a property of the payload's shape, not a default.
    final derived = hasSession ? SleepGap.notDerived : SleepGap.noSession;
    final sampled = hasSession ? SleepGap.notSampled : SleepGap.noSession;
    double? number(String key) => (json[key] as num?)?.toDouble();
    // SpO₂ and breathing are the server's canonical derived metrics since R9, not
    // a raw average: if the server derived this night (any derived field is here)
    // their absence is a sampling gap; if it derived nothing, it is waiting.
    final derivedAny = <String>[
      'tst_min',
      'score',
      'sri',
      'rhr',
      'hrv_sleep_avg',
    ].any((key) => json[key] != null);
    final vitals = !hasSession
        ? SleepGap.noSession
        : derivedAny
        ? SleepGap.notSampled
        : SleepGap.notDerived;
    Reading<bool> point(String key) {
      final raw = number(key);
      return raw == null ? Withheld<bool>(derived.disclosure) : Present<bool>(raw == 1);
    }

    return SleepNight(
      date: json['date']! as String,
      start: _instant(json['start_iso']),
      end: _instant(json['end_iso']),
      deviceScore: sleepReading(number('zepp_score'), derived),
      tstMin: sleepReading(number('tst_min'), derived),
      tibMin: sleepReading(number('tib_min'), derived),
      efficiencyPct: sleepReading(number('efficiency_pct'), derived),
      healthScore: sleepReading(number('score'), derived),
      pointDuration: point('point_duration'),
      pointEfficiency: point('point_efficiency'),
      pointTiming: point('point_timing'),
      pointRegularity: point('point_regularity'),
      midpointLocal: sleepReading(json['midpoint_local'] as String?, derived),
      sri: sleepReading(number('sri'), derived),
      restingHr: sleepReading(number('rhr'), derived),
      hrvSleepAvg: sleepReading(number('hrv_sleep_avg'), derived),
      respiratoryRate: sleepReading(number('respiratory_rate'), vitals),
      spo2Avg: sleepReading(number('spo2_avg'), vitals),
      spo2Min: sleepReading(number('spo2_min'), vitals),
      skinTempC: sleepReading(number('skin_temp_c'), sampled),
      stages: StageMinutes.maybe(json['stages']),
      timeline: <SleepStageSpan>[
        for (final span in (json['stage_timeline'] as List<Object?>? ?? const <Object?>[]))
          if (span is Map<String, Object?>) SleepStageSpan.fromJson(span),
      ],
    );
  }

  /// The owner-local calendar date the night is filed under, `YYYY-MM-DD`.
  final String date;

  /// When the owner fell asleep, or null when there is no session.
  ///
  /// Not a [Reading]: the clock range is chrome on the page's eyebrow, and a
  /// dashed hole inside a heading would be louder than the fact deserves. The
  /// eyebrow drops the range instead of printing `—`, which is the same honesty
  /// rule expressed as omission.
  final DateTime? start;

  /// When they woke. See [start].
  final DateTime? end;

  /// **The strap's own 0–100 score**, not Healthee's judgement of the night.
  final Reading<double> deviceScore;

  /// Total sleep time, minutes.
  final Reading<double> tstMin;

  /// Time in bed, minutes.
  final Reading<double> tibMin;

  /// Sleep efficiency, percent.
  final Reading<double> efficiencyPct;

  /// The 4-dimension sleep-health count, 0–4. **Never a percentage and never
  /// blended** — see `sleep_health_card.dart`.
  final Reading<double> healthScore;

  /// Did last night clear the 7–9 h duration cutoff?
  final Reading<bool> pointDuration;

  /// Did it clear the ≥85% efficiency cutoff?
  final Reading<bool> pointEfficiency;

  /// Did its midpoint land in the 2–4 am band?
  final Reading<bool> pointTiming;

  /// Did the owner's SRI clear 70?
  final Reading<bool> pointRegularity;

  /// The night's midpoint as the server formatted it.
  final Reading<String> midpointLocal;

  /// Sleep Regularity Index, 0–100.
  final Reading<double> sri;

  /// Resting heart rate for the night, bpm — the server's `rhr_daily`.
  final Reading<double> restingHr;

  /// Mean overnight RMSSD, ms.
  final Reading<double> hrvSleepAvg;

  /// Mean breaths per minute across the sleep window.
  final Reading<double> respiratoryRate;

  /// Mean SpO₂ across the window, percent.
  final Reading<double> spo2Avg;

  /// The lowest SpO₂ sample in the window, percent.
  final Reading<double> spo2Min;

  /// Mean skin temperature across the window, °C.
  final Reading<double> skinTempC;

  /// The night's stage totals, or null when the strap staged nothing.
  ///
  /// Nullable on purpose and the nullability is the fix: see [StageMinutes]. A
  /// screen that wants a number out of this has to say what it draws when there
  /// is no breakdown, and cannot reach a zero by accident.
  final StageMinutes? stages;

  /// The hypnogram, in order.
  final List<SleepStageSpan> timeline;

  static DateTime? _instant(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}
