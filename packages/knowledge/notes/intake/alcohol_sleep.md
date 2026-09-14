---
id: alcohol_sleep
name: "Alcohol, sleep architecture, and overnight autonomics"
topic: Alcohol disrupts second-half sleep architecture and acutely lowers HRV
category: intake
grade: Established
summary: "Alcohol before bed front-loads slow-wave sleep then fragments the second half (more wake, delayed and reduced REM), lowers overnight HRV and raises heart rate during sleep — dose-dependent with no established floor (Pietilä 2018: RMSSD −2.0 / −5.7 / −12.9 ms and HR +1.4 / +4.0 / +8.7 bpm at low / moderate / high dose, all significant); a morning-after HRV dip after a logged drink is expected, not an anomaly."
aliases: ["alcohol", "drinking", "alcohol before bed", "nightcap", "alcohol and sleep", "alcohol and hrv", "drinks", "a couple of drinks", "a few drinks", "booze", "wine", "beer"]
applies_to_metrics: ["tst_min", "sleep_health_score_4dim", "hrv_sleep_avg", "rhr_daily"]
applies_to_interventions: ["alcohol"]
population: general
last_reviewed: 2026-08-01
related: ["caffeine_alcohol_cutoff_plan", "caffeine_sleep", "heart_rate_variability"]
tags: [alcohol, sleep, hrv, autonomic]
---

# Alcohol, sleep architecture, and overnight autonomics

## Summary

Alcohol **before bed** predictably alters sleep architecture and autonomic
markers overnight: it increases slow-wave sleep in the **first half** then
**fragments the second half** (more wake), **delays and shortens REM**, and
during sleep **reduces HRV** (RMSSD) and **raises heart rate**. The autonomic
magnitudes are measured, not estimated: over the first hours of sleep, RMSSD
falls by **2.0 / 5.7 / 12.9 ms** and heart rate rises by **1.4 / 4.0 / 8.7 bpm**
at low / moderate / high dose (Pietilä et al. 2018, n = 4,098). The effect is
dose-dependent with **no established lower cutoff** — it is already significant
at the lowest doses studied (≤0.25 g alcohol/kg body weight, ~17 g of ethanol,
about one US standard drink for a 70 kg adult) and worsens as the dose rises.
The Healthee-critical consequence: because our `hrv_sleep_avg` and `rhr_daily`
are computed over the sleep period, a **drop in HRV / rise in RHR reported the
morning after a logged drink is expected physiology, not a health-concerning
anomaly**.

## What it is

Alcohol is a CNS depressant and diuretic that, taken near bedtime, produces a
characteristic two-phase night. It is logged as an intervention and evaluated
against that night's sleep and the next morning's autonomic metrics. "Moderate"
here means roughly 1–2 standard drinks. Effects are graded by **dose**; moving
the last drink earlier is *not* an established way to avoid them (see Honesty &
uncertainty).

## Physiology / mechanism

As blood alcohol falls through the night, its early sedative/GABAergic effect
(which deepens slow-wave sleep early) gives way to a **rebound** in the second
half: sympathetic reactivation, REM suppression then rebound, and arousals. The
same sympathetic shift and the metabolic/diuretic load depress vagally-mediated
HRV and raise heart rate overnight — so the autonomic signals move for
alcohol-clearance reasons, independent of training recovery.

## The evidence

### Sleep architecture — front-loaded SWS, fragmented second half [Established]
"At all dosages, alcohol causes a reduction in sleep onset latency, a more
consolidated first half sleep and an increase in sleep disruption in the second
half of sleep"; slow-wave sleep is increased in the first half of the night
across dose, age and sex (Ebrahim et al. 2013). REM is **delayed and shortened**:
"a delay in the onset of rapid eye movement (REM) sleep and a reduction in the
duration of REM sleep", with disruption present from a low dose (≤0.50 g/kg) and
worsening with dose (Gardiner et al. 2025, meta-analysis of 27 studies).
Ebrahim adds that total-night REM percentage falls "in the majority of studies at
moderate and high doses with no clear trend apparent at low doses", and that the
delay of the first REM period is "the most recognizable effect of alcohol on REM
sleep".

**No percentage figure is quoted here on purpose.** Neither review reports a
pooled second-half REM reduction; the earlier "~10–25%" in this note had no
source and has been removed. Gardiner's own summary is that effects on total
sleep time, sleep efficiency and wake-after-sleep-onset "could not be
determined, with large uncertainty". *[primary-source verified 2026-08-01]*

### Overnight HRV — acute reduction [Established]
Alcohol acutely **reduces vagally-mediated HRV during sleep**, dose-dependently.
Over the first 3 hours of sleep, RMSSD fell by **2.0 ms** (low, ≤0.25 g/kg),
**5.7 ms** (moderate, >0.25–0.75 g/kg) and **12.9 ms** (high, >0.75 g/kg);
"the intraindividual effects of alcohol intake on the ANS regulation were
observed also with low alcohol intake (all P<.001)" (Pietilä et al. 2018,
n = 4,098, beat-to-beat R-R). **The source reports absolute millisecond deltas,
not percentages** — the earlier "commonly 15–30%" in this note was not in the
cited paper and has been removed. *[primary-source verified 2026-08-01]*

### Heart rate during sleep — elevated, dose-dependently [Established]
Heart rate over the first 3 hours of sleep rose by **1.4 bpm** (low), **4.0 bpm**
(moderate) and **8.7 bpm** (high dose) (Pietilä et al. 2018). A separate
prospective smartwatch study found nocturnal resting heart rate rising from
**63.6 ± 9.2 to 66.6 ± 9.0 bpm** (p<0.001) across three nights of moderate
intake in 40 adults, returning to **64.9 ± 9.3 bpm** afterwards (Strüven et al.
2025) — small sample, but it measures the whole-night nocturnal RHR that our
`rhr_daily` is built from. The earlier "~5–10 bpm above personal baseline" in
this note was uncited and, framed around 1–2 drinks, overstated the measured
low-dose figure (1.4 bpm) by 3–7×; it has been replaced by the per-band numbers.
Nothing in either source supports the previous claim that the elevation persists
"until late morning". *[primary-source verified 2026-08-01]*

### Dose-response — bands, not a single threshold [Established]
The effect is **dose-dependent, and no primary source supports a detection
floor**: disruption is already significant in the lowest dose band each study
defines. The two literatures band the dose differently, so always quote the band
*with its source* rather than one cutoff number.
*[primary-source verified 2026-07-31]*

- **Sleep architecture** — REM disruption occurs "following consumption of a low
  dose of alcohol (≤0.50 g∙kg⁻¹ or approximately two standard drinks) and
  progressively worsen[s] with increasing doses of alcohol"; reductions in
  sleep-onset latency and in latency to N3 were seen "only ... following the
  consumption of a high dose" (≥0.85 g∙kg⁻¹) (Gardiner et al. 2025,
  meta-analysis of 27 studies). Ebrahim et al. 2013 — the older, *qualitative*
  review — instead reports shorter sleep onset "at all dosages" and "no clear
  trend" for total-night REM at low doses. **The two disagree**; prefer the
  meta-analysis for dose thresholds and treat the low-dose sleep-onset effect as
  unsettled.
- **Overnight autonomics** — effects on autonomic regulation "were observed also
  with low alcohol intake" — low being **≤0.25 g/kg** there (moderate
  >0.25–0.75, high >0.75), all p<0.001 (Pietilä et al. 2018, n = 4,098).

**Unit trap — do not gloss g/kg as "a drink".** 0.5 g/kg in a 70 kg adult is
**35 g of ethanol ≈ 2.5 US standard drinks** (14 g each) — *not* one drink. One
US standard drink for a 70 kg adult is ≈ 0.2 g/kg. Note also that the reviews'
own "≈ N standard drinks" glosses assume their national standard-drink size
(Australia/UK ≈ 8–10 g), so grams per kilogram is the figure to carry; convert
only at the point of display, with the drink size stated.

## How we compute it

Alcohol is a **logged intervention** (`manual_entry`, kind `alcohol`), not a
derived metric. It is correlated against that night's `tst_min` and
`sleep_health_score_4dim` and the next morning's `hrv_sleep_avg` and `rhr_daily`.
The personal cutoff-time finder that mines these logs lives in
`caffeine_alcohol_cutoff_plan`.

## How the coach uses it

- A drop in nightly HRV the morning after an alcohol entry is **expected**, not a
  health-concerning anomaly — say so plainly.
- Surface the connection when the user has logged alcohol and we observe an
  HRV/RHR shift the next morning, citing this note as the basis.
- Do **not** extrapolate to long-term health claims from a single drinking event.
- Do **not** offer "drink earlier" as a fix. The one controlled test of that idea
  gave 0.55 g/kg **6 hours** before bed, with breath-ethanol back to **zero at
  lights-out**, and still found reduced REM, reduced sleep efficiency and a
  **twofold increase in wakefulness in the second half** of the night (Landolt
  et al. 1996). If the user's own logs show a personal cutoff, present it as
  *their* pattern (`caffeine_alcohol_cutoff_plan`), not as a general rule.
- Dose is the lever the evidence supports: less alcohol, smaller effect.

## Safety bounds

- No acute safety guardrail — this is a sleep/autonomic note. Do not turn a single
  logged drink into a medical warning or a long-term risk claim.
- Never present morning-after HRV/RHR shifts as a diagnosis.

## Honesty & uncertainty

- **Individual variation is real** — some people show smaller effects, but the
  **direction** of effect is consistent.
- **What actually modifies the size of the autonomic hit** (Pietilä et al. 2018):
  age — "the effect of alcohol intake on the change in HR and RMSSD was stronger
  in young subjects than in older subjects" (at 0.75 g/kg, RMSSD fell 10.9 ms for
  a 30-year-old vs 4.7 ms for a 60-year-old) — and **baseline sleep heart rate**:
  "alcohol intake increased HR significantly more among subjects with lower than
  higher baseline sleep HR". Being fit does not rescue you: "being physically
  active does not seem to protect from the negative effects of alcohol intake on
  the ANS during sleep."
  *An earlier version of this note claimed light drinkers take a larger HRV hit
  than heavy drinkers, "replicated". That was uncited, and Pietilä could not have
  shown it — "the alcohol drinking habits of the participants were not known".
  Removed 2026-08-01.* *[primary-source verified 2026-08-01]*
- **Timing is not a proven escape hatch.** Alcohol at 0.55 g/kg six hours before
  bed — breath-ethanol zero by lights-out — still reduced REM and sleep
  efficiency and **doubled second-half wakefulness** (Landolt et al. 1996,
  n = 10 middle-aged men). Van Reen et al. 2011, testing alcohol at four times of
  day under forced desynchrony, found the disruption tracked **circadian phase**
  rather than hours-before-bed, and concluded the findings are "inconsistent with
  the idea that a low dose of alcohol is a useful sleep aid when attempting to
  sleep at an adverse circadian phase". *An earlier version of this note asserted
  ">4 h before bed has smaller second-half effects" in three places, including as
  a Coach Directive, with no source. Removed 2026-08-01.*
  *[primary-source verified 2026-08-01]*
- **There is no "safe below X" dose here.** Every band boundary in the
  literature (0.25, 0.50, 0.75, 0.85 g/kg) is a *study grouping*, not a
  threshold below which nothing happens — the lowest band in each study still
  showed a significant effect. Do not derive an "alcohol is fine under N drinks"
  rule from these numbers.
- Single-night effects say nothing about long-term health; do not extrapolate.

## Bottom line

**Act on confidently:** a nightcap consolidates the first half of the night and
fragments the second, delays and shortens REM, lowers HRV during sleep and raises
heart rate — dose-dependently, with the effect already measurable at the lowest
dose studied. The measured autonomic sizes are RMSSD −2.0 / −5.7 / −12.9 ms and
HR +1.4 / +4.0 / +8.7 bpm for low / moderate / high dose (Pietilä et al. 2018).
A morning-after HRV dip following a logged drink is expected, not an anomaly.

**Hold loosely:** the exact magnitude for a given user and dose; the size of the
REM loss (no pooled figure exists); and the personal cutoff hour — individual,
best learned from the user's own logs, and **not** supported as a general rule
by the timing studies.

## Coach Directives

1. Treat a next-morning HRV drop / RHR rise after a logged alcohol entry as
   expected physiology; report it as such, not as an anomaly, and cite this note.
   *(confidence: high)*
2. Do not extrapolate a single drinking event to long-term health claims. *(high)*
3. When surfacing the effect, frame it by **dose** — the lever the evidence
   supports — rather than blanket avoidance. Do **not** tell the user that
   drinking earlier avoids it: alcohol 6 h before bed with zero breath-ethanol at
   lights-out still doubled second-half wakefulness (Landolt et al. 1996), and
   Van Reen et al. 2011 found disruption tracking circadian phase, not
   hours-before-bed. A personal cutoff hour may only be offered as *this user's
   observed pattern* from their own logs (`caffeine_alcohol_cutoff_plan`), never
   as a general rule. *(confidence: moderate)*
4. Never present overnight autonomic shifts from alcohol as a diagnosis. *(high)*

## References
- Ebrahim IO, Shapiro CM, Williams AJ, Fenwick PB. **"Alcohol and sleep I: effects
  on normal sleep."** *Alcoholism: Clinical and Experimental Research*
  2013;37(4):539–549. doi:10.1111/acer.12006. PMID 23347102. **Qualitative**
  review of controlled-dose studies (it reports directions, not pooled effect
  sizes).
- Gardiner C, Weakley J, Burke LM, et al. **"The effect of alcohol on subsequent
  sleep in healthy adults: a systematic review and meta-analysis."** *Sleep
  Medicine Reviews* 2025;80:102030. doi:10.1016/j.smrv.2024.102030.
  PMID 39631226. 27 studies; source of the ≤0.50 g/kg low / ≥0.85 g/kg high dose
  bands and the REM dose-response.
- Pietilä J, Helander E, Korhonen I, et al. **"Acute effect of alcohol intake on
  cardiovascular autonomic regulation during the first hours of sleep in a large
  real-world sample of Finnish employees: observational study."** *JMIR Mental
  Health* 2018;5(1):e23. doi:10.2196/mental.9519. PMID 29549064. n = 4,098,
  beat-to-beat R-R data; source of the ≤0.25 / >0.25–0.75 / >0.75 g/kg autonomic
  dose bands **and of every bpm/ms figure in this note**. Analysis window: the
  first 3 hours of sleep.
- Landolt HP, Roth C, Dijk DJ, Borbély AA. **"Late-afternoon ethanol intake
  affects nocturnal sleep and the sleep EEG in middle-aged men."** *Journal of
  Clinical Psychopharmacology* 1996;16(6):428–436. PMID 8959467. n = 10;
  0.55 g/kg **6 h before bedtime**, breath-ethanol zero at lights-out, yet REM
  and sleep efficiency fell and second-half wakefulness doubled — the source for
  "earlier is not a fix".
- Van Reen E, Tarokh L, Rupp TL, Seifer R, Carskadon MA. **"Does timing of alcohol
  administration affect sleep?"** *Sleep* 2011;34(2):195–205. PMID 21286495.
  n = 26, 20-h forced desynchrony; disruption tracked **circadian phase**, and
  the findings are "inconsistent with the idea that a low dose of alcohol is a
  useful sleep aid when attempting to sleep at an adverse circadian phase".
- Strüven A et al. **"The impact of alcohol on sleep physiology: a prospective
  observational study on nocturnal resting heart rate using smartwatch
  technology."** *Nutrients* 2025;17(9):1470. doi:10.3390/nu17091470.
  PMID 40362779. n = 40; whole-night nocturnal RHR 63.6 → 66.6 → 64.9 bpm across
  baseline / three nights of moderate intake / recovery. Small, non-randomised —
  carried as corroboration of direction on the metric we actually compute, not as
  a magnitude authority.

**Removed 2026-08-01 —** Park SY et al. *"The effects of alcohol on quality of
sleep."* Korean Journal of Family Medicine 2015;36(6):294–299. It was cited here
as a "review with focus on architecture changes" and used to support the REM
claim. It is neither: it is a **cross-sectional questionnaire survey** (234 men,
159 women attending a general hospital) correlating AUDIT-KR with PSQI-K — no
polysomnography, no REM, no sleep-stage measurement, and about *habitual* intake
rather than an acute pre-bed dose. It cannot support any claim this note makes,
so it is dropped rather than re-labelled.

## Healthee implementation & honesty policy

- Alcohol is a logged intervention, not a derived metric — no `derived_daily` row.
  It is a `manual_entry` (kind `alcohol`) correlated against `tst_min`,
  `sleep_health_score_4dim`, `hrv_sleep_avg`, and `rhr_daily`.
- **The confound rule is mandatory**: when the morning `hrv_sleep_avg` drops or
  `rhr_daily` rises on a day following a logged drink, the coach MUST name the
  alcohol as the expected cause and MUST NOT report the change as a health anomaly
  or an overreaching signal. This is the "never shows a wrong metric as an alarm"
  contract applied to alcohol.
- No composite "alcohol score" is derived; alcohol only contextualises existing
  metrics and feeds the personal cutoff finder (`caffeine_alcohol_cutoff_plan`).
- Honesty rule: single-event only — never launder one night's autonomic shift into
  a long-term health claim.
