# Whole-codebase review — consolidated findings

> **Revalidated 2026-09-23:** every CRITICAL (C1–C3) and HIGH (H1–H6) finding below is
> fixed in current code; the evidence per finding is in `docs/REVIEW_PLAN.md`
> ("Revalidated review findings"). MEDIUM and LOW were not rechecked — treat them as
> unverified, not as open.

**Date:** 2026-07-17 · **Ref:** `main` @ `51bc30d` · **Method:** seven parallel dimension
agents (security & tenancy, correctness & integrity, honesty contract, error handling &
operability, test quality, performance, standards & structure), each running the
end-to-end review prompt with refute-before-report. All work was static analysis plus
execution of pure functions only — **the shared DB and pytest were never touched**, so
every "survives the suite" claim is from reading tests, not running them. Findings marked
**[lead-verified]** were independently re-checked by the lead against the source.

**Headline:** the tenancy/auth layer is genuinely clean — the security agent attacked the
AST guard, RLS, the JWT path, and the legacy token and every candidate was refuted by an
existing guard or mutation test. The real exposure is elsewhere: **the honesty contract's
enforcement layer has three verified holes**, one cross-tenant write survived all of
Phase 6's guards, a shipped feature is silently dead, and the `/api/today` hot path has
two mechanisms that degrade monotonically with history and one that can deadlock the pool.

---

## CRITICAL

### C1 · Cross-tenant write: cutoff findings persist under the sentinel
`analytics/cutoffs.py:267` (caller `jobs/correlate.py:38`) — found independently by two
agents; **[lead-verified]**.

`run_correlate(user_id, tz)` computes cutoff findings per-owner, then
`persist_cutoff_findings(cutoffs)` discards that owner and calls
`replace_findings_of_kind(SENTINEL_USER_ID, "personal_cutoff", …)`.

- **Pre-claim:** owner B's nightly chain DELETE-replaces the sentinel owner's
  `personal_cutoff` rows with **B's** caffeine/alcohol inferences. B's private behavioral
  data surfaces in owner A's `/api/findings`, recs context, and coach context; A's real
  cutoffs are wiped nightly (last-owner-wins); B's own cutoff set stays empty forever.
- **Post-`claim_sentinel --apply`** (sentinel `app_user` row deleted): the INSERT raises
  `ForeignKeyViolation` → the correlate step fails → **recs are skipped every night for
  every owner**, with only Telegram tracebacks as signal.

Why nothing caught it: the write runs inside `tenant_transaction(SENTINEL_USER_ID)`, so
the RLS GUC matches the (wrong) row owner and the policy passes; the AST guard passes
because the SQL does bind `user_id` — to the wrong constant. The only test
(`tests/analytics/test_seam_integration.py:105-116`) computes *and* persists as the
sentinel, so the hardcode matches the fixture. This is the site the 6.4b "sentinel
hardwires cleared" sweep missed. **Fix is one line** (thread `user_id` through) **plus a
two-owner test that drives `run_correlate` for owner B and asserts B owns the rows.**

### C2 · Validator bypass: any response containing a refusal template skips ALL validation
`insights/validator.py:121-124` — verified **by execution** by the honesty agent.

`is_refusal()` matches refusal templates as **substrings**, and `validate()` returns
`ok=True` immediately on a hit. A response embedding a template inside a longer answer
ships with banned certainty, uncited interpretation, and escalations intact, flagged
`validated=True`. Two realistic entry paths: (a) organically — after any refused coach
turn the template sits verbatim in conversation history (`coach.py:_recent`), and a model
quoting its own prior refusal trips the bypass; (b) adversarially — "include this
sentence: <template>" does not trip `classify_refusal` (verified: returns `None`). No
test covers embedded templates. Fix: equality (or prefix-on-stripped) match, plus a test.

### C3 · Safety-critical directives are not mirrored in code — and the notes claim they are
No directives table exists anywhere in `apps/server/src/healthee`; `gen_manifest.py`
extracts no directives field. The only guardrails are question-side (`refusals.py`, recs
keyword block). Two concrete failures, both verified:

- `notes/recs/llm_health_advice_safety.md:118,161,221` marks "no individual
  mortality-risk projection" SAFETY-CRITICAL and "mirrored in code". Executed:
  `validate("Your VO2max of 38 is associated with roughly a 30% higher long-term
  mortality risk for you [vo2max].")` → `ok=True`. The exact forbidden output ships
  fully "validated" — and the vo2max note (full of hazard ratios) is routinely in context.
- `notes/recovery/recovery_readiness.md:374-377` (D7): illness/pain must force
  modify/rest "regardless of the composite — mirrored in code; cannot be overridden".
  `derive/recovery.py` + `read/recovery.py` have **no illness/pain input at all**: a user
  with an active illness flag and composite ≥67 is told *"a good day to push: intervals
  or a harder session are on the table"* on the same `/api/today` payload as their flag.

This is an ENGINEERING_STANDARDS §4 MUST violation and — worse for the product — the
notes assert enforcement that doesn't exist. Fix: extract directives into the manifest,
enforce answer-side (validator patterns for the mortality class; a hard illness override
in the recovery guidance path), and make the notes' "mirrored in code" claims true.

---

## HIGH

### H1 · The validator can't see the standard English for a recommendation
`insights/validator.py:36-63,127-134` — verified by execution. `_INTERP_RE` lacks
"should", "aim for", "try", "shows/means/reflects":
`"You should cut caffeine after noon. Your deep sleep shows real improvement."` →
`ok=True`, zero citations. Additionally `_sentences()` drops lines starting `|` or `>`,
so interpretive content in markdown tables/blockquotes is never sentence-checked (both
constructions verified `ok=True` uncited). This is the everyday silent-wrongness path on
every surface, coach included.

### H2 · `/api/today` action line (and sleep `tonight`) can never populate in production
`insights/coaching.py:51-74` — **[lead-verified]**: `warm_daily_action` /
`warm_sleep_tonight` have zero callers outside one test file; the chain runs exactly
correlate → recs → briefing (`jobs/chain.py:140-162`). Routers correctly read only the
per-day cache — which nothing ever fills. Every real request gets `action: null`,
forever, with no surface reporting the generation as missing. MULTI_USER §12.3 lists
"daily-action" as part of the nightly generation; the warm step needs to join the chain.

### H3 · `/api/today` intraday queries scan the user's entire history per request
`read/today_series.py:121-124,136-142,160-163` — the three intraday queries filter
`sample` with non-sargable `(ts AT TIME ZONE %s)::date = %s` and **no ts range**: the
date predicate can't bound the `(user_id, metric, ts)` index and defeats chunk exclusion,
so every chunk of the user's hr/steps/stress history is visited to keep ~1,440 rows.
After one year, hr alone filters ~525k entries — ×3 queries, on every `/api/today`,
against a 100 ms p95 budget, degrading monotonically forever. The correct sargable idiom
already exists in-repo (`derive/_common.py:92-95`, `read/sleep_page.py:203`); fix is
computing the day's UTC bounds in Python and binding `ts >= %s AND ts < %s`.

### H4 · Pool self-deadlock: hot endpoints hold one connection while borrowing a second
`api/routers/today.py:27` holds `tenant_transaction` across `today_snapshot`, inside
which `compute_baselines` (`analytics/baselines.py:91`) and `get_significant_findings`
(`analytics/finding.py:130`) each open a **second** `tenant_transaction` from the same
hardcoded 10-connection pool (`core/db.py:79`) — **[lead-verified]** nesting. Same shape
on `/api/sleep`. With ~40 permitted in-flight sync handlers and a single worker, 10
concurrent `/api/today` requests each hold #1 and block on #2 → zero free connections →
collective stall, then a burst of PoolTimeout 500s at t+30 s. Below the threshold it
halves effective pool capacity. Fix: thread the router's cursor through (the
`build_today_reads(cur, …)` seam already exists) so a request uses exactly one connection.

### H5 · Data-trust card computes grouped `max(ts)` over the whole sample table
`read/recovery.py:256-263,284` — `SELECT metric, max(ts) … GROUP BY metric` can't use
min/max index descent, and TimescaleDB SkipScan is disabled on the app role (the 0008
workaround), so the GroupAggregate reads all index entries for the user's 6 feed metrics
(~1.3M+ after a year) on every `/api/today`. The comment "one grouped scan instead of a
probe per metric" optimized backwards: six `ORDER BY ts DESC LIMIT 1` probes are ~O(log n)
each. The bare `max(ts) WHERE user_id` at :284 walks backward through *other tenants'*
rows for a lapsed tenant.

### H6 · Biological-age math has no known-value test that touches production code
`tests/analytics/test_biological_age_math.py:37-54` — the "known-value" test asserts
against **its own local replica** of the formula; the production hazard math
(`analytics/biological_age.py:56-57,103,124,141`) has zero value assertions anywhere.
Surviving mutations include `0.85 → 0.7` in the fitness hazard, sleep breakpoint `7 → 8`,
and even `chrono + dage → chrono - dage` (the composite value is never asserted; the
integration test checks sign/structure only; the contract bed compares types only). A
headline actuarial number the product surfaces, effectively unpinned — the exact failure
shape the Phase-6 mutation-testing lesson warned about. Standards §1 MUST.

---

## MEDIUM

- **M1 · Rec evidence grades are the model's self-declared claim** —
  `jobs/recs.py:180-194` + `read/today.py:155-168`: `_rec_ok` never cross-checks
  `evidence_grade` against `manifest.grade_of()` of the cited notes, and legacy's grade≥2
  citation whitelist was dropped. A rec citing a **Contested** note (3 exist) can ship
  labeled grade 3/Established; if the inline citation differs from `research_note_ids`,
  wording calibration never sees the Contested note. Violates the safety note's "displayed
  grade is the cited note's grade; nothing below grade 2 ships".
- **M2 · Five read-layer citations use stale alias ids that resolve nowhere** —
  `read/activity.py:37,39`, `read/fitness.py:71,130,324`, `read/recovery.py:167,236`:
  `vo2max_fitness_mortality`, `cardio_load_trimp`, etc. exist only as manifest *aliases*;
  `research_summaries.json` (the mobile ⓘ asset) and `manifest.by_id()` are canonical-id
  only, so the card's tap-ⓘ chain dead-ends. Already frozen into contract snapshots.
- **M3 · Calorie integrator mis-integrates DST days** — `derive/energy.py:66-73`:
  `_tee_met` hardcodes `range(1440)` while `_day_bounds_utc` yields 23/25-hour local days;
  fall-back days drop ~1 h of real MET (undercount), spring-forward adds ~1 h of phantom
  sedentary. Latent until a DST-zone user onboards — which is what Phase 6 built for.
- **M4 · `derive_vo2max` ignores the note's own withhold directives** —
  `derive/vo2max.py:40-73`: the note requires skipping on RHR 7-day MAD > 8 bpm and
  out-of-range age (20–70)/BMI (16–45); code checks only ≥3 RHRs and RHR 40–100, and the
  read layer surfaces the stored value verbatim. Writes a confident number the corpus
  says must read "insufficient data".
- **M5 · No LLM timeout/retry policy anywhere** — `insights/client.py:87,121`: SDK
  defaults (~600 s × retries) apply; cold-cache insight generation runs on the request
  thread (worker starvation can fail `/healthz`), and the serial per-owner sweep
  (`jobs/scheduler.py:130-138`) stalls **every later owner's chain** by up to ~30 min per
  stuck call. One `timeout=`/`max_retries=` at client construction covers both.
- **M6 · `/api/sleep` N+1: one physiology query per night, `days` up to 365** —
  `read/sleep_page.py:168-187`: per-session `AVG` scans with **no metric filter** (each
  range-scans all tenants' rows in the window), 30 by default, 365 max; `main_sessions`
  also executes twice per request. A single joined/LATERAL query is expressible; the
  single-window version already exists (`sleep_extras.py:52-63`).
- **M7 · Contract snapshot checks can't see field removal inside lists** —
  `tests/contracts/shape.py:55-68` + `endpoints.py:38-49`: only *extra* keys fail;
  deleting `median_30d` from every `today.metrics` element stays green (no other test
  references it); a live `[]` conforms to any snapshot list; `workout`/`gps_detail`
  contract tests pass **vacuously** when the seed list is empty.
- **M8 · TRIMP implemented twice and already diverged** — `derive/cardio_load.py:99-100`
  clamps HR-reserve to [0,1]; `read/workout.py:128-136` has no upper clamp, so a sample
  above HRmax weights differently in daily vs session TRIMP. Both cite the same note.
  ONE-canonical-definition violation with live drift.
- **M9 · "Valid HR" filter: five sites, two semantics** — inclusive `BETWEEN 30 AND 220`
  in derive (`rhr.py:32`, `cardio_load.py:48`, `gps.py:92`) vs exclusive `> 30 AND < 220`
  in read (`workout.py:68`, `today_series.py:123`); HR exactly 30/220 counted by one
  layer, dropped by the other.
- **M10 · The choke-point docs lie** — `insights/grounded.py:10-13,74`: `allow_tools` is
  dead (never passed, never read, `noqa`'d as a "WP5b seam" though WP5 is merged), and the
  claim that the coach routes via `grounded_ask` is false — `coach.py:95` calls
  `client.complete` directly. The *protection* holds (coach reuses the refusal classifier
  + blocking validator), but the documented invariant doesn't match the code.
- **M11 · Metric-insight prompt mislabels the all-time median as "30-day median"** —
  `insights/surfaces.py:131-140` + unbounded `analytics/series.py:37-52`: the model echoes
  a mislabeled measured-fact number that ships as a descriptive sentence needing no
  citation. (The coach's `query_metric` windows correctly; only this site is unbounded.)

## LOW

- **L1 · §12.7 anti-invariant is operator-discipline only** — no `Settings` validator
  forbids `SIGNUPS_OPEN=true` while `REALTIME_INGEST_TOKEN` is set (`core/config.py:130-146`).
  One `model_validator` makes the MUST-NOT structural.
- **L2 · Failed Telegram delivery reported as step success** — `jobs/briefing.py:54-69`
  returns `{"ok": True, "sent": False}`; a revoked bot token stops all briefings with the
  chain green. Should be a failed/distinct step outcome.
- **L3 · Scheduler tick failure = silent crash-loop** — `jobs/scheduler.py:210-212`:
  `main()` has no supervision around `tick()`, and `docker-compose.prod.yml` gives the
  scheduler no healthcheck (only db/api have one).
- **L4 · One transient manifest read failure pins an empty corpus until restart** —
  `insights/manifest.py:62-74`, `analytics/notes.py:40-53`: `@lru_cache` caches the
  `OSError` fallback `()` forever; every insight degrades to the fallback on one WARNING.
- **L5 · CI runs UTC only** — `.github/workflows/ci.yml:71-81`: the repo's own two-TZ
  discipline (UTC **and** IST) has no CI leg; a new session-tz-sensitive read passes CI
  whenever UTC agrees.
- **L6 · CI has no failsafe that integration tests actually ran** — every DB-gated test
  skips silently via `_db_reachable()`'s blanket except; env drift converts the RLS/
  isolation proofs into green skips. A fail-on-skip or min-count check closes it.
- **L7 · AST guard checks `"user_id" in stmt` as a substring** —
  `tests/db/test_tenant_read_scoping.py:118-121`: projecting the column (or a comment)
  counts as scoped; `sql.SQL`-composed statements are invisible to the table regex. RLS
  backstops app reads; residual exposure is future admin-context code.
- **L8 · Baseline window anchors to `date.today()` (UTC), not owner-local today** —
  `analytics/baselines.py:89` — **[lead-verified]**; the exact anti-pattern
  `core/tenancy.py` documents eliminating. One-day edge shift near local midnight for
  callers that omit `end_date`.
- **L9 · LLM context builder defeats its own batching** — `insights/context.py:51-99`:
  ~80 pool checkouts/queries per `build_context`, including per-metric nested checkouts
  inside a held transaction (same hazard class as H4); `compute_all` loops the
  single-metric wrapper 20× instead of one `compute_baselines` call.
- **L10 · `workout_detail` runs identical queries twice** — `read/workout.py:39-41`:
  `cardio_load_payload` called back-to-back for `hrmax` then `rhr`; full `vo2max_payload`
  called just to extract `sex`.
- **L11 · Duplication/config oddments** — age calc ×3 (`derive/_common.py:98`,
  `jobs/recs_context.py:56`, `analytics/biological_age.py:51`); Tanaka HRmax ×2; Edwards
  zone bounds as magic numbers in `read/workout.py:87-89`; `SRTM_CACHE_DIR` read via
  `os.environ` at import and documented nowhere (`derive/dem.py:33`) — violating
  `core/config.py`'s own "no other module touches os.environ" invariant (with
  `core/knowledge.py:20` as second violator); the file-length gate excludes
  `packages/knowledge/tools/gen_manifest.py` by directory-name accident; standards §2
  layout omits the 17-module `read/` package; the prod compose scheduler comment still
  describes the pre-6.4c IST-timer design.

---

## Clean bills (what was attacked and survived)

- **Security & tenancy: no exploitable defect.** Attacked and refuted: AST-scanner
  bypass shapes (splits make it stricter, never blinder), RLS bypass via plain
  `transaction()` (every caller touches identity tables only), pool/GUC manipulation
  outside `core/db.py` (none), model-controllable tenant params in coach tools (none),
  legacy-token → minted-credential escalation (JWT-only dependencies block it), JWT
  alg/aud confusion (HS256 pinned, `sub`/`exp` required), injection via dynamic SQL
  (every fragment is an allowlisted constant or `sql.Identifier`), tracked-secret
  leakage, and 404-vs-403 id oracles. The RLS migration, app-role split, and the
  two-sided leakage suites all held under adversarial reading.
- **Mechanical standards gates:** no file > 400 lines (max 373); exactly the 3 known
  over-limit science functions, no fourth; import graph strictly downward; no dead
  modules (18 candidates all refuted).
- **Chain/sweep supervision** (per-owner failure isolation, retry budget, dedup markers),
  **ingest atomicity** (one transaction: upsert → derive → override), **exception
  hygiene** (no bare excepts; the three `except Exception` sites are supervised
  boundaries), **the RLS/app-role/leakage/anchoring test suites** (mutation-resistant by
  design — drop-policy, forced-owner, 25-h-apart-zone constructions all genuinely bite),
  **science known-value tests** other than bio-age (hand-computed values, byte-pinned
  legacy parity), and the **"not enough data wins" paths** across baselines, insights,
  coach tools, and recovery.

## Caveats

- Planner claims (H3, H5, M6) argue from Postgres/TimescaleDB semantics + the
  migration-defined index set, not observed `EXPLAIN` plans; volumes are arithmetic from
  minute cadence, not measured prod counts. Worth one EXPLAIN session on a throwaway DB
  before sizing the fixes.
- Honesty findings C2/C3/H1 were verified by executing the validator/refusal functions
  directly; end-to-end behavior with a live model was not exercised.
- C1's post-claim FK-crash path is inferred from the schema (FK + sentinel row deletion),
  not executed.

## Suggested order of attack

1. **C1** (one-line fix + two-owner test) — it's a live cross-tenant write.
2. **C2 + H1** together (validator hardening + tests) and **C3** (directives enforcement)
   — the product's one promise depends on these.
3. **H2** (add the warm step to the chain) and **H6** (pin the bio-age math) — cheap,
   high-value.
4. **H4 → H3 → H5** as one `/api/today` perf PR (thread the cursor, sargable day bounds,
   per-metric probes), then M5/M6.
5. The mediums fold naturally into existing tracks: M1/M2 into the honesty backlog,
   M3/M4 as science PRs with known-value tests, M8/M9 as a canonical-definition
   consolidation, M7/L5/L6 as a test-infra PR.

*Update the review prompt's suppression list (`docs/…` review doc) as these land — a
stale entry hides the next real finding.*
