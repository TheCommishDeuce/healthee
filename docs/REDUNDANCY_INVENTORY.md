# Redundancy inventory (F5)

Owner feedback 2026-09-23: "a lot of redundancy in sections and screens". This is
the screen × panel inventory after F1–F4 landed, the overlaps found in it, and a
proposal for each. **Status (2026-09-23): the owner accepted the recommendations.
R1, R2, R3, R5 and R8 are done (`142f7d6`); R4, R6, R7 are kept on purpose; R9 is
open (server PR).** The screen table below is the state *before* the consolidation.

## What each screen draws now

| Screen | Panels, top to bottom |
|---|---|
| **Today** | Sleep summary · Recovery (factor bars) · Weight · Steps (by hour) · Heart rate (by hour, resting/low/high) · Stress (by hour, peak hour) |
| **Sleep** | Sleep analysis · Sleep reading · How your night unfolded · Every stage, accounted for · Your body overnight (5 vitals) · Four sleep checks · Sleep need & debt (measured week) · Your week, stage by stage · Sleep timing (SRI) · Naps (only on a nap day) |
| **Activity** | Activity analysis · VO₂max with its source · Fitness plan · Fitness → age / Recovery cards · Today's movement (steps week + energy) · Heart rate & stress (linked, by hour) · Your week, by intensity · Training load · Zones · Sessions |
| **Insights** | Pattern card / Fitness → age card · Your longer patterns (7 trends) · Notable days · Sleep history / Fitness estimates rows |
| Sleep history | Sleep duration (30 nights) · Seven nights of stages · Open a night (rows) |
| Recovery | Recovery, explained · Compared with your baseline · Your body overnight (5 vitals) · Capacity through the day |
| Body (age) | Age ladder · Confidence · Fitness term · Sleep term · Excluded terms |
| Fitness | Cardiorespiratory · Stored history · Instrument · Age bridge · Load/work · Rhythm |
| Metric history | One metric's dated series (+ insight card) |

## Overlaps, and what to do about them

| Id | Same thing shown twice | Proposal |
|---|---|---|
| **R1** | The 7-night stacked stage chart: Sleep *Your week, stage by stage* and Sleep history *Seven nights of stages*. Same widget (`HStackedSleep`), same nights. | **Remove from Sleep history.** Sleep history keeps what only it has: the 30-night duration chart and the night list. |
| **R2** | The five overnight vitals table: Sleep *Your body overnight* and Recovery *Your body overnight*. Same table widget, but fed from **two server payloads** (`/api/sleep` vs `/api/today.last_sleep_extras`). | **Remove from Recovery**, replace with a one-line link to Sleep. Recovery's factor bars already carry the HRV and resting-HR scores that feed it. |
| **R3** | The day's hourly heart rate and stress: Today's new *Heart rate* and *Stress* cards and Activity's *Heart rate & stress* linked chart. Same two hourly series. | **Remove from Activity** (Today now has both in more detail). Alternative: keep Activity's as the side-by-side comparison, and accept the repeat. |
| **R4** | Today's step total on Today *Steps* and Activity *Today's movement*. | **Keep both**: Today is the day by hour, Activity is the week plus energy. Listed for completeness. |
| **R5** | Sleep regularity (SRI) in three places: Sleep checks (81/100), Sleep timing (SRI 81), Insights trend (81.1). | **Drop the SRI figure from the Sleep timing panel**; the checks row carries today's value, Insights the trend. |
| **R6** | Nightly sleep duration: Sleep need & debt (7 nights against need) and Sleep history (30 nights). | **Keep both**: different question (shortfall vs. the month). |
| **R7** | The *Fitness → age* card on Insights and on Activity (added by F3). | **Keep both** for now: owner kept it on Insights and asked for more visibility from Activity. Revisit if it still reads as repetition. |
| **R8** | Code, not UI: `AgeEntryCard.contribution` and Activity's `fitnessContributionYears` are the same function. | **Merge into one** (no visible change). |
| **R9** | Server, one-definition rule: `/api/sleep`'s overnight blood oxygen and breathing are computed by their own query (`read/sleep_page.py`), not read from the canonical `spo2_overnight` / `respiratory_rate_sleep` (`derive/hrv_spo2_resp.py`). They agree today (99 vs 99.0) by coincidence of method, not by construction. | **Server change**: have the sleep page read the derived metrics. Own PR with known-value tests. |
