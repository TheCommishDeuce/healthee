---
id: mvpa_minutes_mortality
name: "MVPA minutes and mortality (150-min target)"
topic: Moderate-to-vigorous physical activity minutes (MVPA) and the 150 min/week target
category: activity
grade: Established
summary: "Weekly MVPA minutes is one of the most robust modifiable mortality predictors, with a clear dose-response; the WHO target is ≥150–300 min/week moderate OR ≥75–150 vigorous, most of the benefit banked in the first 150; vigorous bouts as short as 1–2 min count, and MVPA captures intensity that raw steps miss."
aliases: ["mvpa", "moderate-to-vigorous physical activity", "150 minutes", "who activity guidelines", "vilpa", "mvpa_minutes_mortality", "walk", "walking"]
tags: ["mvpa", "moderate-to-vigorous physical activity", "150 minutes", "who activity guidelines", "vilpa", "mvpa_minutes_mortality"]
applies_to_metrics: ["moderate_min", "vigorous_min", "mvpa_min", "steps_per_minute"]
applies_to_interventions: ["exercise"]
population: general
last_reviewed: 2026-07-15
related: ["cadence_intensity", "mvpa_weekly_plan", "steps_mortality", "exercise_mortality", "vo2max"]
---

# MVPA minutes and mortality (150-min target)

## Summary

Weekly minutes of **moderate-to-vigorous physical activity (MVPA)** is one of the most
robust modifiable predictors of all-cause and cardiovascular mortality, with a clear
dose-response curve. The WHO 2020 guidelines recommend **≥150–300 min/week of moderate**
OR **≥75–150 min/week of vigorous** activity (or any combination). The lower end of that
band is where most of the mortality benefit is realized; benefit continues to accrue at
higher doses with diminishing returns.

Distinct from total steps in two ways:
1. MVPA is **intensity-anchored** (≥3 METs for moderate, ≥6 METs for vigorous), not
   volume-anchored.
2. **Vigorous bouts as short as 1–2 minutes** independently track lower mortality even
   outside structured exercise [Stamatakis 2022].

## What it is

MVPA is time spent at ≥3 METs (moderate) or ≥6 METs (vigorous). Reported as a **weekly**
total, MET-weighted by the WHO rule that one vigorous minute counts as two moderate
(`moderate + 2 × vigorous`). It is the intensity-aware complement to raw step volume and
the direct target the physical-activity guidelines are written around.

## Physiology / mechanism

Higher-intensity activity drives cardiorespiratory adaptation (stroke volume, capillary
and mitochondrial density) more per minute than low-intensity movement, which is why an
intensity-anchored measure predicts mortality beyond step volume — it captures the
fitness-raising stimulus ([[vo2max]]) that a slow stroll does not. Brief vigorous bursts
(VILPA) are potent because even short near-maximal efforts recruit this adaptive pathway.

## The evidence

- **[Established]** **Dose-response is steepest in the 0 → 150 min/week range**: ~22–31%
  lower all-cause mortality at 150 min/week moderate vs none, ~26–35% at 300 min/week
  (plateau begins) [Garcia et al. 2023, pooled 196 prospective studies].
- **[Established]** **Brief vigorous bouts count**: a median **4.4 min/day of "vigorous
  intermittent lifestyle physical activity" (VILPA)** — non-exercise vigorous bursts —
  was associated with **HR 0.62 (95% CI 0.55–0.71)** for all-cause mortality vs no VILPA;
  even 1–2 minute bouts, not necessarily a structured workout [Stamatakis et al. 2022,
  UK Biobank wearables n = 71,893].
- **[Established]** **8,000 vs 4,000 steps/day → 51% lower mortality, but step intensity
  (cadence) added no independent benefit beyond total MVPA volume** [Saint-Maurice et al.
  2020, NHANES n = 4,840] — so MVPA captures the intensity signal raw steps miss (see
  [[steps_mortality]]).
- **[Established]** The accelerometer-measured MVPA effect **survives reverse-causality
  adjustment** [Strain et al. 2020, UK Biobank].

## How we compute it

MVPA is derived nightly from cadence-classified per-minute steps and reported as a weekly
total (`mvpa_min = moderate_min + 2 × vigorous_min`). **Workouts are not part of it** —
`derive/mvpa.py` reads `steps_per_minute` and nothing else, so cycling, weights and
swimming contribute nothing whether or not they are logged (corrected 2026-09-08; adding
them is planned, and the design is in [[mvpa_weekly_plan]] step 2). The full derivation —
cadence thresholds, debouncing, and the weekly card — is in [[mvpa_weekly_plan]]; the
cadence→intensity method is in [[cadence_intensity]].

## How the coach uses it

- Display **weekly MVPA minutes (moderate + 2×vigorous, WHO MET-equivalent rule) vs a
  150-min target** on the Activity and/or Today page.
- Frame the target as the **lower bound of clinically meaningful**, not a maximum — the
  dose-response continues past 300 min/week with smaller marginal gains.
- **Surface progress weekly, not daily** — single days don't move the mortality math.
- Credit **brief vigorous bursts (VILPA)** — they count even without a workout.
- Cite this note + [[cadence_intensity]] when displaying derived MVPA.

## Safety bounds

- No death-risk number is shown to the user.
- Keep to general encouragement toward the guideline band; do not issue clinical exercise
  prescriptions.

## Honesty & uncertainty

- **Observational.** Reverse-causation bias is reduced by accelerometer cohorts [Strain
  2020] but not eliminated.
- **"Moderate-intensity" is ≥3 METs in research**, but consumer-wearable derivation
  depends on the proxy (HR zones, cadence, or sensor fusion); **cadence-based MVPA is a
  reasonable but imperfect proxy** — see [[cadence_intensity]].
- **WHO's combined-intensity arithmetic ("1 min vigorous = 2 min moderate") is a practical
  simplification, not a precise biological equivalence.**

## Bottom line

**Act on confidently:** MVPA is a strong dose-response mortality marker; aim for the 150
min/week lower bound; brief vigorous bursts count; MVPA captures intensity that steps miss.

**Hold loosely:** the exact MET-equivalence of the 1-vig-=-2-mod rule, the wearable
cadence proxy's accuracy, and any causal magnitude.

## Coach Directives

1. Show **weekly MVPA vs a 150-min lower-bound target**, MET-weighted (`mod + 2×vig`);
   surface weekly, not daily. *(confidence: high)*
2. Frame 150 as a **floor, not a ceiling** — benefit continues past 300 with diminishing
   returns. *(high)*
3. Credit **VILPA / brief vigorous bursts**; they count outside structured exercise.
   *(high)*
4. Label MVPA a **cadence-based estimate** and cite [[cadence_intensity]]; never show a
   death-risk number. *(high)*

## References

- Garcia L, Pearce M, Abbas A, et al. *Non-occupational physical activity and risk of
  cardiovascular disease, cancer and mortality outcomes: a dose-response meta-analysis of
  large prospective studies.* Br J Sports Med 2023;57(15):979–989.
  DOI: 10.1136/bjsports-2022-105669. Pooled 196 prospective studies.
- Bull FC, Al-Ansari SS, Biddle S, et al. *World Health Organization 2020 guidelines on
  physical activity and sedentary behaviour.* Br J Sports Med 2020;54(24):1451–1462. Sets
  the 150-min/week target.
- Stamatakis E, Ahmadi MN, Gill JMR, et al. *Association of wearable device-measured
  vigorous intermittent lifestyle physical activity with mortality.* Nat Med
  2022;28:2521–2529.
- Strain T, Wijndaele K, Sharp SJ, et al. *Impact of follow-up time and analytical
  approaches to account for reverse causality on the association between physical activity
  and health outcomes in UK Biobank.* Int J Epidemiol 2020;49(1):162–172.

## Healthee implementation & honesty policy

- **Metrics: `moderate_min`, `vigorous_min`, `mvpa_min`** (daily), aggregated to a weekly
  MVPA-equivalent (`moderate_min + 2 × vigorous_min`); derived from per-minute
  `steps_per_minute` cadence **only** — logged workouts are not counted today (see
  [[mvpa_weekly_plan]], [[cadence_intensity]]). Only `mvpa_min` is a `derived_daily` row;
  the other two live in its `flags`.
- **Honesty rules**: 150 min/week is a *lower bound*; surface weekly trends, not single
  days; label the number a cadence-based estimate; never a death-risk figure; the
  1-vig-=-2-mod rule is a practical simplification.
