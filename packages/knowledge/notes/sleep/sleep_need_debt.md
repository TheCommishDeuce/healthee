---
id: sleep_need_debt
name: "Sleep need & cumulative sleep debt"
topic: Personal sleep need (age-based) and rolling cumulative sleep debt — the evidence-based version of Whoop/Oura "sleep need / debt"
category: sleep
grade: Probable
summary: "Set nightly sleep need from the NSF 2015 age bands (18–64 → 8 h midpoint, 65+ → 7.5 h) and track a rolling 14-night cumulative debt (surplus repays at 0.5×), because sleep restriction's neurobehavioural cost accumulates (Van Dongen 2003) — an evidence-grounded alternative to proprietary 'sleep need/debt', not a composite score."
aliases: ["sleep need", "sleep debt", "sleep deficit", "how much sleep do I need", "sleep target", "cumulative sleep debt", "catch-up sleep", "sleep banking", "recovery sleep", "NSF sleep recommendation", "hours of sleep", "hours slept", "sleep hours", "wiped out", "exhausted", "no energy", "feeling tired"]
applies_to_metrics: ["sleep_need_min", "sleep_debt_min", "tst_min", "sleep_health_score_4dim"]
applies_to_interventions: []
population: general
last_reviewed: 2026-07-15
related: ["sleep_duration_mortality", "sleep_and_recovery", "no_validated_sleep_score", "wearable_sleep_stage_validity", "recovery_readiness", "sleep_health_score_multidim"]
tags: [sleep, circadian, recovery, sleep_need, sleep_debt]
---

# Sleep need & cumulative sleep debt

## Summary

Two related, evidence-grounded quantities. **Sleep need** is the nightly
total-sleep target, anchored on the National Sleep Foundation's 2015 age bands
(adults 18–64 → 7–9 h, older adults 65+ → 7–8 h), set at the band **midpoint**
(8.0 h / 7.5 h) as a defensible default because no validated per-person "need"
estimator exists from wearable data alone. **Sleep debt** is the running shortfall
of actual sleep vs need, tracked as a rolling 14-night cumulative deficit — because
chronic partial restriction accumulates a cognitive cost that grows night over
night with no plateau (Van Dongen 2003). This is explicitly **not** a proprietary
composite: it is arithmetic over one measured quantity (total sleep time) against a
cited target.

## What it is

- **Sleep need** (`sleep_need_min`) — the nightly total-sleep target for the user.
  The National Sleep Foundation's 2015 consensus (panel of 18 experts, 300+ studies
  reviewed) gives age bands: **adults 18–64 → 7–9 h**, **older adults 65+ →
  7–8 h** (younger ages need more). We anchor each person's need at the band
  **midpoint** (8.0 h for 18–64, 7.5 h for 65+) as a defensible default, since no
  validated per-person "need" estimator exists from wearable data alone.
- **Sleep debt** (`sleep_debt_min`) — the running shortfall of actual sleep vs
  need. Chronic partial sleep restriction accumulates a *cumulative* deficit whose
  cognitive cost grows night over night (Van Dongen 2003). We track a **rolling
  14-night cumulative debt**.

Typical: an adult's need sits at 8 h (480 min); a debt of a few hours over two
weeks is common and framed descriptively, not as medical risk.

## Physiology / mechanism

Sleep pressure (homeostatic drive, signalled by adenosine and related molecules)
builds with time awake; lost sleep is only *partially* repaid by later recovery
sleep, and the neurobehavioural deficit of sustained restriction compounds rather
than plateauing (Van Dongen 2003). This is the mechanistic basis for (a) treating
debt as cumulative rather than "just last night" and (b) crediting surplus sleep
only partially — you cannot fully "bank" extra sleep. The health backing for the
*target* itself is the U-shaped duration↔mortality relationship (both short and
long sleep carry elevated risk; see `sleep_duration_mortality`).

## The evidence

- **[Established]** **NSF 2015 age-band targets** — Hirshkowitz et al. (2015),
  *Sleep Health* 1(1):40-43, "National Sleep Foundation's sleep time duration
  recommendations: methodology and results summary." Structured expert consensus
  over 300+ studies. **★★★** for the age-band targets (18–64 → 7–9 h; 65+ →
  7–8 h).
- **[Probable]** **Cumulative-debt model** — Van Dongen, Maislin, Mullington &
  Dinges (2003), *Sleep* 26(2):117-126, "The cumulative cost of additional
  wakefulness: dose-response effects on neurobehavioral functions…" Restricting
  sleep to **6 h/night for 14 nights degraded cognitive performance to a level
  equivalent to 2 nights of total sleep deprivation**, and the deficit **kept
  accumulating without plateau** — the empirical basis for treating debt as
  cumulative, not just "last night." Landmark controlled lab study; replicated by
  Belenky 2003. **★★** (lab cognition endpoints, n small).
- **[Established]** **The health backing for a mid-curve target** — Cappuccio et al.
  (2010), *Sleep* 33(5):585-592, U-shaped duration↔all-cause mortality
  meta-analysis (n ≈ 1.4 M; both < 6 h and > 9 h carry elevated risk). Backs the
  *target* the need is set to. **★★★** (see `sleep_duration_mortality`).

## How we compute it

```
need_min        = age_band_midpoint (e.g. 480 min for 18–64)
nightly_deficit = max(0, need_min − tst_min)        # only shortfalls add debt
sleep_debt_min  = Σ over last 14 nights ( nightly_deficit )
                  − recovery_credit                 # see below
```

Nights **above** need pay debt back (recovery sleep), but physiology only recovers
a fraction of lost sleep per night — we credit surplus at **0.5×** (you don't
fully "bank" extra sleep). **There is NO ceiling on total debt, and there must not be**
(corrected 2026-09-08; this said "cap total debt at a sane ceiling (~ 2 nights' need)
so a long gap doesn't read as an implausible deficit"). `derive/sleep_score.py:239`
returns `max(0.0, shortfall - 0.5 * surplus)` uncapped and its docstring says so on
purpose — *"no artificial cap, so a real chronic deficit shows in full"*. The cap was
uncited, and for a chronic short sleeper it would clip a genuine fortnightly deficit to
two nights' worth: flattery by construction, in the one metric this product exists to be
honest about. "Implausible" was the wrong word for a real number that is merely large.
Here the CODE is right and this note was wrong. This is arithmetic over one
measured quantity (TST) against a cited target — not a proprietary composite (cf.
`no_validated_sleep_score`, `sleep_duration_mortality`).

*What it quantifies:* NSF need is a *recommendation band*, not an effect size. The
7–9 h band is **NSF 2015's**; Cappuccio backs only the U-*shape* around it and states
no reference band of his own (#88, see `sleep_duration_mortality`) — so "the U-curve
supports 7–9 h" is a claim about direction, never about those two numbers. Van Dongen quantifies the
cumulative cost of restriction (6 h × 14 nights ≈ 2 nights of total deprivation,
still accumulating), which is why debt is modelled as cumulative rather than
last-night.

## How the coach uses it

- Compute `sleep_need_min` (age-band midpoint) and `sleep_debt_min` (rolling
  14-night, partial-recovery) as daily derived metrics.
- Surface as: **"Sleep need 8 h · you're 3.2 h in debt over 2 weeks"** with the
  trend, framed **descriptively**. Recommend (not prescribe) catch-up.
- Always show "recommended need — adjust to yours"; let the user override their
  target (a minority are genuine short/long sleepers).
- Evidence label to carry: **★★ moderate** for the debt model; the 7–9 h need band
  is **★★★**.
- Read debt alongside the recovery triangulation (`recovery_readiness`,
  `sleep_and_recovery`) — a rising debt biases the coach toward reducing load, not
  adding it.

## Safety bounds

- "Sleep debt" evidence is for **cognitive/alertness** outcomes, not a direct
  morbidity endpoint — **never imply medical risk from a few hours of debt**.
- Never use sleep-need targeting to justify *restricting* sleep to fit training;
  persistent severe short sleep is a flag to reduce load (see `sleep_and_recovery`).

## Honesty & uncertainty

- Individual sleep need genuinely varies (a minority are short/long sleepers); the
  age-band midpoint is a population default, not a measured personal need. Surface
  it as "recommended", and let the user override their target.
- The **0.5× recovery credit and 14-night window are modeling choices, not
  validated constants** — the literature establishes that debt accumulates and
  that recovery is partial, but not an exact payback coefficient. Keep them in
  flags and label the debt as an estimate.
- "Sleep debt" evidence is for cognitive/alertness outcomes, not a direct
  morbidity endpoint — don't imply medical risk from a few hours of debt.
- Total sleep time itself depends on wearable sleep-staging accuracy
  (`wearable_sleep_stage_validity`); TST is more reliable than per-stage splits.

## Bottom line

**Act on confidently:** the 7–9 h need band (18–64) is well-established; sleep debt
from chronic restriction is real, cumulative, and dose-dependent (Van Dongen 2003).
A run of short nights is accumulating fatigue, not independent events.

**Hold loosely:** the exact per-person need (individual variation); the 0.5×
recovery-credit coefficient and 14-night window (modelling choices); any implied
medical risk from small short-term debt.

## Coach Directives

1. Set `sleep_need_min` from the NSF 2015 age band midpoint (480 min for 18–64,
   450 min for 65+); always label it "recommended — adjust to yours" and allow
   override. *(confidence: high)*
2. Track `sleep_debt_min` as a rolling 14-night cumulative deficit with surplus
   credited at 0.5×; present the trend descriptively, recommend (not prescribe)
   catch-up. *(confidence: moderate)*
3. Treat a run of short nights as **cumulative** fatigue (Van Dongen), not
   independent events. *(confidence: high)*
4. Never imply medical/morbidity risk from a few hours of debt — the evidence is
   for cognitive/alertness outcomes. *(confidence: high)*

## References

- Hirshkowitz M, Whiton K, Albert SM, et al. *National Sleep Foundation's sleep
  time duration recommendations: methodology and results summary.* Sleep Health
  1(1):40-43 (2015).
- Van Dongen HPA, Maislin G, Mullington JM, Dinges DF. *The cumulative cost of
  additional wakefulness: dose-response effects on neurobehavioral functions and
  sleep physiology from chronic sleep restriction and total sleep deprivation.*
  Sleep 26(2):117-126 (2003). https://doi.org/10.1093/sleep/26.2.117
- Cappuccio FP, D'Elia L, Strazzullo P, Miller MA. *Sleep duration and all-cause
  mortality: a systematic review and meta-analysis of prospective studies.* Sleep
  33(5):585-592 (2010). (See `sleep_duration_mortality`.)
- Belenky G, et al. *Patterns of performance degradation and restoration during
  sleep restriction and subsequent recovery: a dose-response study.* J Sleep Res
  12(1):1-12 (2003). (Replication of the cumulative-debt finding.)

## Healthee implementation & honesty policy

- **Derived fields:** `sleep_need_min` and `sleep_debt_min` in `derived_daily`.
  Provenance: `derive/sleep_score.py::derive_sleep_debt`, ported verbatim from
  legacy v2 (science code). Constants: `SLEEP_NEED_MIN_18_64 = 480`,
  `SLEEP_NEED_MIN_65P = 450`, `SLEEP_DEBT_WINDOW = 14`,
  `SLEEP_RECOVERY_CREDIT = 0.5`. Age determined from the profile DOB; need basis
  tagged `NSF2015` in flags.
- **Formula (shipped):** `debt = max(0, Σ max(0, need − tst) − 0.5·Σ max(0, tst −
  need))` over the recorded nights in the trailing 14-day window, reading `tst_min`
  from the `sleep_health_score_4dim` row's flags. The debt flags carry
  `window_nights`, `nights`, `avg_tst_min`, `avg_deficit_min`, `nights_below`, and
  `recovery_credit` so the number is never bare.
- **Deviation from this note's plan (documented):** the note's model caps debt at
  ~2 nights' need; the **shipped derive applies no artificial cap** ("so a real
  chronic deficit shows in full") — an intentional honesty choice for a chronic
  short sleeper. The 0.5× credit and 14-night window are retained as-is.
- **Honesty policy:** `sleep_need_min` is always "recommended, adjust to yours"
  (user-overridable); `sleep_debt_min` is labelled an estimate with its flags
  shown; never framed as medical risk. Not a composite score — arithmetic over one
  measured quantity against a cited target.
- **The debt is dated, and withheld when it is not today's** (2026-07-31). The Today
  card read the newest `sleep_debt_min` row and shipped it with **no date key at all**.
  A debt is a cumulative claim over the 14 nights ending on its own day, so three weeks
  later the stored window and today's share no night whatsoever — it is not "the debt,
  slightly out of date". `read/health_metrics.py::sleep_debt_payload` now carries
  `as_of_date` + `data_confidence`, nulls `debt_min` (and the window breakdown that
  describes the same fortnight) when the row is not the owner's today, and moves the
  value into a `withheld` block naming the reason
  (`derive/sleep_score.py::sleep_debt_unavailable_reason`, which recomputes this
  derivation's own two gates: profile/weight present, ≥1 recorded night in the window).
  `need_min` survives a withhold — the NSF age-band midpoint is a recommendation for
  someone of this owner's age, not a measurement of them.
- **"Last night's sleep" and Sleep Performance % are a SECOND freshness question.**
  `last_tst_min` was the newest `sleep_health_score_4dim` row's TST with the day thrown
  away, and it drove `performance_pct` — so after a week without syncing, a field named
  "last night" and a ratio named "performance" both described a night a week ago. They
  come apart from the debt in both directions (a strap taken off for one night leaves
  the 14-night window intact; a missing profile kills the debt while last night is
  fine), so they are gated separately: `last_tst_as_of_date` + `last_tst_withheld`, and
  `performance_pct` is dropped with the night it was a ratio of.
