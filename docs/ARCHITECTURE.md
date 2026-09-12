# Healthee — Target Architecture

Full blueprint with diagrams, the honesty contract, and the complete audit
findings: `docs/blueprint.html` (published copy:
https://claude.ai/code/artifact/c854d435-402b-471d-b308-d853f61b7a36).
This file is the working summary.

> ⚠ **`blueprint.html` predates Phase 6 and is not maintained.** It still
> describes the single shared bearer token as a thing that "blocks multi-user".
> Where it and this file disagree, **this file wins**; for tenancy specifically,
> `docs/MULTI_USER.md` wins over both.

## Where the detail lives (this file is the summary — don't duplicate it here)

| Subject | Owner doc |
|---|---|
| Multi-tenancy: identity, RLS, the app role, per-user jobs, the signup gate | `docs/MULTI_USER.md` |
| Grounding: the choke point, validator, output guardrails, retrieval, coverage | `docs/INTELLIGENCE.md` |
| Binding quality gates (sizes, errors, tests, performance budgets) | `docs/ENGINEERING_STANDARDS.md` |
| The deploy procedure, the one-time cutover, rollback | `infra/DEPLOY.md` |
| Restoring from a dump | `infra/backup/RESTORE.md` |
| Free/premium line + LLM cost model | `docs/PRICING.md` |

## One system, three tiers

```
Helio Strap ──BLE (RE'd Huami/ZeppOS)──▶ Mobile app ──POST /ingest/helio──▶ Server (FastAPI)
  sensors + firmware buffers              │ ble kit (auth·pager·parsers)      │ ingest → TimescaleDB
                                          │ local store (60d samples,         │ derive (science layer)
                                          │   400d sessions + dailies)        │ analytics (baselines·corr·
                                          │ device analytics (provisional)    │   anomalies·cutoffs·bio-age)
                                          │ sync engine ◀─GET /api/sync/down──│ insights (grounded LLM)
                                          └ offline-first UI                  │ jobs (supervised) · backup
                                                                              └ Telegram · OpenRouter
                        packages/knowledge (graded corpus) grounds BOTH tiers
```

- **Strap** is the sensor. Keep-on-device ACKs + per-metric watermarks make
  partial syncs safe and resumable (proven in legacy — port this design).
- **Mobile** is collector *and* analytical node: renders everything from local
  data instantly (provisional recovery score at wake-up), reconciles with the
  server after push. Offline = degraded (no LLM, no full history), never dead.
- **Server** is the canonical brain: full history, the science layer, the
  grounded intelligence. Server values win on reconcile; drift beyond tolerance
  is logged, never hidden.
- **The server is multi-tenant** (Phase 6, shipped — detail in
  `docs/MULTI_USER.md`, which owns this subject). One database, **row-level**
  tenancy: `user_id UUID` on all 16 data tables and folded into every natural
  key. Identity is **Supabase auth-only** — the backend is a *resource server*
  that verifies the JWT (`core/supabase_auth.py`) and never issues one; sign-in
  is Google/Apple social login. Every tenant read and write is owner-scoped, and
  **Postgres RLS is the backstop underneath** (`0008`): the app pool connects as
  a non-superuser `NOBYPASSRLS` role, so a missed `WHERE` returns nothing rather
  than another person's health data. Per-user timezone is live end-to-end; there
  is no global fire zone.
  - **Transitional, and load-bearing to know:** auth is **dual**
    (`core/request_auth.py`) — a Supabase JWT resolves to the real user, the
    **legacy shared token** resolves to the sentinel owner. That branch cannot
    die until the Phase-2 app ships Supabase login, so **`SIGNUPS_OPEN` must
    stay false until then**. And RLS only *protects prod* once `POSTGRES_APP_*`
    is set there — otherwise the pool falls back to the admin superuser, which
    bypasses the policies (the startup log says which). See `infra/DEPLOY.md`.

## The honesty contract (product law)

1. Never lies, never flatters — every interpretive sentence cites the corpus or
   doesn't ship (blocking validator). Enforced at the grounded-ask choke point,
   which is now ONE body of code (`insights/pipeline.py`) that **both** entry
   points run: `grounded_ask` for the non-conversational surfaces, `run_coach`
   for the coach. The coach used to be *enforced-equivalent* rather than
   routed-through, so a new rule had to be added in two places; #46 removed that.
   A stage is added to a registry and reaches both surfaces by construction, with
   a test that fails otherwise (INTELLIGENCE.md §3–§4).
2. Confidence is part of the answer — every number carries coverage, freshness,
   origin (measured/derived/provisional), and evidence grade.
3. Nudge, don't please — measured outcomes (frozen ledgers), not streak theater.
4. Science is a pipeline — graded notes, calibrated language, safety directives
   as hard guardrails. The guardrail is real and live: `insights/output_guard.py`
   blocks a documented forbidden output (personal death-risk projections,
   advising through red-flag symptoms, sleep restriction, bone-stress/REDs)
   **regardless of citations or validation** — a floor beneath the validator,
   because a forbidden answer can be perfectly cited. Its rules are hand-compiled
   from what the product documents, each citing the line that forbids it;
   compiling them *from* note directives is a seam, not yet a fact
   (INTELLIGENCE.md §2).
5. The user owns the data — self-hosted, on-device history, backups, export.
6. **Fast is a feature** — the app renders instantly from local data (never
   blocks on the network), the server answers reads in <100 ms p95, LLM work
   is pre-warmed and cached off the hot path. Concrete budgets are binding in
   ENGINEERING_STANDARDS.md ("Performance is a requirement").

## Phase plan

| Phase | Scope | Done when |
|---|---|---|
| 0 ✅ | Foundations: repo scaffold, CI + gates, hooks, infra (docker/nginx/deploy/backup) | CI runs the gates on every push |
| 1 ✅ | Server core: core/ingest/derive/analytics/insights/jobs rebuilt clean; the 5 legacy view-seam bugs fixed by design (v2-native reads); grounded coach through a blocking validator; seeded-DB + contract tests. **DONE** — 227 tests green on a real DB, deployable | All legacy /api/* endpoints reproduced, contract-tested; deployable |
| 2 | Mobile core: ble/ ported (version-guarded, sentinel-filtered), core/data layers, features rebuilt clean screen-by-screen | APK on device, all tabs live against the new server |
| 3 | On-device 60-day tier: local daily_metric mirror, /api/sync/down, retention pruning, offline-first rendering | Airplane mode = fully functional app; reinstall repopulates in one sync |
| 4 | Device analytics: baselines/trends/anomalies/provisional recovery/confidence in Dart, parity-tested vs server goldens | Parity suite green in CI; instant wake-up score |
| 5 | Companion intelligence: per-card confidence, weekly review digest, coach memory, knowledge-corpus reconciliation (unify to richer template + directives manifest), export | First honest weekly review delivered and fact-checked |
| 6 ✅ | **Cutover + real multi-tenancy** (not "seams"). Cutover: done — prod runs from this repo (`healtheeapi.example.com`), legacy stack stopped. Multi-user: **6.1→6.5 shipped** (migrations `0002`→`0008`) — Supabase auth-only identity (`app_user` UUID + hash-only `device_token`), `user_id` on all 16 data tables folded into every key, per-user timezone end-to-end, per-owner nightly chain, server-enforced signup gate, a least-privilege DB role, and **RLS** on all 16 tables. Guarded by an AST completeness guard + RLS/service/HTTP/job isolation suites (`tests/db/`). **Plan of record: `docs/MULTI_USER.md`** — it owns the detail. **Outstanding:** the legacy shared-token branch (dies with Phase 2) · 6.6 premium gating (unbuilt) · rate-limiting · per-user backup/export | Prod runs from this repo ✅; legacy repo frozen ✅; isolation proven by defeating it ✅ |

### Phase 1 work packages (the actual build order)

Server rebuilt module-by-module, each an independently-reviewed, CI-green merge.
Dependency order, not calendar order.

| WP | Module | Depends on | Status |
|---|---|---|---|
| WP1 | `core/` (config·pooled db·auth·notify·logging) + `db/` schema + migrations + `/healthz` | — | ✅ merged |
| WP4 | `packages/knowledge` — sports-science made citable + manifest generator + CI freshness | — | ✅ merged |
| WP2 | derive verbatim + parity-tested | WP1 | ✅ merged |
| WP3 | ingest + /ingest/helio | WP1 | ✅ merged |
| WP6 | analytics v2-native (5 seam bugs dead) | WP1·WP2 | ✅ merged |
| WP7 | read routers + contracts | WP2·WP3·WP6 | ✅ merged |
| WP5 | `insights/` — grounded-ask **choke point**, **blocking validator v2** (grade-calibrated), manifest retrieval, coach (5 tools; adopt_challenge deferred) | WP1·WP4·WP7 | ✅ merged |
| WP8 | `jobs/` — scheduler + the supervised event chain replacing legacy `Popen`; recs through the choke point; errors → Telegram | WP6·WP5 | ✅ merged |

Sequencing notes (deltas from the phase table above, kept honest):
- **`packages/contracts`** moved from Phase 0 → **WP7**: contract snapshots need real
  endpoints to snapshot. Deliberate, not dropped.
- **`jobs/`** is now an explicit Phase-1 package (**WP8**): the event chain needs
  analytics + insights to exist first. The prod compose already stubs the scheduler
  service for it.
- **`insights/` choke point** design (blocking validator, refusal pre-classifier,
  manifest retrieval, coach memory) is specified in `docs/INTELLIGENCE.md`.

Legacy audit findings (what these phases must not recreate): five silent
view-seam bugs, no backups, no tests, swallowed errors everywhere, a 4,463-line
API file, an 1,571-line screen. Full catalogue in the blueprint appendix.
