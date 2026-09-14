---
id: sleep_duration_mortality
name: "Sleep duration and all-cause mortality"
topic: Sleep duration and all-cause mortality (U-shaped curve)
category: sleep
grade: Established
summary: "Habitual sleep shows a U-shaped tie to mortality — both short and long sleep carry higher risk than each cohort's own normal-sleep reference (pooled RR 1.12 short, 1.30 long) — but Cappuccio 2010 states NO reference band, and it is observational, self-reported, and a population signal, never a single-night verdict. Where a recommended band is needed the citation is NSF 2015 (7–9 h for 18–64), not this paper."
aliases: ["sleep duration", "sleep and mortality", "sleep longevity", "u-shaped sleep mortality", "sleep_duration", "hours of sleep", "hours slept", "sleep hours"]
applies_to_metrics: ["sleep_health_score_4dim"]
applies_to_interventions: []
population: general
last_reviewed: 2026-08-01
---

# Sleep duration and all-cause mortality

## Summary
Habitual sleep duration has a U-shaped association with all-cause mortality:
both short and long sleep carry higher risk than the middle of the curve. It is
background context for *chronic* patterns only — observational, self-reported, and
about the population, not a person's exact optimum or any single night.

**Do not quote a reference band from this note.** Cappuccio 2010 states none (see the
⚠ box in "The evidence"); the "<6 h"/">9 h" shorthand is the common
operationalisation across cohorts, not the meta-analysis's own cut-points. The
recommended band — 7–9 h for adults 18–64 — is **NSF 2015's consensus**, a different
kind of claim, and must be cited as such.

## What it is
The epidemiological relationship between how long a person habitually sleeps and
their risk of dying from any cause. Risk rises on both tails of the curve; the
reference category against which those tails are measured **varied across the pooled
cohorts** and the paper names no single band (#88).

## Physiology / mechanism
The mechanisms are only partly understood and differ by tail. Short sleep is
linked to sympathetic activation, impaired glucose regulation, inflammation, and
raised blood pressure. Long sleep is widely thought to be a *marker* of
underlying illness, depression, or low cardiorespiratory fitness rather than a
direct cause — which is why the long tail must be read cautiously.

## The evidence
- **[Established]** Habitual sleep duration shows a U-shaped association with
  all-cause mortality: both short and long sleep are associated with higher
  mortality than each study's own normal-sleep reference category (Cappuccio 2010,
  *Sleep*).
- **[Established]** Short sleep: pooled relative risk ≈ **1.12** (95% CI 1.06–1.18,
  P < 0.01), with heterogeneity between studies (P = 0.02) and no evidence of
  publication bias.
- **[Established]** Long sleep: pooled relative risk ≈ **1.30** (95% CI 1.22–1.38,
  P < 0.0001), with **significant** heterogeneity (P < 0.0001) and no evidence of
  publication bias.

> ⚠️ **Corrected 2026-08-01 (#88): Cappuccio 2010 states no reference band, and this
> note used to attach "7–8 h" to it four times.** The abstract was re-read at PubMed
> on 2026-08-01: it reports the two pooled RRs and no reference category at all, and
> the reference category *varied across the 27 pooled cohort samples*. So **neither
> "7–8 h" nor "7–9 h" is Cappuccio's** — this note asserted the former while
> `no_validated_sleep_score`, `sleep_health_score_multidim` and the shipped 4-dim
> score asserted the latter, all citing the same paper. Both were over-claims and both
> are now gone.
>
> What Cappuccio supports is the **shape and the two effect sizes**, nothing finer.
> The definitions of "short" and "long" also varied by cohort; the "<6 h" and ">9 h"
> shorthand used elsewhere in this corpus is the *common* operationalisation, not the
> meta-analysis's own cut-points. Where a corpus or a code path needs an actual
> recommended band, the citation is **NSF 2015 (Hirshkowitz et al., *Sleep Health*):
> 7–9 h for adults 18–64, 7–8 h for 65+** — a consensus recommendation, which is a
> different and weaker kind of claim than a pooled effect size, and must be presented
> as one.

Evidence base: Cappuccio FP, D'Elia L, Strazzullo P, Miller MA. "Sleep duration
and all-cause mortality: a systematic review and meta-analysis of prospective
studies." *Sleep* 2010;33(5):585–92. PMID 20469800 — 16 studies providing 27
independent cohort samples, n = 1,382,999 participants, 112,566 deaths, follow-up
4–25 years, sleep duration by questionnaire and outcome by death certification.
*[abstract re-verified at PubMed 2026-08-01]*

## How we compute it
Not a derived metric of its own — this note is the mortality-context evidence
behind the *duration* dimension of the sleep-health score and any multi-week
sleep-duration trend. Duration comes from the strap's sleep sessions (total
sleep time), read via `sleep_health_score_4dim` and the sleep history.

## How the coach uses it
- Background context only, and only for **chronic** patterns.
- **Never** flag a single short night as a health concern on this basis.
- A multi-week trend of <6h *average* sleep is worth surfacing as a personal
  pattern, citing this note — paired with the person's own baseline.
- The proximal signal is deviation from the user's own median, not the
  population mean.

## Safety bounds
This is a longevity-epidemiology note, not a diagnostic. Never present sleep
duration as a personal death-risk number, and never alarm someone over normal
night-to-night variation. Persistent extreme short sleep alongside distress is a
reason to suggest a clinician, not a statistic.

## Honesty & uncertainty
- All included studies are **observational**. Reverse causation is plausible:
  long sleep may reflect underlying illness rather than cause harm.
- Sleep duration in the source studies was **self-reported**, and self-report does
  not merely add noise — it is **biased, by an amount that grows as sleep shortens**.
  This note used to say "self-report typically over-estimates by 30–60 min", uncited.
  The primary source was checked on 2026-08-01 and does not support a flat range:
  **Lauderdale et al. 2008** (*Epidemiology* 19(6):838–45, PMID 18854708; CARDIA
  Chicago, n = 669, 3 days of wrist actigraphy against questions about usual sleep)
  reports mean measured sleep of **6.0 h against a mean report of 6.8 h**, and that
  "*persons sleeping 5 hours over-reported their sleep duration by 1.2 hours, and
  those sleeping 7 hours over-reported by 0.4 hours*". So 30–60 min is roughly right
  in the middle of the curve and **materially too small below ~5.5 h measured** —
  exactly where a chronic short sleeper lives. Anything that applies a hazard curve
  from these studies to *device-measured* hours must convert first; see
  [[biological_age_estimate]] and `analytics/reference_scales.py`, which does.
- The population association does **not** imply a single individual's optimum is
  any particular number of hours — personal baseline matters more than the population
  mean, and the meta-analysis supplies no band to be exact about (#88).
- The association is for **habitual** sleep, not single nights.

## Bottom line
**Act on confidently:** protect a habitual sleep duration in the middle of the
curve — cite **NSF 2015's 7–9 h (18–64)** if a number is wanted, never this paper for
a band; a sustained multi-week average under ~6h is a real, citable personal pattern
worth addressing.
**Hold loosely:** the exact personal optimum, the long-sleep tail (likely a
marker, not a cause), and anything inferred from single nights.

## Coach Directives
1. Use only for chronic (multi-week) sleep-duration patterns, never a single
   night. *(confidence: high)*
2. Cite deviation from the person's own median as the proximal signal; the
   population U-curve is context, not a verdict. *(high)*
3. Never present sleep duration as a personal death-risk number. *(high)*

## References
- Cappuccio FP, D'Elia L, Strazzullo P, Miller MA. 2010. Sleep duration and
  all-cause mortality: a systematic review and meta-analysis of prospective
  studies. *Sleep* 33(5):585–592. PMID 20469800. **States no reference band** — see
  the ⚠ box above. *[abstract re-verified at PubMed 2026-08-01]*
- Lauderdale DS, Knutson KL, Yan LL, Liu K, Rathouz PJ. 2008. Self-reported and
  measured sleep duration: how similar are they? *Epidemiology* 19(6):838–845. PMID
  18854708. Mean measured 6.0 h vs mean reported 6.8 h; over-report 1.2 h at 5 h
  measured and 0.4 h at 7 h measured; reports rose 34 min per additional measured
  hour; correlation 0.47. **The source of the self-report↔device conversion**, and the
  reason the old uncited "30–60 min" is gone. *[abstract verified at PubMed 2026-08-01]*
- Hirshkowitz M, Whiton K, Albert SM, et al. 2015. National Sleep Foundation's
  sleep time duration recommendations: methodology and results summary. *Sleep
  Health* 1(1):40–43. doi:10.1016/j.sleh.2014.12.010. An 18-member expert panel
  applying the RAND/UCLA Appropriateness Method — **7–9 h for adults 18–64, 7–8 h
  for 65+**. This, not Cappuccio, is the citation for a recommended band; it is
  expert consensus, not a pooled effect size, and is presented as such.

## Healthee implementation & honesty policy
- Not a stored metric; it grounds the *duration* dimension of
  `sleep_health_score_4dim` and any long-run sleep-duration trend surfaced to the
  user.
- Honesty rules the coach must hold: never a death-risk number; never alarm on a
  single night; the long-sleep tail is presented as a possible marker of illness,
  not a cause; the person's own baseline is always the proximal signal.
- Relates to [[no_validated_sleep_score]] (no single validated sleep score),
  [[sleep_need_debt]] (age-based need), and [[sleep_regularity_index]]
  (regularity, a stronger mortality-linked signal than duration alone).
