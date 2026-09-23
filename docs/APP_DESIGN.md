# Healthee App — design & build tracker (Phase 2)

> **Personal-use rebuild (2026-09-22):** screen scope and placement now follow
> [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md), not the historical layout below.
> Today is sleep, overnight recovery and weight entry; HR/stress belongs to Activity.
> Evidence, safety and data-confidence requirements remain in force.

> **What this is.** The single living doc for the Phase-2 mobile app: the design law,
> every data point the backend serves, how each one becomes *health understanding*
> (not a number on a grid), the screen-by-screen plan, and a build checklist. Edit it
> as the plan moves. It supersedes scattered per-screen notes; where it conflicts with
> an older note, this wins.
>
> **Status (2026-07-17):** backend complete + live (Phase 1 + Phase 6). `apps/mobile`
> is **empty** — this is greenfield. Nothing here is built yet; this is the spec to
> build against.

---

## 0. The one rule this whole app answers to

**Show people their health, not their data.**

A number on a card is data. "Your resting heart rate is 3 bpm above your own normal,
which usually tracks a night of short sleep — it'll settle" is health. The difference
is *framing, baseline, mechanism, and confidence*. Every screen in this app earns its
place by making a measurement *mean something* to the person looking at it.

This is not a slogan — it decomposes into rules the backend already enforces and the
app must honor:

1. **Never a bare number.** Every value ships with its personal baseline (median ± MAD),
   its direction, and — for any interpretive claim — a cited research note. The backend
   already attaches `median_30d`, `z`, `anomalous` to metric cards; the app must render
   the comparison, not just the value.
2. **Confidence is part of the answer.** When data is thin, the *copy changes* — it does
   not hide. "HRV trend unclear — only 4 nights of data" beats a confident-looking line.
   The backend exposes this everywhere (see §6); the app must surface it, never swallow it.
3. **"Not enough data" beats a guess.** Withheld states are first-class UI, not error
   states. VO₂max with too few RHR days shows "Insufficient data — need 3+ nights", not a
   fabricated estimate.
4. **Show the breakdown, never the black box.** A summary score is allowed *only* when its
   components are shown beside it. Recovery (0–100), sleep-health (0–4), biological age —
   each always renders its per-factor breakdown. (This is also the no-composite rule, §2.)
5. **Frame, don't judge.** The primary user is a genuine ~3.7h chronic short sleeper
   (real data — the reason this app exists). "Bad" numbers are shown honestly and
   supportively — the deficit is never hidden, never alarmed, never sermonized. Meet the
   person where they are. Every domain screen must degrade gracefully for someone whose
   numbers are far from textbook.
6. **North-star per domain.** Don't dump metrics. Each screen organizes around the *one
   lever that matters* and shows the gap + what closing it buys: VO₂max for fitness, the
   "Tonight" lever for sleep, the recovery band for the day's ceiling. Comprehension is
   knowing *which* number matters and *why*.
7. **The chart is the explanation.** Small charts are interactive (drag → crosshair +
   value bubble) so people read their own data directly instead of opening a sheet.

---

## 1. Binding UI/UX law (already decided — carry forward, do not relitigate)

These are settled from prior feedback and CLAUDE.md hard rules. They are constraints, not options.

| Rule | What it means | Source |
|---|---|---|
| **Scroll = reveal once** | Every scrollable screen with animated charts uses `ListView.builder` + a reveal-once wrapper (unique id prefix per screen), or charts replay their animation on every scroll-back. Flagged twice by the user. | CLAUDE.md, `feedback_scroll_reveal_once` |
| **No card-in-card** | Lists (recs/findings/logs) = one outer card with hairline `divide-y` rows. State accents go on a thin left border or content opacity, never a nested container. | `feedback_no_card_in_card` |
| **No composite without breakdown** | Never invent a single 0–100 readiness/strain/body-battery. Summarize only as a tally ("2 favorable, 1 unfavorable") or a directional phrase — *unless* the per-component evidence renders alongside. Approved exceptions (do not re-flag): Recovery 0–100, Sleep-health 0–4, Biological age, Strain 0–21, Sleep Performance % — each always shown with its breakdown. | `feedback_no_composite_score` |
| **Honest color** | Score strips use a **monochrome opacity ramp, not red/amber/green**. Traffic-light coloring reads as judgment. Status colors only for genuine status (illness flag, sync stale), never decoration. | `project_sleep_page` |
| **Evidence-first** | No interpretive number without its evidence label + inline citation. Descriptive personal-baseline stats don't need one; interpretive claims do. | `feedback_evidence_first` |
| **Empty states, not "—"** | Graceful "no data yet / here's how to get it" degradation. Drop metrics that don't exist rather than showing a sparse grid of dashes. | `project_activity_tab` |
| **Tone** | Truth over flattery, always data + note grounded, expert + warm, no hype/emoji, always leads toward the next achievable improvement. | `feedback_coach_persona`, `docs/COACH_PROMPT.md` |

---

## 2. Information architecture (approved direction)

**5 tabs + Coach FAB + Profile route.** Stable across the blueprint and prior app notes.

```
Today · Sleep · Activity · Insights · Actions        [tabs]
   └─ Coach FAB (floating chat, on Today)
   └─ Profile (right-slide route off the Today avatar — not a tab)
```

- **Today** — the daily snapshot: where do I stand right now, what should today look like.
- **Sleep** — last night + the one lever to improve tonight + the honest 4-dimension picture.
- **Activity** — fitness organized around VO₂max as the longevity north-star.
- **Insights** — "what's actually working for you" (outcome ledger; premium; empty until challenges finish).
- **Actions** — adopt-a-commitment / challenges (premium).
- **Coach** — grounded chat, tool-calling, cites or says-so.
- **Profile** — identity, body (re-derive on change), appearance, data & sync.

Screens must be thin — modular `features/` tree over shared `core/`/`shared/`. No monster files.

---

## 3. The datapoint catalog → how each becomes understanding

This is the heart of the doc: every data point the backend serves, grouped by the screen
that owns it, with the *presentation intent* (how it turns into health, not data). Field
names are the real contract (golden fixtures in `packages/contracts/snapshots/`).

### 3.1 TODAY — `GET /api/today` (+ AI daily action, warmed nightly)

The snapshot. Organized top-to-bottom as: *where do I stand → what does today look like → the numbers behind it.*

| Data (field) | What it is | How we make it *health* |
|---|---|---|
| `recovery` + `recovery_score` (0–100) + live `readiness` | Evidence-weighted recovery (HRV 0.42 · RHR 0.28 · sleep 0.20 · RR 0.10) vs personal 42-day baseline; readiness decays today with strain | **Hero.** Band (high≥67/mod≥34/low) sets the day's *intensity ceiling*. Always render `flags.factors` breakdown + the deterministic guidance line. Illness flag overrides the guidance text, never the number. Null without HRV or RHR → "building your baseline". |
| `action` (str\|null) | The daily coaching one-liner | The single "what to do today" line. **Premium** (teaser 1×/7d free). `null` until warmed → show nothing, never a spinner. |
| `illness_flag` | RR/skin-temp/HRV deviation, `severity`, `framing` (deterministic) | Safety-critical, **free**. Render the `framing` text as-is (rule-based, not LLM). Quiet card when present, nothing when absent. Auto-clears after 2 days. |
| `metrics[]` (RHR, Steps, Active/Total cal, BMR, Distance, Weight) | Each: `value`, `unit`, `median_30d`, `z`, `anomalous` | The comprehension unit: value + **delta badge (z vs your normal)** + median + interactive mini-chart. "Anomalous" (|z|≥2) is a quiet flag, not alarm. Weight has no baseline (z null) — show plainly. |
| `sleep_health` (0–4) | 4-dim score + per-dimension points + cutoffs | Slim gauge → deep-links to Sleep. Never the bare 0–4; show the 4 ✓/✗ with cutoffs (see §3.2). |
| `last_sleep` + `last_sleep_extras` | Last night TST, stages, + overnight SpO₂/RR/skin-temp/HRV | Compact "last night" card → Sleep tab. Physiology row only where values exist. |
| `mvpa` | today/week min vs 150 target, moderate/vigorous split | "This week's movement" with the gap to 150. → Activity. |
| `vo2max` | Jurca estimate + `see_ml_kg_min` (±band) + median-for-age + trend | Fitness headline → Activity. Always show the ± band; **withheld** state when gated (§6). |
| `cardio_load` | Daily TRIMP + strain 0–21 + zones | Training load → Activity. |
| `sleep_debt` | need/debt/performance% over 14 nights | The short-sleeper's honest number: deficit shown, framed recoverable, never capped-to-hide, never alarmed. |
| `biological_age` | Gompertz estimate + `contributions[]` + disclaimer | Motivational, **always** with per-lever breakdown + the "not clinical" disclaimer. Candidate for its own detail screen (contributions are rich). |
| `today_hr_series` | Hourly HR (avg/min/max) | 24h HR chart — the day's physiological arc. Interactive. |
| `today_stress_series` | Hourly stress (avg/max/n) | Intraday stress; `n` is the confidence. Empty → hide. (Stress UI reframe + RR-interval work is a Phase-2 track.) |
| `today_step_buckets` | 15-min steps/distance | Activity texture of the day. (`calories` per bucket is always 0 — don't show.) |
| `data_health` | Per-feed freshness + overall sync recency | **The trust card.** Renders *nothing* when fresh; a quiet card when stale. This is mechanism #2 made visible. |
| `routine` | open fast, meditation, workouts, logs summary | "What you did today" — logged behavior, not sensor data. |
| `top_findings[]` (≤5) | Personal correlations (effect size, q-value, note ids) | The strongest honest motivator: "when your MVPA rose 20%, HRV followed ~10 days later." Personal cause-and-effect. |
| `recommendations[]` | Job-authored rec rows (action/rationale/effect/grade) | **Premium** (locked card free). Cite-or-drop; each carries `evidence_grade` + note ids. |
| `sparklines` | 14-day series per slot | Feed the mini-charts. Note GAP slots (`sleep_score`, `stress`, `pai_total`) are always empty — don't design around them. |

### 3.2 SLEEP — `GET /api/sleep`, `/sleep/health_score`, `/sleep/consistency` (+ `/sleep/insight`, `tonight`)

**North-star: the one lever to improve tonight.** Then the honest picture. Designed *for* a chronic short sleeper.

| Data | What it is | Presentation intent |
|---|---|---|
| `tonight` (on `/sleep/consistency`) | The single highest-leverage lever, picked **deterministically** (wake_anchor → bedtime → duration → consistency → maintain) + target clock time + adherence count | **Headline "Tonight" card.** Facts are deterministic (free); only the coaching prose is LLM (premium, cached/day, deterministic fallback). A free user still sees the lever + target time. |
| `nights[]` | Per night: TST, stages, stage timeline, 4-dim points, SRI, HRV, RHR, efficiency, midpoint, physiology (SpO₂/RR/skin-temp) | 30-night tappable strip (**monochrome ramp, not RAG**). Per-night detail: stage timeline + HR overlay + physiology row. **Do NOT show nightly stage-% trends** — wearable staging is too noisy (Chinoy 2021); aggregate weekly + caveat if built. |
| 4-dim health score | `sleep_health_score_4dim` (0–4) = duration (Cappuccio) + efficiency (AASM) + timing (Buysse) + regularity (Windred SRI) | **Always** the per-dimension ✓/✗ with *value · cutoff · citation*, plus the "no 0–100 score" footer. Timing dimension needs a **chronotype "skip this" toggle** for non-standard sleepers. |
| `sleep_debt` | need/debt/performance%, 14-night | Debt bars with target markline. Honest + supportive; "even +30 min helps." |
| SRI (`sleep_regularity_index`) | −100..100, Phillips/Windred, **null until 7 days** | Consistency chart. The null-until-7-days *is* the confidence gate — show "building" not zero. |
| `naps[]` | strap nap sessions ≥5 min | Strategic nap guidance only when deficit ≥60 min, no nap logged, early afternoon. |
| `findings[]` (≤10) | Sleep-related personal correlations | "What moves your sleep" — personal cause/effect. |
| `/sleep/insight` | AI 4–6 line analysis + citations + `grade_floor` | **Premium** insight card; `grade_floor` is the evidence-floor confidence. |

### 3.3 ACTIVITY — `GET /api/activity` (+ `/activity/insight`, workouts)

**North-star: VO₂max as the longevity lever** (low CRF = strongest modifiable mortality predictor). A motivating screen, not a data dump.

| Data | What it is | Presentation intent |
|---|---|---|
| `vo2max` | Jurca non-exercise estimate + `see_ml_kg_min` (±5.6) + `median_for_age` + `delta_from_median` + `trend_90d` + `submax` (GPS method) | **Hero.** Gauge + gap-to-median bar + "what it buys" + 90d trend. Always the ± band. Two methods (non-exercise + GPS submax) shown honestly, not merged. |
| `fitness_plan` | current → `projected_12wk` (bounded +2..+5) + weekly Rx (zone2/vilpa) + adherence | **12-week plan** card. Projection *labeled a projection, never a promise.* |
| `mvpa` | week min vs 150 + moderate/vigorous | "This week" with a gap-closing action. |
| `steps` / calories / `distance` | daily + trend | Supporting, framed vs the week's target. |
| `cardio_load` | daily TRIMP + `strain` 0–21 + zone minutes + `acwr` | "Train smart": strain + acute:chronic ratio (`acwr.state`: detraining/optimal/caution/overreaching) + HR zones + energy. |
| `workouts[]` | device workouts ≥10 min | Preview 4 + "View all". Detail screen below. |
| Workout detail (`/activity/workout`) | HR series, zones, `avg_pct_hrmax`, `intensity`, pace/speed, `trimp`, `hr_drift` | Effort hero (avg-%HRmax gauge) → opt-in "Coach review" (LLM fires only on tap) → only-metrics-that-exist → HR-over-time → time-in-zones. |
| GPS (`/workout/gps`, `/{track_id}`) | Track list + full detail (points, ele, pace, submax VO₂max) | A whole sub-feature: route map + elevation + submax VO₂max per run. |

> **Strength** was deliberately removed from Activity (can't derive from the strap). A 2-tap manual entry is the documented path if revisited — do not add a sparse strength grid.

### 3.4 INSIGHTS — the outcome ledger (**premium**)

"What's actually working for you." Outcome cards: before → after, completed/dropped, downstream chips. Empty until challenges finish. Depends on the Actions system, so effectively premium. The per-metric anomaly flags stay free on their cards; this curated ledger is premium.

### 3.5 ACTIONS — challenges / commitments (**premium**)

Adopt-a-commitment layer, up to **3 active**, targets calibrated to *the user's own baseline* (not textbook ideal), progress rings, projection-on-adopt, measured before→after, recovery-aware streak protection, full outcome-ledger learning loop. Detail is a **bottom sheet** (dual-mode suggested/active), not a screen. The whole system is premium — design an honest locked/teaser state for the free tier's 5th tab, not a hidden tab.

### 3.6 COACH — `POST /api/coach` (**premium**, teaser 1 q / 7 days free)

Full-width bottom sheet, message bubbles, citation chips, typing dots, persisted multi-chat. Tool-calling backend (query_metric, compare_event, sleep_consistency, log_entry, get_knowledge). Returns `reply`, `citations[]`, `personal_findings[]`, `grade_floor`, `validated`, `refused`. `grade_floor` is the **weakest** grade among the cited notes (`null` when nothing gradeable was cited) — render it as the answer's evidence-confidence chip, same semantics as the insight cards. Persona fixed in `docs/COACH_PROMPT.md` (truth over flattery, mechanism + next step, cite-or-say-so, grade-calibrated certainty, meets the 4h-sleeper where they are). Ships the honest fallback rather than an ungrounded answer — *this is the product's promise; render the fallback with dignity, not as an error.*

**The questions-left meter (#116) belongs on this screen, and it is a subscriber's meter — NOT a paywall.** `GET /api/entitlement` carries `included`: one entry per capped feature with `limit`, `used`, `remaining`, `window_days`, and (only once spent) `resets_at` + `retry_after_s`. Render the coach's entry quietly beside the composer — *"17 of 20 questions left this month"*, and at zero *"all 20 used — the next opens on the 14th"*, from `resets_at`. Design rules that are not negotiable:

- **No upgrade button, ever, on this meter.** The owner already paid. The server deliberately omits the `upgrade` URL from a capped subscriber's 402 for the same reason; a meter that sprouts a subscribe button undoes that.
- **Never render it from `locked`.** `locked` is the *upgradeable* list and is empty for a subscriber by design. `included` is empty for a **free** owner — they were never sold twenty of anything, and "0 of 20" at somebody with no access is an upsell wearing a meter's clothes. If `premium` is false, show the locked card, not a meter.
- **A feature absent from `included` is uncapped, not exhausted.** The insight cards and the daily action emit no entry because they have no limit. Do not default a missing entry to zero.
- The number exists because a stated limit nobody can observe until it refuses them is most of the way back to "unlimited (fair-use)" (`PRICING.md` §0). Hiding the meter until it hits zero would reintroduce exactly that.

### 3.7 PROFILE + logging

- **Profile** (`/api/profile`) — name, height, sex, dob, weight. Body edits **re-derive** age-dependent science. dob is epoch-ms at owner-local midnight (the tz-correct codec — do not reinvent).
- **Manual logging** (`POST /api/log`) — instant: caffeine (mg), alcohol (units), water, food, med, symptom, mood, habit; duration: meditation, exercise; special: weight, fast_start/fast_end. Fasting surfaced via `fast`, not the feed. Logging is **free** (never paywall input) and feeds the correlation engine that produces personal findings.

---

## 4. The tier split, applied to screens (PRICING §1a — authoritative)

**Free = the numbers + the evidence. Premium = the interpretation + the coach + the guidance.**
**Never paywall data or safety.**

| Surface | Free | Premium |
|---|---|---|
| All metrics, charts, **full history**, trends, sparklines | ✓ | ✓ |
| Personal baselines + per-card anomaly flags | ✓ | ✓ |
| Recovery score + readiness + **deterministic** guidance line | ✓ | ✓ |
| **Illness early-warning** (deterministic, safety-critical) | ✓ | ✓ |
| Data-health / confidence chips | ✓ | ✓ |
| Manual logging · workouts · GPS · export · research notes | ✓ | ✓ |
| Personal findings (correlations/cutoffs) | ✓ as plain stats | ✓ coach explains & acts on them |
| **AI coach** | — (no AI in free) | ✓ **20 questions / rolling 30 days** |
| **Daily action line** | — (no AI in free) | ✓ daily, uncapped |
| **Daily recommendations** (1–3) | locked card | ✓ |
| **AI insight cards** (sleep/activity/metric/workout) | locked card | ✓ |
| **Challenges / Actions** + **Notable feed** + coach-companion | — | ✓ |

**Design consequence:** every AI surface needs a designed *free / locked* state. The deterministic pieces (Tonight lever + target, recovery guidance, illness framing) stay free even on premium screens — those screens must degrade to "the facts without the generated prose," never to blank. **There is no teaser state to design any more** (2026-08-02): a free owner is refused on the first call, so the free state IS the locked state.

**A second locked state now exists and is NOT an upsell**: a paying owner who has used all 20 coach questions gets the same 402 shape, with `used`/`limit`/`resets_at` and *no* `upgrade` URL. It must read as "the next one opens on the 22nd", never as a subscribe button — the server deliberately omits the upgrade link so the app cannot render one by habit.

Pricing (decided 2026-08-02, `PRICING.md` §0): **$6.99/mo · $69/yr**, lifetime dropped. The anti-Whoop brand ("we don't hold your data hostage") means the **free tier must stay genuinely excellent** — it is the whole tracker, and it now costs us $0 to give away.

---

## 5. The confidence system (mechanism #2, made concrete)

The "every number carries its confidence" rule is not one widget — the backend expresses it through many signals the app must surface:

- **Per-card:** `median_30d` + `z` + `anomalous` (Today metrics, `/api/notable`).
- **Freshness:** `data_health` — per-feed `status`/`age_h` + overall sync recency. Renders nothing when fresh.
- **Withheld gates:** VO₂max produces *no row* when RHR is too thin/out-of-range (reasons logged) → "Insufficient data — need 3+ nights", never a fake number. SRI null &lt;7 days; ACWR null &lt;7 days; recovery baselines need ≥5 points; consistency needs ≥3 nights; metric-insight empty &lt;3 points.
- **Explicit bands:** `see_ml_kg_min` (±5.6 on VO₂max), `r2` (submax/GPS), `n_samples`/`q_value` (findings), `n` (hourly stress).
- **AI trust:** `validated`, `refused`, `grade_floor` (weakest cited grade), `citations[]`. Only validated output cached; unvalidated → honest fallback.
- **Evidence grades** (from the corpus): Established → plain · Probable → hedge · Emerging → flag · Contested → present as debated. The app's copy calibration must match the grade.

**Rule for the app:** a thin signal changes the copy and shows the gate reason — it never renders a confident-looking value it doesn't have.

---

## 6. Dead data worth surfacing (backend computes, no home yet)

Low-hanging richness — the backend already produces these; they just have no screen:

- `biological_age.contributions[]` — full per-lever breakdown → deserves its own detail screen.
- `respiratory_rate_sleep`, `spo2_overnight(_min)`, `skin_temp_c` — canonical daily metrics with full history via `/api/history`, but no dedicated Today cards (sparkline / sleep-physiology only). Skin-temp drives illness detection but has no trend surface.
- `cardio_load` internals — `edwards_tl`, `hr_minutes`, zone minutes — buried in flags.
- Correlation `findings` — rich (pairwise-lag, event effects, personal cutoffs) but only ≤5/≤10 surfaced; no dedicated "patterns" browse.
- `pal` (activity level), `stride_m` — computed, never shown.
- Historical intraday (hr/steps/stress) — today-only; no history endpoint yet (would need backend work).

---

## 7. Open decisions (need a call before visual build)

1. ~~**⚠ Brand accent — genuinely unresolved.**~~ **CLOSED 2026-08-04.** Neither option in this question survived. The owner approved a new design (`Healthee.html`) and ruled: *"the colors and fonts all we will keep from new."* The app is **indigo `#5145e5` / `#8f87ff`, light default**, transcribed verbatim in `docs/APP_DESIGN_BRIEF.md` §2 and implemented in `apps/mobile/lib/core/theme/palette.dart`. The face was Instrument Sans and is now **Manrope** (owner, 2026-08-05 — see the type note in brief §2).
   Two corrections to what this item used to say, because both were still being cited:
   - The forest-green "warm editorial" system is **explicitly rejected** (brief §2: no serif, no paper texture, no beige).
   - The landing page is **no longer v3 iris/indigo**. It is **v5 "The Ledger"** — warm paper, clay accent (`apps/landing/DESIGN.md`). So the app and the landing **deliberately diverge**, and any doc claiming the app's indigo "matches the landing page" is wrong.
2. **Onboarding / first-run / empty-state experience** — not designed anywhere. Greenfield. A brand-new user gets ~60 days of back-history on first sync, then accumulates; the first-run must handle the "still building your baselines" period honestly (ties directly to §5).
3. **Premium paywall UI** — the gating logic (6.6) is unbuilt and no locked/teaser states are designed. Needed before any AI surface ships.
4. **Stress card reframe + RR-interval BLE** — flagged for Phase 2, not designed. The current device stress is framed honestly-but-thin; RR-interval extraction would give a real HRV/stress signal.

---

## 8. Build tracker

Legend: ✅ done · 🟡 designed, not built · ⬜ greenfield (design + build)

### Backend (the data source) — ✅ complete & live
- ✅ All read endpoints, science layer, AI surfaces, confidence gates (Phase 1 + Phase 6, prod `fa5aaea`).

### App scaffold
- ⬜ Flutter app scaffold: `core/env.dart`, single API client via provider, typed models at the data boundary (no raw maps in feature code), `features/` module tree, `nav.dart` (5 tabs + Coach FAB), Profile route.
- ⬜ Shared: charts (interactive crosshair), reveal-once scaffold, stale banner, ai_insight card, metric_info, locked/teaser card.
- ⬜ Design-system decision (§7.1) then the theme (light default per landing law, or green — TBD).

### Screens
- ⬜ **Today** — recovery hero · daily action (premium) · illness flag · metric grid · sleep-health slim · last-night · mvpa/vo2max/cardio-load previews · 24h HR · intraday stress · data-health · routine · findings · recs (premium).
- ⬜ **Sleep** — Tonight lever (free facts / premium prose) · 30-night monochrome strip · per-night detail · 4-dim breakdown + chronotype toggle · debt bars · SRI · naps · insight (premium).
- ⬜ **Activity** — VO₂max hero · 12-week plan · this-week (mvpa/steps) · train-smart (strain/acwr/zones/energy) · workouts + detail · GPS sub-feature · insight (premium).
- ⬜ **Insights** — outcome ledger (premium; empty until challenges).
- ⬜ **Actions** — challenges bottom-sheet system (premium) + honest free-tier locked state.
- ⬜ **Coach** — grounded chat FAB (premium + teaser).
- ⬜ **Profile** — identity · body (re-derive) · appearance · data & sync · logging.

### Cross-cutting
- ⬜ Confidence system rendering (§5) — the single most important "health-not-data" mechanism.
- ⬜ Free / locked / teaser states on every AI surface (§4).
- ⬜ Onboarding / first-run (§7.2).
- ⬜ On-device 60-day tier + offline-first rendering (blueprint Phases 3–4; designed, unbuilt).

---

## 9. Source map

Approved IA/vision: `project_modular_companion_blueprint`, `docs/blueprint.html` (IA authoritative; its auth/tenancy is superseded by `docs/MULTI_USER.md`), `docs/ARCHITECTURE.md`.
Per-screen design: `project_activity_tab`, `project_sleep_page`, `project_sleep_health_score`, `project_recovery_sleep_vo2max_features`, `project_whoop_level_metrics`, `project_app_v2_rebuild`.
Tone/coach: `docs/COACH_PROMPT.md`, `docs/COACH_ROADMAP.md`, `feedback_coach_persona`, `feedback_health_analysis_approach`, `feedback_evidence_first`.
UI law: `feedback_scroll_reveal_once`, `feedback_no_card_in_card`, `feedback_no_composite_score`.
Tier split: `docs/PRICING.md` §1a. User constraint: `user_chronic_short_sleep`. Data contract: `packages/contracts/snapshots/`.
