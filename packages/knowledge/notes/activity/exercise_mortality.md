---
id: exercise_mortality
name: "Minimum exercise dose and mortality"
topic: Even 15 minutes of moderate daily exercise tracks with lower all-cause mortality
category: activity
grade: Established
summary: "As little as ~15 min/day (~90 min/week) of moderate activity is associated with meaningfully lower all-cause mortality vs inactivity; benefit keeps accruing with diminishing returns above ~300 min/week moderate (or ~150 vigorous), and resistance training adds benefit beyond aerobic work."
aliases: ["exercise mortality", "minimum exercise", "15 minutes exercise", "physical activity mortality", "exercise_mortality", "exercising", "working out", "exercise more", "working out more"]
tags: ["exercise mortality", "minimum exercise", "15 minutes exercise", "physical activity mortality", "exercise_mortality"]
applies_to_metrics: ["steps_total", "mvpa_min"]
applies_to_interventions: ["exercise"]
population: general
last_reviewed: 2026-07-15
related: ["mvpa_minutes_mortality", "steps_mortality", "sedentary_mortality", "strength_training_mortality"]
---

# Minimum exercise dose and mortality

## Summary

Compared with inactivity, **as little as 15 minutes per day** (or ~90 min/week) of
moderate-intensity physical activity is associated with a meaningful reduction in
all-cause mortality. Benefits continue to accrue with more activity, with **diminishing
returns above ~300 min/week of moderate or ~150 min/week of vigorous** activity.
**Resistance training adds additional benefit beyond aerobic activity** (see
[[strength_training_mortality]]).

The practical headline: the first 15–60 min/day is where most of the benefit lives — the
biggest step is from *zero* to *some*.

## What it is

This note is about the **minimum effective dose** of exercise for longevity, framed in
weekly minutes of moderate-to-vigorous activity. It complements the volume view
([[steps_mortality]]) and the intensity-anchored target ([[mvpa_minutes_mortality]]): here
the emphasis is that even a small, sub-guideline dose beats inactivity.

## Physiology / mechanism

Regular moderate activity improves cardiorespiratory fitness, endothelial function,
insulin sensitivity, blood pressure and lipid profile — the same pathways that make CRF
the strongest modifiable mortality marker ([[vo2max]]). The steep early part of the
dose-response curve reflects that the metabolically inactive body gains the most from the
first regular stimulus; the flattening at high volumes reflects saturating adaptation.

## The evidence

- **[Established]** **15 min/day moderate vs inactive ≈ 14% lower all-cause mortality
  (HR ≈ 0.86, 95% CI 0.81–0.91)** [Wen et al. 2011, Taiwan cohort, n ≈ 416,175].
- **[Established]** **150–300 min/week moderate vs none ≈ 25–30% reduction** [Ekelund et
  al. 2019].
- **[Established]** **Resistance training 1–2×/week is independently associated with
  ~10–17% lower all-cause mortality** [Saeidifard et al. 2019] — additive to aerobic
  activity (see [[strength_training_mortality]]).

## How we compute it

No mortality number is derived. Logged exercise and derived MVPA (`mvpa_min`) plus steps
(`steps_total`) are the inputs; the evidence is used to *affirm* activity and set the
"even a little counts" framing, not to compute a personal risk.

## How the coach uses it

- **Affirm any logged exercise as net-positive** without quantifying mortality to the user.
- Don't push toward extreme volumes — **most of the benefit is in the first 15–60
  min/day**, and returns diminish above the guideline band.
- Encourage adding **resistance training** for the additive benefit
  ([[strength_training_mortality]]).
- Cite this note when discussing weekly activity patterns.

## Safety bounds

- No death-risk number is shown to the user.
- Do not prescribe specific clinical exercise doses; keep to general encouragement and the
  guideline reference bands.

## Honesty & uncertainty

- **Observational**, with self-selection — healthier people exercise more.
- **"Moderate intensity" definitions vary**; in accelerometer studies it usually means
  **≥3 METs**.
- The **benefit curve flattens**: doubling weekly exercise from 150 to 300 min/week yields
  a *small* additional reduction, not a doubled one — never imply linear "more = double".

## Bottom line

**Act on confidently:** even ~15 min/day of moderate activity is associated with
meaningfully lower mortality vs inactivity; the first hour/day matters most; resistance training adds benefit.

**Hold loosely:** exact dose-response magnitudes for an individual, and causality (all
observational).

## Coach Directives

1. **Affirm any logged exercise** as net-positive; never quantify mortality to the user.
   *(confidence: high)*
2. Emphasise that **even 15 min/day counts** and that the first 15–60 min/day carries most
   of the benefit; don't push extreme volumes. *(high)*
3. Encourage **resistance training** for its additive benefit. *(high)*

## References

- Wen CP, Wai JPM, Tsai MK, et al. *Minimum amount of physical activity for reduced
  mortality and extended life expectancy: a prospective cohort study.* The Lancet
  2011;378(9798):1244–1253. Taiwan cohort, n ≈ 416,175.
- Ekelund U, Steene-Johannessen J, Brown WJ, et al. *Dose-response associations between
  accelerometry measured physical activity and sedentary time and all cause mortality:
  systematic review and harmonised meta-analysis.* BMJ 2019;366:l4570.
- Saeidifard F, Medina-Inojosa JR, West CP, et al. *The association of resistance training
  with mortality: A systematic review and meta-analysis.* Eur J Prev Cardiol
  2019;26(15):1647–1665.

## Healthee implementation & honesty policy

- **No mortality metric**: this note backs `mvpa_min` and `steps_total` interpretation and
  the "even a little counts" framing.
- **Honesty rules**: affirm activity, never quantify death risk; state that returns
  diminish above the guideline band (no linear "more = proportionally better"); route
  strength framing to [[strength_training_mortality]]. Cite when discussing weekly
  activity.
