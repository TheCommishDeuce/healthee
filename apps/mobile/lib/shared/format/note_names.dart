/// The owner-facing name for a research-note id. **Generated — do not hand-edit.**
///
/// Run `python3 tool/gen_note_names.py` from `apps/mobile` after any change to
/// `packages/knowledge`; `test/shared/note_names_test.dart` reads the manifest
/// out of the repo and fails when this file has drifted from it.
///
/// ## Why the app carries the corpus's names at all
///
/// A citation reaches the screen as an id — `/api/today` sends
/// `research_note_ids: ["mvpa_minutes_mortality"]` and nothing else — and an id
/// is an internal identifier. The chips rendered `recovery_readiness` under the
/// gauge and `cardio_load_trimp` on Activity, which is a log line where a source
/// should be.
///
/// The names here are the corpus's own `name` field, transcribed. Two other
/// designs were rejected:
///
///   * **Prettify the id** (`sleep_score_implementation_plan` → "Sleep score
///     implementation plan"). `metric_names.dart` already argues this one down
///     for metric ids: it invents an owner-facing name for something nobody
///     named, and it looks like a name, so nothing about it reads as a gap.
///   * **Have the server send the name.** This is the right long-term fix and it
///     is a wire change, so it belongs in a server PR with a contract snapshot.
///     Until then the app resolves offline, which it must do anyway — the
///     citations are on cached payloads and the phone is often on no network.
///
/// An id with no entry keeps its id (see [noteName]), which is the same stance
/// `metric_names.dart` takes and is now a corpus-ahead-of-app condition rather
/// than a routine one.
///
/// ## Aliases are here because the SERVER cites them
///
/// `/api/today` does not only send note ids. `read/activity.py` cites
/// `cardio_load_trimp` and `read/vo2max.py` cites `vo2max_fitness_mortality`,
/// and neither is a note id — both are **aliases**, of `training_stress_score`
/// and `vo2max` respectively. An ids-only table left those two chips reading as
/// raw snake_case on the Activity screen, which is the defect this file exists
/// to fix, so [kNoteAliases] resolves them.
///
/// Only aliases **shaped like an id** are here (`^[a-z0-9_]+$`) — those are the
/// only ones that can arrive in a `research_notes` array — and any alias claimed
/// by two or more notes is dropped rather than guessed at. `methodology` belongs
/// to seven notes; naming one of them would be picking a source for the reader.
library;

/// The readable source name for [cited], or null when this build cannot resolve
/// it to a note.
///
/// [cited] is whatever the payload carried: a note id, or one of the aliases the
/// server's read layer cites. Null rather than a manufactured phrase — an app
/// older than the corpus should show the id and be visibly behind, not invent a
/// title for a note it does not have. `CitationRow` renders the id then, and
/// logs it.
String? noteName(String cited) => kNoteNames[canonicalNoteId(cited)];

/// The note id [cited] refers to — itself, or the note it is an alias of.
String canonicalNoteId(String cited) =>
    kNoteNames.containsKey(cited) ? cited : (kNoteAliases[cited] ?? cited);

/// Every note in the corpus, id → the corpus's own name.
const Map<String, String> kNoteNames = <String, String>{
  'aerobic_decoupling': 'Aerobic Decoupling & Cardiac Drift',
  'alcohol_sleep': 'Alcohol, sleep architecture, and overnight autonomics',
  'behavior_change_and_personalization': 'Behavior change & personalization (recs design basis)',
  'biological_age_estimate': 'Biological Age (estimate)',
  'cadence': 'Cadence (Step Rate)',
  'cadence_derived_speed': 'Cadence-derived speed as a workload input',
  'cadence_intensity': 'Step cadence as exercise-intensity proxy',
  'caffeine_alcohol_cutoff_plan': 'Personal caffeine/alcohol cutoff-time finder (plan)',
  'caffeine_sleep': 'Caffeine timing and sleep',
  'critical_speed': 'Critical Speed / Critical Power',
  'distance_from_steps': 'Deriving distance from step count',
  'energy_expenditure_derivation': 'Deriving daily energy expenditure (calories)',
  'environmental_stress': 'Heat & Altitude',
  'exercise_mortality': 'Minimum exercise dose and mortality',
  'fasting_metrics': 'Fasting (IF / TRE) and tracked metrics',
  'fitness_fatigue_form': 'Fitness / Fatigue / Form (CTL, ATL, TSB)',
  'fueling_and_hydration': 'Fueling & Hydration',
  'grade_adjusted_pace': 'Grade-Adjusted Pace (GAP)',
  'heart_rate_variability': 'Heart-Rate Variability (HRV)',
  'heart_rate_zones': 'Heart-Rate Training Zones',
  'hr_reserve_vo2max': 'VO₂max from heart-rate reserve (%HRR = %VO₂R)',
  'hydration_8x8_rule': 'The "8 glasses a day" rule',
  'hydration_everyday': 'Everyday hydration (non-exercise)',
  'illness_flag_plan': 'Illness / recovery early-warning flag',
  'individualization': 'Individualization — Training the Runner, Not the Population',
  'injury_prevention': 'Running Injury Prevention',
  'lactate_threshold': 'Lactate Threshold (LT1, LT2, LTHR)',
  'late_eating_sleep': 'Late eating and sleep',
  'llm_health_advice_safety': 'LLM health-advice safety guardrails',
  'load_currency': 'Load Currency — TRIMP vs TSS (why Healthee reasons over one unit)',
  'maximum_heart_rate': 'Maximum Heart Rate (HRmax)',
  'menstrual_cycle_and_training': 'Menstrual Cycle & Training',
  'mindfulness_anxiety_depression': 'Mindfulness meditation for anxiety, depression, and pain',
  'morning_light_circadian': 'Morning bright light & circadian entrainment',
  'mvpa_minutes_mortality': 'MVPA minutes and mortality (150-min target)',
  'mvpa_weekly_plan': 'MVPA derivation & weekly-target plan',
  'napping': 'Daytime napping',
  'napping_chronic_health': 'Is habitual napping healthy?',
  'no_validated_sleep_score': 'No validated composite sleep score',
  'non_exercise_vo2max': 'Non-exercise VO₂max estimate (Jurca 2005)',
  'pace_zones': 'Pace Zones & Threshold Pace',
  'periodization': 'Periodization & Tapering',
  'polarized_training': 'Polarized & Intensity-Distribution Training',
  'progressive_overload': 'Progressive Overload & Adaptation',
  'race_prediction': 'Race-Time Prediction',
  'recommendations_engine_plan': 'Daily AI recommendations engine (implementation plan)',
  'recovery_readiness': 'Daily Recovery / Readiness',
  'respiratory_rate_normal': 'Respiratory Rate (overnight)',
  'resting_heart_rate': 'Resting Heart Rate (RHR)',
  'running_economy': 'Running Economy',
  'running_form_metrics': 'Advanced Form Metrics & Running Power',
  'sauna_cv_benefits': 'Sauna bathing and cardiovascular mortality',
  'sedentary_mortality': 'Sedentary time and mortality',
  'skin_temp_signals': 'Skin Temperature (overnight)',
  'sleep_and_recovery': 'Sleep & Recovery',
  'sleep_consistency': 'Sleep timing consistency (day-to-day variability)',
  'sleep_duration_mortality': 'Sleep duration and all-cause mortality',
  'sleep_health_score_multidim': 'Multi-dimensional sleep-health composites (evidence review)',
  'sleep_need_debt': 'Sleep need & cumulative sleep debt',
  'sleep_regularity_index': 'Sleep Regularity Index (SRI)',
  'sleep_score_implementation_plan': '4-dimension sleep-health score (implementation plan)',
  'sleep_timing_chronotype': 'Sleep timing, chronotype & the lowest-CVD-risk bedtime',
  'slow_breathing_hrv_acute': 'Slow-paced breathing and acute HRV',
  'specificity_and_recovery': 'Specificity & Recovery',
  'steps_mortality': 'Daily steps and mortality',
  'strength_adherence_plan': 'Weekly strength-minutes tally plan',
  'strength_training_for_runners': 'Strength Training for Runners',
  'strength_training_mortality': 'Strength training and mortality',
  'stride_length': 'Stride Length',
  'submaximal_vo2max': 'Submaximal HR-vs-pace VO₂max estimate',
  'training_load_acwr': 'Training Load & Acute:Chronic Workload Ratio (ACWR)',
  'training_stress_score': 'Training Stress Score (TSS) and Session Load Quantification',
  'vo2max': 'VO₂max (Maximal Oxygen Uptake)',
  'wearable_hr_validity': 'Wearable HR (PPG) — validity & limits',
  'wearable_sleep_stage_validity': 'Wearable sleep-stage scoring — validity & limits',
  'wearable_spo2_validity': 'Wearable SpO2 — validity & limits',
  'wearable_stress_validity': 'Wearable stress scores — validity & limits',
  'weight_bmi_body_composition': 'Body weight, BMI, and body composition',
};

/// Id-shaped aliases the corpus declares, → the note they belong to.
///
/// See the library docstring: the server cites some of these directly. Ambiguous
/// aliases are omitted, so a lookup here is never a guess.
const Map<String, String> kNoteAliases = <String, String>{
  '8x8': 'hydration_8x8_rule',
  'acclimatization': 'environmental_stress',
  'acwr': 'training_load_acwr',
  'adiposity': 'weight_bmi_body_composition',
  'alcohol': 'alcohol_sleep',
  'amenorrhea': 'menstrual_cycle_and_training',
  'apmhr': 'maximum_heart_rate',
  'atl': 'fitness_fatigue_form',
  'autonomic': 'respiratory_rate_normal',
  'autoregulation': 'recovery_readiness',
  'bedtime': 'sleep_timing_chronotype',
  'beer': 'alcohol_sleep',
  'biological_age': 'biological_age_estimate',
  'biomechanics': 'running_form_metrics',
  'bmi': 'weight_bmi_body_composition',
  'bonking': 'fueling_and_hydration',
  'booze': 'alcohol_sleep',
  'breathwork': 'slow_breathing_hrv_acute',
  'caffeine': 'caffeine_sleep',
  'cardio_load_trimp': 'training_stress_score',
  'chronotype': 'sleep_timing_chronotype',
  'coffee': 'caffeine_sleep',
  'composite': 'biological_age_estimate',
  'ctl': 'fitness_fatigue_form',
  'decoupling': 'aerobic_decoupling',
  'dehydrated': 'hydration_everyday',
  'dehydration': 'hydration_everyday',
  'deload': 'progressive_overload',
  'detraining': 'specificity_and_recovery',
  'drinking': 'alcohol_sleep',
  'drinks': 'alcohol_sleep',
  'dysmenorrhea': 'menstrual_cycle_and_training',
  'electrolytes': 'fueling_and_hydration',
  'estrogen': 'menstrual_cycle_and_training',
  'euhydration': 'fueling_and_hydration',
  'exercising': 'exercise_mortality',
  'fasting': 'fasting_metrics',
  'fluids': 'hydration_everyday',
  'form': 'fitness_fatigue_form',
  'freshness': 'fitness_fatigue_form',
  'gels': 'fueling_and_hydration',
  'glycogen': 'fueling_and_hydration',
  'guardrails': 'llm_health_advice_safety',
  'hr': 'wearable_hr_validity',
  'hr_zone_minutes': 'heart_rate_zones',
  'hrr': 'heart_rate_zones',
  'hrtss': 'training_stress_score',
  'hrv_improvement': 'heart_rate_variability',
  'hrv_recovery_marker': 'heart_rate_variability',
  'hrv_rmssd_ms': 'heart_rate_variability',
  'hrv_sleep_avg_ms': 'heart_rate_variability',
  'humidity': 'environmental_stress',
  'hunt3': 'non_exercise_vo2max',
  'hydrated': 'hydration_everyday',
  'hydration': 'hydration_everyday',
  'hyponatremia': 'fueling_and_hydration',
  'hypoxia': 'environmental_stress',
  'illness': 'illness_flag_plan',
  'illness_flag': 'illness_flag_plan',
  'jurca': 'non_exercise_vo2max',
  'karvonen': 'heart_rate_zones',
  'longevity': 'biological_age_estimate',
  'lthr': 'heart_rate_zones',
  'macrocycle': 'periodization',
  'meditation': 'mindfulness_anxiety_depression',
  'melatonin': 'morning_light_circadian',
  'mental_health': 'mindfulness_anxiety_depression',
  'mesocycle': 'periodization',
  'mhr': 'maximum_heart_rate',
  'microcycle': 'periodization',
  'mindfulness': 'mindfulness_anxiety_depression',
  'motivational': 'biological_age_estimate',
  'mvpa': 'mvpa_minutes_mortality',
  'nap': 'napping',
  'naps': 'napping',
  'nightcap': 'alcohol_sleep',
  'oestrogen': 'menstrual_cycle_and_training',
  'overload': 'progressive_overload',
  'overstride': 'stride_length',
  'overstriding': 'stride_length',
  'ovulation': 'menstrual_cycle_and_training',
  'peaking': 'periodization',
  'period': 'menstrual_cycle_and_training',
  'periodisation': 'periodization',
  'photoplethysmography': 'wearable_hr_validity',
  'plyometrics': 'strength_training_for_runners',
  'plyos': 'strength_training_for_runners',
  'pmc': 'fitness_fatigue_form',
  'polysomnography': 'wearable_sleep_stage_validity',
  'ppg': 'wearable_hr_validity',
  'progesterone': 'menstrual_cycle_and_training',
  'psg': 'wearable_sleep_stage_validity',
  'readiness': 'recovery_readiness',
  'respiration': 'respiratory_rate_normal',
  'respiratory_rate': 'respiratory_rate_normal',
  'responders': 'individualization',
  'rest': 'sleep_and_recovery',
  'resting_hr_health_marker': 'resting_heart_rate',
  'riegel': 'race_prediction',
  'rtss': 'training_stress_score',
  'sauna': 'sauna_cv_benefits',
  'scale': 'weight_bmi_body_composition',
  'siesta': 'napping',
  'skin_temp_c': 'skin_temp_signals',
  'sleep': 'sleep_and_recovery',
  'sleep_duration': 'sleep_duration_mortality',
  'sleep_stage': 'wearable_sleep_stage_validity',
  'slept': 'sleep_and_recovery',
  'sodium': 'fueling_and_hydration',
  'spo2': 'wearable_spo2_validity',
  'srpe': 'training_stress_score',
  'strain': 'training_stress_score',
  'stress': 'wearable_stress_validity',
  'stride': 'stride_length',
  'sunlight': 'morning_light_circadian',
  'taper': 'periodization',
  'tapering': 'periodization',
  'temp': 'skin_temp_signals',
  'temperature': 'skin_temp_signals',
  'thirst': 'hydration_everyday',
  'trainability': 'individualization',
  'trimp': 'training_stress_score',
  'tsb': 'fitness_fatigue_form',
  'tss': 'training_stress_score',
  'turnover': 'cadence',
  'vagal_tone': 'slow_breathing_hrv_acute',
  'vdot': 'race_prediction',
  'vilpa': 'mvpa_minutes_mortality',
  'vo2max_estimate_plan': 'non_exercise_vo2max',
  'vo2max_fitness_mortality': 'vo2max',
  'vo2max_reserve': 'hr_reserve_vo2max',
  'vo2max_submax': 'submaximal_vo2max',
  'vo2max_training_program': 'vo2max',
  'vo2peak': 'vo2max',
  'water': 'hydration_everyday',
  'wearable_stress_scores': 'wearable_stress_validity',
  'weighing': 'weight_bmi_body_composition',
  'weight': 'weight_bmi_body_composition',
  'weights': 'strength_training_for_runners',
  'wine': 'alcohol_sleep',
};
