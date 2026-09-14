---
id: recovery_readiness
name: "Daily Recovery / Readiness"
topic: Daily recovery / readiness from wearable autonomic + sleep markers
category: recovery
grade: Probable
summary: "No peer-reviewed formula combines HRV+RHR+sleep into one recovery number, so recovery_score ships as a transparent 0-100 evidence-weighted estimate ALWAYS shown with its per-factor breakdown; triangulate ≥3 inputs, let no single input decide, and never let a green score clear a fatigued or ill user."
aliases: ["readiness", "readiness score", "daily readiness", "training readiness", "recovery score", "recovery status", "body battery", "go no-go", "green light", "autoregulation", "morning check-in", "wellness check", "am I ready to train", "recovery", "recovery_readiness", "wiped out", "exhausted", "no energy", "feeling tired", "push hard", "take it easy", "train hard", "should i train today"]
tags: ["readiness", "readiness score", "daily readiness", "training readiness", "recovery score", "recovery status", "body battery", "go no-go", "green light", "autoregulation", "morning check-in", "wellness check", "am I ready to train", "recovery", "recovery_readiness"]
applies_to_metrics: ["recovery_score"]
applies_to_interventions: []
population: general
last_reviewed: 2026-07-15
related: ["heart_rate_variability", "resting-heart-rate", "sleep_and_recovery", "training-load-acwr", "fitness-fatigue-form"]
---

# Daily Recovery / Readiness

## Summary
Recovery (a.k.a. readiness, recovery status, body battery) is a **daily, morning-facing
estimate of how recovered the body is** — a triangulated read of overnight autonomic and
sleep markers. The single most important fact is honest and load-bearing: **there is NO
peer-reviewed, validated formula that combines HRV + RHR + sleep into one "recovery"
number.** Whoop / Oura / Garmin / Polar scores are proprietary black boxes — their input
*signals* (HRV, RHR, sleep) are validated, but the *composite output and weighting* are
not independently validated as predictors. The individual markers are well-evidenced;
combining them is an **informed estimate, not a clinical truth**. So Healthee ships
`recovery_score` as a **0–100 estimate ALWAYS shown with its per-factor breakdown** —
never a bare number — the documented, user-approved exception to the no-composite rule
(published per-marker science + transparent weighting + a visible breakdown, the same bar
cleared for biological-age; see `no_validated_sleep_score`). The governing coaching
principle, well-supported (Established) by the overtraining-monitoring consensus, is
**triangulation: read ≥3 inputs together, let no single input be decisive, and treat
concordance as confidence** — and **subjective wellness is at least as sensitive as the
sensors**, so a cheap morning self-report is a first-class signal, not a poor substitute.
Readiness answers one narrow question — *"is today a good day to deliver a hard stimulus?"*
— and is a **suggestion the user can override, never a verdict**.

## What it is
"Recovery / readiness" is a *derived* construct: it has no ground truth of its own, only
the ground truths of its inputs. It is expressed as a **0–100 index** (Healthee's
`recovery_score`) or, equivalently, as a three-way **go / modify / rest** band. It answers
*"is today a good day to deliver the planned hard stimulus?"* — and **not** "how fit am I",
"will I get injured", or "am I overtrained". It is an **autoregulation** tool that times
intensity within a plan; it does not set the plan.

The inputs, each read as a *deviation vs the person's own baseline* (never an absolute):

| Component | What it contributes | Owning note |
|---|---|---|
| **Overnight HRV** (lnRMSSD) | Autonomic (parasympathetic) recovery vs personal baseline | `heart_rate_variability` |
| **Resting HR** | Coarse autonomic / illness / fatigue signal vs baseline | `resting-heart-rate` |
| **Sleep** (TST vs physiological NEED) | The largest single recovery lever | `sleep_and_recovery` |
| **Respiratory rate** | Early illness / strain signal vs baseline | `respiratory_rate_normal` |
| **Prior-day load** (strain / TRIMP) | The demand being absorbed (feeds intraday decay) | `training-load-acwr`, `fitness-fatigue-form` |
| **Subjective wellness** | Fatigue, soreness, stress, mood — cheap and often *earliest* | `sleep_and_recovery` (Hooper-style) |

Typical operating bands (starting defaults, individualised over time):
- **Go / green** — components at or above baseline; proceed with the planned quality.
- **Modify / amber** — one or more components meaningfully off-baseline, or mixed signals;
  soften or shift intensity but keep the session.
- **Rest / red** — multiple concordant negatives, or a single safety-critical input
  (illness, acute sleep deprivation, pain); reduce to easy or rest.

## Physiology / mechanism
There is no single "readiness organ"; the construct works only because its components each
track a real, partly **independent** strand of recovery:

- **Overnight is the correct window.** Parasympathetic (vagal) reactivation dominates
  at-rest cardiac control during sleep, so overnight HRV/RHR index recovery state far
  better than daytime spot readings [Stanley 2013 (parasympathetic reactivation review);
  Michael 2017 (early HR recovery is parasympathetic)]. Recovery is therefore **set at
  wake and does not rise during the day** — what changes through the day is strain
  *consuming* the morning's capacity.
- **HRV** indexes cardiac **parasympathetic (vagal)** reactivation — fast, beat-to-beat
  autonomic recovery (see `heart_rate_variability`).
- **RHR** reflects intrinsic sinoatrial rate plus autonomic tone and rises with systemic
  stress, inflammation and incipient illness — a slower, coarser read partly **decoupled**
  from HRV.
- **Sleep** is the master restorative process (GH-driven tissue repair, glycogen
  resynthesis, CNS and immune restoration); sleep loss degrades skill, reaction time and
  perceived effort *before* gross force (see `sleep_and_recovery`).
- **Prior load** is the demand side — the fitness–fatigue balance and recent ramp set how
  much residual fatigue is being cleared.
- **Subjective wellness** integrates what the sensors miss — psychological/life stress,
  soreness, motivation, illness prodrome — through the person's own perception, which is
  why it is often the **first** thing to move.

The mechanistic case for *combining* them is that each captures a different failure mode
and any one can be fooled. The classic trap is the **overreaching paradox**: vagal HRV
markers can *rise* paradoxically in functionally overreached athletes, and post-exercise
HRV increases in both good adaptation and overreaching — so HRV alone "cannot independently
distinguish positive from negative adaptations" [Bellenger 2016]. A composite covers that
blind spot: an HRV that looks fine is contradicted by rising RHR, poor sleep, a load spike
and heavy-legged wellness. **Concordance is the signal; a lone outlier is usually noise.**

## The evidence
Recovery/readiness sits on two evidence layers: (1) **strong** evidence for the *principle*
of multi-marker triangulation and for each component's validity, and (2) **thin, unsettled**
evidence for any *specific composite score* as a validated predictor.

### The principle: triangulate; no single number
- **[Established]** No single marker diagnoses recovery/overtraining; integrated,
  multi-parameter monitoring is the consensus standard — *joint ECSS/ACSM consensus
  statement*: overtraining diagnosis "requires exclusion of other causes" and a combination
  of markers, and no individual physiological/biochemical variable is pathognomonic
  [Meeusen 2013]. HR-based monitoring reviews agree: resting/submaximal HR and HRV each add
  partial information and must be read with load and wellness, not in isolation
  [Buchheit 2014].
- **[Established]** **Subjective self-report is at least as sensitive as objective markers**
  — *systematic review of 56 studies* [Saw 2016, BJSM]. Subjective and objective measures
  generally **did not correlate**, yet subjective well-being tracked acute and chronic load
  with *superior* sensitivity: it declined with acute load increases and chronic loading and
  improved with load reduction. The cheap 1–5 morning check-in is a first-class, often
  *earlier* signal, not a poor substitute for sensors.
- **[Probable]** A simple composite **subjective** index tracks staleness/overtraining and
  can outperform biochemical markers — *seminal prospective cohort, 14 elite swimmers over a
  6-month season* [Hooper 1995]. The self-reported "Hooper index" (fatigue, stress, sleep,
  muscle soreness) predicted staleness, accounting for **~76% of variance** (rising to ~85%
  with resting catecholamines), and self-report was judged *more* sensitive than the
  physiological/biochemical measures. Small, single-sport and dated, but directionally
  consistent with [Saw 2016].
- **[Probable]** Readiness-style autoregulation (timing hard sessions by a recovery signal)
  modestly beats fixed plans. The closest trial body is **HRV-guided training**: a
  meta-analysis of 6 RCTs (195 endurance athletes) found a larger pooled fitness effect for
  HRV-guided than predefined training (SMD ≈ 0.40 vs 0.22), strongest in amateurs
  [Granero-Gallegos 2020], though a stricter meta-analysis found VO₂max/endurance effects
  trivial and non-significant [Manresa-Rocamora 2021]. This validates the *autoregulation
  behaviour* (don't prescribe intensity on a bad day), not any particular composite formula.

### The components are individually valid (the inputs are real)
- **[Established]** The underlying signals are measurable on consumer wearables: overnight
  **RHR** agrees near-perfectly with ECG (CCC 0.91–0.98 across Oura/WHOOP; Oura MAPE
  ~1.7–1.9%) and **HRV (RMSSD)** agrees well though more loosely (CCC 0.82–0.99; MAPE ~6–8%)
  — *device-validation vs Polar H10 / ECG* [Dial 2025; Bellenger 2021].
- **[Established]** Each marker carries its own outcome evidence: HRV-guided training
  improves vagal markers (SMD ≈ 0.50, sig) while its **VO₂max effect is NS (0.13)** — HRV
  reflects autonomic *state*, not performance [Manresa-Rocamora 2021; Plews 2013;
  Buchheit 2014]; **+10 bpm resting HR → RR 1.17 all-cause mortality** in a meta-analysis of
  ~1.2M people, and acute RHR elevation tracks fatigue/illness [Aune 2017]; **short sleep
  raises mortality** and sleep is restorative [Cappuccio 2010]; **elevated overnight
  respiratory rate is an early illness/strain signal** [Smarr 2020; Quer 2021].

### The composite *score* itself is unsettled
- **[Emerging / Contested]** **No specific readiness/recovery composite is independently
  validated as a predictor.** Commercial scores (WHOOP Recovery, Oura Readiness, Garmin Body
  Battery / Firstbeat) are **proprietary black boxes**: the component signals are validated
  [Bellenger 2021; Dial 2025], but the **weighting and composite output** are not
  transparently published or independently validated for decision accuracy. The WHOOP
  validation that exists covers *sensor accuracy*, not the recovery percentage's predictive
  value [Bellenger 2021]. Treat any single recovery number — Healthee's included — as a
  **low-precision summary**, not a measured quantity.
- **[Emerging]** Multivariate/ML models fusing training, sleep, HRV and subjective wellness
  to predict next-day recovery outperform single inputs in-sample but are early,
  dataset-specific and not yet cross-validated into deployable, generalising rules.
- **[Probable]** **How readiness is *delivered* changes whether it helps.** Imposed,
  controlled self-monitoring can backfire: athletes who self-reported because they were
  *instructed to* (rather than autonomously) were **less responsive**, with preliminary signs
  of reduced intrinsic motivation [Saw 2015] — the empirical basis for keeping readiness
  **opt-in and overridable**. This parallels "orthosomnia," where anxious chasing of device
  scores worsens the very thing measured (see `sleep_and_recovery`).

**Consistency verdict:** the *principle* (triangulate; no single number; subjective counts)
is **consistent and well-supported**; any *specific composite score or threshold* is
**unsettled** — plausible and component-valid, but not proven as a predictor or shown in an
RCT to beat reading its parts.

## How we compute it
Healthee computes `recovery_score` **transparently from its own component metrics** — every
read decomposes back to the inputs that drove it. The **shipped morning score** combines
four overnight sensor factors, evidence-weighted; the fuller triangulation model below
(adding prior load and subjective wellness) is the coaching stance and the design direction.

**Shipped `recovery_score` (0–100, set at wake) — `derive/recovery.py`:**

| Factor | Direction | Grade | Weight |
|---|---|---|---|
| Overnight **HRV** (`hrv_sleep_avg`) vs personal baseline | higher = better | ★★★ marker / ★★ as readiness | **0.42** |
| **Resting HR** (`rhr_daily`) vs personal baseline | lower = better | ★★★ | **0.28** |
| **Sleep** (TST vs physiological NEED) | more = better | ★★★ marker | **0.20** |
| **Respiratory rate** (`respiratory_rate_sleep`) vs baseline | lower = better | ★★ | **0.10** |
| Skin-temp deviation | elevation = worse | ★★ | *excluded — not in daily derived store* |
| Prior-day strain (TRIMP) | — | ★★ | *intraday decay only (below)* |

- **Weights are assigned by evidence strength, not fitted**, and **renormalized over
  whatever factors exist** for the night. The score is `None` (undefined, not zero) unless at
  least one autonomic marker (HRV or RHR) is present.
- **Normalization (the key methodological point): personal smoothed baseline + smallest-
  worthwhile-change, NOT population norms** [Plews 2013; Buchheit 2014]. HRV/RHR/RR are scored
  as a **robust z vs the person's own trailing ~6-week (42-day) median (MAD-based SD)** — the
  reference adapts to the individual. This is what makes it valid for a chronic ~4 h sleeper:
  their *autonomic* baseline is their own, while **sleep is held to the ABSOLUTE need** (you
  can't out-baseline the need), so the score stays physiologically honest about
  under-recovery [Cappuccio 2010].
- **Per-factor breakdown always rides in the payload** (each factor's sub-score, z, value,
  baseline, and the weights) so the UI/LLM never show a bare number.

**Live readiness (intraday decay) — app-side, design intent, self-labelled unvalidated:**
recovery is the morning value; what changes through the day is **strain consuming capacity**.
There is **no validated intraday "battery" formula** (Garmin Body Battery / Firstbeat is
proprietary), so it is modelled transparently and conservatively:

```
readiness(t) = recovery × (1 − 0.5 · min(1, strain_today / typical_daily_strain))
```

where `strain_today` = Banister-TRIMP cardio-load accrued so far and `typical_daily_strain`
= the personal 30-day median. A full typical day's strain trims readiness by **≤ 50%**, and
it is always shown as e.g. *"recovery 72 → 58 (−14 today's load)"*. Framed as an estimate.

**Triangulation / coaching layer (design intent, not the shipped number):** the fuller
model adds **prior load** (weekly ramp / hedged EWMA-ACWR / form) and a **subjective
morning check-in** (a Hooper-style 1–5 self-report of fatigue/soreness/stress/mood
[Hooper 1995; Saw 2016]). Composition rules:
- Each component maps to a contribution ∈ {negative, neutral, positive}, gated by its own
  smallest-worthwhile-change band so within-noise readings count as neutral.
- **No single component can force "go".** A clean HRV cannot upgrade a day that sleep, load
  or wellness drag down.
- **Safety-critical inputs can unilaterally force "rest/modify"** (illness signs, acute
  sleep deprivation, reported pain) — guardrails, not votes. Only the illness limb has
  code behind it; the other two are coach rules (see *Safety bounds*, #87).
- **Concordance scales confidence:** ≥3 inputs agreeing → high-confidence band and firmer
  language; mixed/conflicting → low-confidence, defer to the user.
- Weights start from the fixed evidence-strength defaults above; individualising them from
  the person's own history (which signal best predicts *their* good/bad days) is an
  Emerging direction, not yet shipped (see `individualization`).

**Estimation-error flags:** the score inherits *every* input's noise and confounds (alcohol,
caffeine, heat, menstrual-cycle phase, travel, psychological stress,
device/protocol drift, and ACWR's instability at low chronic load). It is undefined or
low-confidence until each component has enough history (≈2–3 weeks for HRV/RHR baselines;
≥28 days before ACWR contributes). A single day is never decisive; the unit of action is the
**multi-day trend**.

## How the coach uses it
Core stance: **recovery is an opt-in suggestion that opens a conversation; the user can
always override it.** Surface *why* (which components moved), propose a modification, and let
the person decide — never a bare verdict or a silent plan rewrite, and **always show the
components**.

- **Go (concordant positives / all near baseline):** green-light the planned quality; speak
  plainly ("everything looks recovered — good day for the intervals").
- **Modify (mixed or one meaningful negative):** keep the session but soften it — cut reps,
  drop to the easier end of the range, or swap order; hedge the language ("HRV and sleep are
  a bit down — let's trim the session and see how you feel in the warm-up").
- **Rest / easy (multiple concordant negatives):** convert to easy aerobic or rest and say
  which signals drove it; a persistent multi-day decline across HRV + RHR + sleep + wellness
  is the strongest non-safety signal to back off.
- **Conflict → defer to the person.** When signals disagree (great HRV, terrible sleep; or
  clean sensors, heavy legs), confidence is low — present both, weight the **subjective
  report and any pain highest** [Saw 2016], and let them choose.
- **On a low-recovery morning, name the likely confounder** — but only a confounder this
  product can actually observe or the person has actually reported (a logged drink the
  night before, a logged illness flag, reported travel or heat), rather than alarming on
  the number. Do **not** offer a late meal as the explanation: see *Honesty & uncertainty*.

By **stage**:
- **Stage 1 (beginner):** educational, not directive. Baselines aren't formed, ACWR is
  meaningless and device noise is alarming; lean on **sleep and a simple subjective
  check-in**; use recovery to *teach* the concept. After a bad night, keep the session easy
  and short rather than skipping — protect the habit.
- **Stage 2 (developing):** begin light autoregulation — let a **persistent, concordant**
  dip (≥2 inputs) shift or soften the next quality session; the autoregulation benefit is
  clearest here, especially for non-elites [Granero-Gallegos 2020].
- **Stage 3 (racing/advanced):** full readiness-guided timing of hard blocks against stable
  baselines, read **through the plan's intent** (a taper lowers load by design; an overload
  block elevates fatigue by design). Never let a single green day clear a runner reporting
  rising fatigue, and never let one red day derail a well-judged plan.

## Safety bounds
Recovery is **not** a clinical tool and its *score* is not a guardrail, but it **routes**
several safety-critical inputs that are hard bounds in their own notes. These **override**
any "go" the composite would otherwise give. **Two of the four have real code behind
them and two do not** — the per-bullet ledger at the end of this section says which,
because "mirrored in code" was written here as a blanket claim and it was not true
(#87, 2026-08-01).

- **Illness rule (hard; partly enforced — see the ledger below):** RHR sustained above
  baseline *with* illness symptoms
  (fever, sore throat, body aches, malaise) → do **not** prescribe hard/intense training;
  advise rest. Training intensely through febrile illness carries cardiac risk (myocarditis).
  Cannot be overridden by a green score [see `resting-heart-rate`]. Elevated
  overnight RR **plus** temperature is surfaced as a **"possible early signal," never a
  diagnosis** [Smarr 2020; Quer 2021].
- **Acute sleep deprivation (hard; NOT enforced — see the ledger below):** acute
  deprivation (e.g. <~4–5 h, or a string
  of sub-6-h nights) caps prescribed intensity/load regardless of other inputs — no PRs, max
  efforts, or load jumps; default easy/short or rest [see `sleep_and_recovery`].
- **Pain / injury (hard override):** any reported pain, injury, or red-flag wellness signal
  overrides every "safe"/"go" reading [see `training-load-acwr`].
- **Clinical red flags (refer out):** syncope, chest pain, unexplained breathlessness,
  symptomatic bradycardia — route to medical advice; never reassure cardiac symptoms.
- Otherwise recovery-driven *easing* is conservative and low-risk. Recovery must **never** be
  used to *escalate* training on its own.

**What is actually enforced (#87, verified against the tree 2026-08-01).** This section
opened by calling all four bounds "mirrored in code", and D7 said they "cannot be
overridden by the AI or the score". Half of that is true and half is not:

- **Illness — GENUINELY ENFORCED, on two deterministic paths, but not on the coach's
  prose and not on the trigger this note describes.** `derive/illness.py` writes an
  `illness_flag` per owner per day from overnight respiratory rate + skin temperature
  (never from symptoms — Healthee collects none, so the note's "RHR + fever/sore
  throat/malaise" trigger is not the one implemented). While a flag is active,
  `read/recovery_guidance.py` **replaces the band's guidance sentence entirely**, so a
  green score cannot render "good day to push"; and `challenges/recovery_guard.py`
  refuses to offer or raise a hard training lever (`mvpa_min`, `cardio_load`,
  `workouts_week`). Those two are real overrides that neither the score nor the user can
  argue with. **No output rule keys on illness**, so the sentence "cannot be overridden
  by the AI" is not true of the conversational coach.
- **Acute sleep deprivation — NOT ENFORCED as a cap.** Nothing caps prescribed
  intensity after a short night. `insights/output_guard.py`'s `advise_sleep_restriction`
  is a different rule pointing the other way: it blocks the coach *advising you to cut
  sleep*, not training after you did. The only indirect path is that sleep carries 0.20
  weight in `recovery_score`, and a `low` trailing-week band triggers
  `challenges/recovery_guard.py` — a composite effect, not this bound.
- **Pain / injury — NOT ENFORCED as stated.** Nothing in the tree records reported pain,
  so "any reported pain overrides every go reading" has no input. Two narrower rules are
  real: `output_guard.py` blocks an answer that advises training through a red-flag
  symptom (chest pain, syncope, palpitations, dizziness, breathlessness) or through
  suspected bone stress / RED-S.
- **Clinical red flags (refer out) — ENFORCED, and strongly.** `insights/refusals.py`
  classifies the question *before the model runs* and returns a fixed emergency response
  for chest pain, chest tightness, fainting, loss of consciousness, "can't breathe" and
  the stroke set; the model never sees it, so it cannot be prompted past.
  `output_guard.py`'s `advise_through_red_flag_symptom` catches the answer-side case.

**Mechanically, why none of this is compiled from this note:** only directives a note
declares `safety_critical` in its frontmatter compile into
`insights/guard_directives.py`, with a test asserting a rule exists per marker. **This
note declares none.** Everything enforced above is hand-compiled elsewhere or lives in
the derive/read/challenges layers; nothing fails the build if it disappears. D7 is a
strong candidate for the `safety_critical` mechanism.

## Honesty & uncertainty
- **The composite number is the weakest part.** The triangulation *principle* is strong; the
  specific *score and weighting* are not validated. No RCT shows a composite recovery score
  improves performance or reduces injury **better than its components**. Healthee keeps the
  score transparent and hedged for exactly this reason, and always renders the per-factor
  breakdown + citations — **never a bare number**.
- **Do not claim it predicts performance** — the meta-analytic VO₂max effect of the strongest
  input (HRV-guidance) was non-significant [Manresa-Rocamora 2021]; recovery reflects
  autonomic *state*, not fitness or a race result.
- **Garbage in, garbage out — multiplied.** Recovery inherits every confounder of every
  input (alcohol, caffeine, heat, dehydration, illness, psychological/life stress,
  menstrual-cycle phase, travel/jet-lag, device/protocol drift). A "low recovery" morning is
  frequently a night with a drink in it, not a training signal [see `alcohol_sleep`].
- **"Late meals" used to be on that list, and it is now off it (#92, 2026-08-01).** This
  note listed late eating among the confounders of a low-recovery morning here and in
  Directive D10, **with no citation**. [[late_eating_sleep]] searched specifically for a
  primary source linking late eating to overnight HRV or resting heart rate and found none
  it could verify; a second search for this fix found none either. What exists is adjacent
  and does not support the claim: Uçar 2021 measured HRV after two *different late* meals
  (easily- vs slowly-digestible, both at 22:00, n = 16) and so never tested late-vs-early;
  the meal-timing/HRV-circadian work is about the *acrophase* of the 24-h HRV rhythm in
  shift and rotating-shift workers, not about one morning's recovery score; and the only
  overnight-HR figure we found (heavier evening meals ≈ +0.73 bpm) is an unreviewed 2026
  preprint about meal *size*, not lateness. So the claim is **removed, not softened** —
  and Healthee logs no meals at all, so even a sourced version could never be said about
  this owner. This paragraph is the record of the removal; do not reintroduce the
  confounder without a primary source.
- **Components disagree, and that's expected.** HRV and RHR are only partly coupled; subjective
  wellness routinely **doesn't correlate** with objective markers [Saw 2016]. Disagreement is
  information (lower confidence), not a malfunction; a single tidy number hides this.
- **The overreaching blind spot persists.** Because vagal markers can rise when overreached
  [Bellenger 2016], a *high* recovery does **not** clear someone reporting mounting fatigue,
  sleep disruption, mood decline or stalling performance. A green score can be falsely
  reassuring; subjective decline and the safety bounds override it.
- **Never medical-grade.** Elevated RR + temperature is a "possible early signal," not a
  diagnosis; label recovery an **estimate**, and let the **trend** matter more than any single
  day.
- **Subjective wellness is not yet a shipped input to the number.** The 1–5 self-report is a
  first-class signal the *coach* should weight (especially when signals conflict), but the
  shipped `recovery_score` is currently the four overnight sensor factors only — do not imply
  the number already contains a wellness input.
- **Individual weighting is unknown a priori** and reactivity/orthosomnia is real: pushing a
  daily verdict at an anxious user can *cause* the stress and poor sleep it claims to measure
  [Saw 2015]. Keep recovery opt-in, framed as information, never moralised.
- **What's still unknown:** the right component weights; whether a composite beats reading
  components separately; the smallest-worthwhile-change band for the composite; how to fuse
  conflicting signals; and whether ML fusion generalises. Treat advanced composite scoring as
  **Emerging**.

## Bottom line
**Act on confidently (conclusive):**
- **Triangulate; never decide on one number.** No single physiological marker diagnoses
  recovery — the consensus standard is multi-parameter monitoring read together
  [Meeusen 2013; Buchheit 2014].
- **Subjective wellness is a first-class signal**, at least as sensitive as objective markers
  and often earlier — include a cheap morning self-report and weight it (and any pain) highest
  when signals conflict [Saw 2016; Hooper 1995].
- **Concordance = confidence.** Multiple inputs agreeing (HRV down + RHR up + poor sleep +
  high load + heavy legs) is a strong, actionable "ease" signal; a lone outlier is usually
  noise.
- **A high recovery never clears a fatigued or ill person** — vagal markers can rise when
  overreached, so subjective decline and the safety bounds override a green score
  [Bellenger 2016].
- **Overnight is the correct window and recovery is set at wake** — it does not rise during
  the day [Stanley 2013; Michael 2017].
- **Score autonomic markers vs the personal baseline; hold sleep to the absolute need** — the
  only way the score stays honest for a chronic short sleeper [Plews 2013; Cappuccio 2010].
- **Safety inputs (illness, acute sleep loss, pain) are hard overrides, not votes.**

**Hold loosely (unsettled):**
- **Any specific composite score or weighting.** Commercial scores are proprietary and not
  independently validated as predictors; the underlying signals are valid, the composite is
  not [Bellenger 2021; Dial 2025]. Healthee's score is a transparent, hedged summary, not a
  measurement.
- **The intraday readiness-decay model** — a conservative, explicitly unvalidated estimate;
  no validated "battery" formula exists.
- **The exact thresholds and component weights**, and whether individualised weights beat the
  fixed evidence-strength defaults — Emerging.
- **Whether a composite beats reading the components separately**, and whether ML fusion
  generalises.

## Coach Directives
- **D1:** Compute recovery by **triangulating ≥3 components** (HRV, RHR, sleep, respiratory
  rate, prior load, subjective wellness); **no single input may be decisive**, and **never
  present a recovery number without its per-factor breakdown**. — confidence: Established
- **D2:** **Always include a subjective morning check-in** (fatigue/soreness/stress/mood);
  treat it as at least as sensitive as the sensors and weight it (plus any pain) **highest
  when signals conflict**. — confidence: Established
- **D3:** Act on the **multi-day trend and concordance**, not a single day or single input;
  scale coaching confidence to how many inputs agree. — confidence: Established
- **D4:** Score HRV/RHR/RR vs the **person's own ~6-week baseline (robust z)**, but hold
  **sleep to the ABSOLUTE physiological need**, never a personal median — a chronic short
  sleeper is genuinely under-recovered. — confidence: Probable
- **D5:** Map recovery to **go / modify / rest** as a **suggestion the user can override**,
  explaining which components drove it — never a bare verdict or a silent plan rewrite. —
  confidence: Probable
- **D6:** **Never let a high/green recovery clear** someone reporting rising fatigue, poor
  sleep, mood decline, illness, pain, or stalling performance; vagal markers can rise when
  overreached. — confidence: Established (safety-relevant)
- **D7:** **Safety inputs are hard overrides, not votes:** illness-symptom + elevated RHR
  (and/or elevated RR + temperature as a "possible early signal"), acute sleep deprivation,
  and any reported pain/injury force modify/rest regardless of the composite. **Only the
  illness limb is enforced in code** (`derive/illness.py` → `read/recovery_guidance.py` +
  `challenges/recovery_guard.py`), and there it cannot be overridden by the score; the
  sleep-deprivation and pain limbs are coach rules with no code behind them, and no output
  rule stops the AI on any of the three. See *Safety bounds*, #87. — confidence:
  Established (safety-critical)
- **D8:** **Never use recovery to escalate** training and **never claim it predicts
  performance**; it eases or holds — the meta-analytic VO₂max effect was NS. — confidence: Probable
- **D9:** Treat the **composite number as low-precision** and label it an **estimate**;
  present the intraday readiness-decay as an explicitly unvalidated, conservative model
  ("recovery 72 → 58 (−14 today's load)"), never a validated battery. — confidence: Probable
- **D10:** Suppress or down-weight recovery when components lack history (≈2–3 weeks for
  HRV/RHR baselines; ≥28 days before ACWR contributes) or when an obvious confounder
  (alcohol, heat, travel, illness, menstrual phase) explains a dip. **Never a late meal** —
  that confounder was removed as unsourced (#92); see *Honesty & uncertainty* and
  [[late_eating_sleep]]. — confidence: Probable
- **D11:** Keep recovery **opt-in and non-moralised**; imposed daily verdicts reduce
  responsiveness and can cause the stress they measure (reactivity/orthosomnia). —
  confidence: Probable
- **D12:** In **Stage 1** use recovery **educationally** (lean on sleep + subjective
  check-in); begin light autoregulation in **Stage 2** (persistent concordant dips soften
  quality); full readiness-guided block timing in **Stage 3**, read through the plan's
  intent. — confidence: Probable

## References
- Saw, A. E., Main, L. C., & Gastin, P. B. (2016). *Monitoring the athlete training response:
  subjective self-reported measures trump commonly used objective measures: a systematic
  review.* British Journal of Sports Medicine, 50(5), 281–291.
  https://doi.org/10.1136/bjsports-2015-094758
- Saw, A. E., Main, L. C., & Gastin, P. B. (2015). *Monitoring athletes through self-report:
  factors influencing implementation.* Journal of Sports Science & Medicine, 14(1), 137–146.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC4306765/
- Hooper, S. L., Mackinnon, L. T., Howard, A., Gordon, R. D., & Bachmann, A. W. (1995).
  *Markers for monitoring overtraining and recovery.* Medicine & Science in Sports & Exercise,
  27(1), 106–112. https://doi.org/10.1249/00005768-199501000-00019
- Meeusen, R., Duclos, M., Foster, C., et al. (2013). *Prevention, diagnosis, and treatment of
  the overtraining syndrome: joint consensus statement of the ECSS and the ACSM.* European
  Journal of Sport Science, 13(1), 1–24. https://doi.org/10.1080/17461391.2012.730061
- Buchheit, M. (2014). *Monitoring training status with HR measures: do all roads lead to
  Rome?* Frontiers in Physiology, 5, 73. https://doi.org/10.3389/fphys.2014.00073
- Bellenger, C. R., Fuller, J. T., Thomson, R. L., Davison, K., Robertson, E. Y., & Buckley,
  J. D. (2016). *Monitoring athletic training status through autonomic heart rate regulation:
  a systematic review and meta-analysis.* Sports Medicine, 46(10), 1461–1486.
  https://doi.org/10.1007/s40279-016-0484-2
- Bellenger, C. R., Miller, D. J., Halson, S. L., Roach, G. D., & Sargent, C. (2021).
  *Wrist-based photoplethysmography assessment of heart rate and heart rate variability:
  validation of WHOOP.* Sensors, 21(10), 3571. https://doi.org/10.3390/s21103571
- Dial, M. B., Hollander, M. E., Vatne, E. A., Emerson, A. M., Edwards, N. A., & Hagen, J. A.
  (2025). *Validation of nocturnal resting heart rate and heart rate variability in consumer
  wearables.* Physiological Reports, 13(16), e70527. https://doi.org/10.14814/phy2.70527
- Granero-Gallegos, A., González-Quílez, A., Plews, D., & Carrasco-Poyatos, M. (2020).
  *HRV-based training for improving VO2max in endurance athletes: a systematic review with
  meta-analysis.* International Journal of Environmental Research and Public Health, 17(21),
  7999. https://doi.org/10.3390/ijerph17217999
- Manresa-Rocamora, A., Sarabia, J. M., Javaloyes, A., Flatt, A. A., & Moya-Ramón, M. (2021).
  *Heart rate variability-guided training for enhancing cardiac-vagal modulation, aerobic
  fitness, and endurance performance: a methodological systematic review with meta-analysis.*
  (also cited in the source as *J Sci Med Sport*.) International Journal of Environmental
  Research and Public Health, 18(19), 10299. https://doi.org/10.3390/ijerph181910299
- Plews, D. J., Laursen, P. B., Stanley, J., Kilding, A. E., & Buchheit, M. (2013). *Training
  adaptation and heart rate variability in elite endurance athletes: opening the door to
  effective monitoring.* Sports Medicine, 43(9), 773–781.
  https://doi.org/10.1007/s40279-013-0071-8
- Aune, D., et al. (2017). *Resting heart rate and the risk of cardiovascular disease, total
  cancer, and all-cause mortality — a systematic review and dose-response meta-analysis of
  prospective studies* (n ≈ 1.2M; +10 bpm RHR → RR ≈ 1.17 all-cause mortality). Nutrition,
  Metabolism & Cardiovascular Diseases, 27(6), 504–517. (As cited in the source note.)
- Cappuccio, F. P., et al. (2010). *Sleep duration and all-cause mortality: a systematic
  review and meta-analysis* (short sleep → increased mortality). Sleep, 33(5), 585–592. (As
  cited in the source note.)
- Stanley, J., Peake, J. M., & Buchheit, M. (2013). *Cardiac parasympathetic reactivation
  following exercise: implications for training prescription* (review of parasympathetic
  reactivation during recovery/sleep). Sports Medicine, 43(12), 1259–1277. (As cited in the
  source note.)
- Michael, S., et al. (2017). *Cardiac autonomic responses during exercise and post-exercise
  recovery — early heart-rate recovery is parasympathetically mediated.* (As cited in the
  source note.)
- Smarr, B. L., et al. (2020) & Quer, G., et al. (2021). *Elevated overnight respiratory rate
  as an early illness/strain signal from wearables.* (As cited in the source note.)
- Gabbett, T. J. (2016). *The training-injury prevention paradox: should athletes be training
  smarter and harder?* (acute:chronic workload ratio). British Journal of Sports Medicine,
  50(5), 273–280. https://doi.org/10.1136/bjsports-2015-095788

## Healthee implementation & honesty policy
- **Derived field: `recovery_score`** (0–100, integer) in `derived_daily`. Provenance:
  `derive/recovery.py::derive_recovery`, **ported verbatim from legacy v2** (science code —
  not to be "simplified" on refactor). Constants:
  - `RECOVERY_WEIGHTS = {"hrv": 0.42, "rhr": 0.28, "sleep": 0.20, "rr": 0.10}` — assigned **by
    evidence strength, not fitted**, and **renormalized over the factors present** for the night.
  - Personal baseline = **robust median + MAD·1.4826** over a trailing **42-day** window,
    requiring **≥5 points**, with a **0.5 floor on the robust SD** so a flat history can't
    explode the z-score; the day itself is excluded.
  - Autonomic factors score `50 + k·z` (higher-better) or `50 − k·z` (lower-better), clamped
    0–100, with **k = 20** for HRV, **20** for RHR, **15** for RR.
  - **Sleep is scored vs ABSOLUTE need** (not the personal baseline): `100 · tst_min / need_min`,
    reading `sleep_need_min` and `tst_min` from the `sleep_health_score_4dim` row.
    **There is no fallback.** When `sleep_need_min` is absent the sleep factor is ABSENT and
    the remaining weights renormalise — `derive/recovery.py:92-138` deleted the 480-minute
    default deliberately, calling it *"a personal target invented for an owner we have never
    been able to compute one for"* and *"the third definition of one metric"*.
    *(Corrected 2026-09-08: this bullet still documented "(fallback **480 min**)".)*
  - The score is **`None` (undefined, not 0)** unless at least one of HRV or RHR is present —
    "no data" stays distinct from "low recovery".
  - The full **per-factor breakdown** (each factor's `sub`, `z`, `value`, `baseline`, the
    `weights`, `method="evidence_weighted_personal_baseline"`, and `note_id`) is written to the
    row's `flags` so the UI/LLM **never** render a bare number.
- **Component metrics** come from their own derive modules: `hrv_sleep_avg`
  (`derive/hrv_spo2_resp.py`, see `heart_rate_variability`), `rhr_daily`,
  `respiratory_rate_sleep`, and the sleep total behind `sleep_health_score_4dim`.
- **Intraday readiness decay** (`readiness(t) = recovery × (1 − 0.5·min(1, strain_today /
  typical_daily_strain))`, strain = Banister TRIMP so far, typical = personal 30-day median)
  is an **app-side, explicitly unvalidated** layer surfaced as "recovery 72 → 58 (−14 today's
  load)". No validated "battery" formula exists.
- **Not yet in the shipped number:** skin-temp deviation (not in the daily derived store), the
  **subjective-wellness input**, prior-load in the *morning* score, and individualised
  (vs fixed) weights. These are coaching-model / roadmap elements — the coach may use a
  subjective report qualitatively, but must **not** imply the `recovery_score` number already
  contains them.
- **Honesty policy (carry into UI + LLM):** always an **estimate** shown with its per-factor
  breakdown + citations; **never a bare number, never a death-risk number, never medical-grade**
  (elevated RR + temp = "possible early signal," not a diagnosis); **never claim it predicts
  performance**; **trend > single day**; autonomic markers are personal-relative while sleep is
  held to the absolute need. This is the documented, user-approved exception to the no-composite
  rule (see `no_validated_sleep_score`).
