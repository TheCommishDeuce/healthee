# Design decisions

Decision record for the personal-use rebuild, starting 2026-09-22.
**Accepted** means an explicit owner requirement or an approved direction. **Proposed**
means an implementation choice still subject to inspection. Neither means implemented.
Implementation status and verified facts belong in `REVIEW_PLAN.md` and
`PHASE_A_TRIAGE.md`. Keep IDs stable; record reversals instead of silently changing scope.

## Product and intelligence

| ID | Status | Decision |
|---|---|---|
| P1 | Accepted direction | Personal, self-hosted app rather than a commercial SaaS. Preserve useful BLE data; remove unnecessary product complexity. |
| P2 | Accepted | Try the owner's local Gemma instance later. Nightly batch generation is useful; it need not be in the first build. |
| P3 | Accepted (2026-09-23) | Remove interactive coach UI from the first simplified build, including the conversations stored on the phone. The server's `/api/coach` stays for installed older clients. This is not a permanent prohibition on chat. |
| P5 | Accepted (2026-09-23) | Remove the Actions tab and its challenge, program, outcomes and recommendation-history screens. The daily-focus and challenge-completed notifications go with it. Nightly recommendation/correlation jobs stay on the server (A7). |
| P4 | Preserve | Keep knowledge, citation validation, confidence and safety guardrails for any future LLM output. |

`prime_slop` has a llama.cpp/OpenAI-compatible client and a configured homelab endpoint.
Its documentation mentions a 12B model, but that does **not** verify the owner's current
Gemma model, size, speed or health-advice quality. Benchmark/evaluate before integrating;
a base-URL swap alone does not establish compatibility or safety. Local inference still
has resource costs, so removal of commercial entitlements must not remove abuse controls.

## Identity and deployment

| ID | Status | Decision |
|---|---|---|
| I1 | Accepted direction | No email/password setup. Replace it with QR enrollment while preserving the existing owner and health history. |
| I2 | Proposed security design | QR holds a single-use, short-lived enrollment code, exchanged over HTTPS for per-phone credentials. Enrollment issued by an authenticated administrator/CLI. |
| I3 | Proposed security design | Revocable, least-privilege phone credentials; phones cannot enroll other phones by default. Keep administrative recovery separate. |
| I4 | Accepted | Reuse the existing Traefik deployment path. Traefik does not establish whether the service is public or private; treat credentials as exposed-network credentials either way. |

The current API requires JWTs for reads and device tokens for ingest. Removing GoTrue is
not a deletion-only task: owner mapping, scopes, credential rotation, recovery, migration
and compatibility with the installed app must work first. Do not reset the owner's
password or alter production auth as a side effect of local development.

## Data and offline operation

| ID | Status | Decision |
|---|---|---|
| A1 | Accepted | Server is the canonical source of full health history. |
| A2 | Accepted capability; API design proposed | Phone may download its complete health history. Use an owner-scoped, paginated snapshot/delta API, not a raw database dump containing credentials or other users. Exact contract is not yet designed. |
| A3 | Accepted | Collect BLE data during server outages and upload pending data after recovery, without loss or duplication. Preserve local reads and clearly date cached server results. |
| A4 | Preserve | Keep owner isolation/RLS. One user now does not justify removing safety infrastructure. |
| A5 | Future consideration | Separate owners/devices and other BLE protocols may be useful later. No speculative device framework or blanket `strap_*` renaming now. |
| A6 | Deferred | Home Assistant integration is on hold. Preference is push when revisited; MQTT is a proposal, not a chosen requirement. |
| A7 | **Retracted technical conclusion** | Earlier notes incorrectly proposed deleting all correlation analytics because manual caffeine/alcohol logging is unused. Preserve shared correlations and nightly dependencies pending an actual caller review. |

The BLE upload queue already uses SQLite pending rows, send-before-mark, and server
upserts. Verify failure/restart behavior rather than replace it. It is **not** unbounded:
unsent high-volume samples have a 365-day retention limit; unsent event records are kept
without that limit. Manual weight logging currently posts to the server and is **not**
covered by the BLE outbox. Durable offline weight entry requires separate implementation.

The historical C1 cross-tenant cutoff finding is already fixed at the starting revision:
`jobs/correlate.py` passes `user_id` to `persist_cutoff_findings`. Deleting working code
cannot be claimed as fixing that old finding. That job also computes sensor correlations
used by recommendations, not only caffeine/alcohol cutoffs.

## Screens and tracking

| ID | Status | Decision |
|---|---|---|
| U1 | Accepted | Dedicated Today, Sleep and Activity pages, split by function. Insights remains tentative (U13). |
| U2 | Accepted | Today emphasizes information that remains useful all day, rather than a dashboard of continuously changing measurements. |
| U3 | Accepted | Sleep should change minimally. Preserve its existing detail, honesty states and navigation. |
| U4 | Accepted | Activity combines the current activity screen with heart rate and stress. Do not just move all of Today's clutter there. |
| U5 | Accepted | Weight entry is directly accessible on Today for the morning weigh-in. Reuse existing validated logging/storage where appropriate. |
| U6 | Superseded by U10 | Earlier proposal to add food logging. |
| U7 | Proposed method | Prefer concise summaries and reachable detail over crowded screens. No arbitrary global panel count; Today has its explicit budget in U11. |
| U8 | Accepted direction | Retain functional page navigation and existing visual language. No unrelated theme or component-library rewrite. |
| U9 | Consequence | Remove Today's chapter-navigation machinery when the short layout no longer needs it. |
| U10 | Accepted | Do not build food tracking. Owner: “nevermind dont bother.” |
| U11 | Accepted | Today's three content priorities, in order: **sleep, recovery, log weight**. Conditional sync/failure/safety notices are not extra dashboard sections and must remain useful. |
| U12 | Proposed method | Remove surplus Today composition; retain shared components/details until callers are checked. Lack of a top-level tab does not mean a detail page has no caller. |
| U13 | Tentative | Owner: “maybe (lets see it in the first build)” about Insights. Earlier notes incorrectly converted this into an unequivocal deletion. Retain it for review rather than silently remove it. |
| U14 | Accepted direction | No general journal page is needed for caffeine/alcohol tracking; owner does not log those. Keep weight entry and its supporting code. Do not delete `data/journal` before moving/reusing the weight path. |
| U15 | Accepted | Remove built-in GPS/maps; owner uses Dawarich. Preserve workout records and any stored data during the removal. |
| U16 | Accepted | Keep recorded workouts for exploration. Current UI displays strap-recorded sessions; it is not an exercise/set/rep catalogue. |
| U17 | Proposed/deferred | Landing site is a separate Astro marketing/waitlist site, unrelated to the Android UI. Owner did not know it existed. No deletion needed to deliver the first mobile slice. |
| U18 | Accepted with dependency check | Replace the crowded Today composition. Do not blindly delete every file under `features/today`: Sleep, Activity and pushed details share some of them. |
| U19 | Accepted | No new gym exercise catalogue, sets/reps or progression tracker for now. Does not remove strap-recorded workouts (U16). |
| U20 | Implementation choice for U11 | Today uses three full-width cards, without the age hero, dashboard chapters or floating coach button. Recovery keeps its factor bars; weighting/method detail remains reachable rather than duplicating the full detail page. |
| U21 | Implementation choice for U5 | Weight entry opens the existing validated form directly. Its sheet observes credential loading/retries for its lifetime; unconfirmed saves retain the typed draft. No offline-queue claim. |
| U22 | Implementation choice for U2/A3 | Sleep timestamps are displayed in phone-local time, explicitly labelled local and including the year. The server sends timestamp instants, not necessarily owner-local dates. Missing dates are explicit. Local sleep is a fallback only when no server answer exists, never a way around a server refusal. |

### General journal removal and weight-only entry

- **U23 — implementation of U14:** remove the general journal page, route, grid and
  links from Settings, Sleep, Actions, Insights and metric history. Retain existing
  observations, history markers and the server logging API; this is not a data deletion.
- **U24 — weight form integrity:** show only kilograms and observation time. The
  weight branch of `read/logs.py::record_log` stores no notes, so a notes field would
  promise storage it does not provide. Retrying an unconfirmed save keeps its original
  timestamp, matching the existing server upsert key `(user_id, ts)`. Concurrent Save
  taps are refused. These protections last while the form is open; closing/killing the
  app still does not create a durable offline draft or outbox.

### Presentation constraints for the first slice

- Sleep summary links to the full Sleep page; date older sleep explicitly.
- Recovery means the **overnight recovery estimate**, not the live, exertion-decayed
  readiness figure. Preserve factor breakdown and medical/safety qualifications.
- Activity receives the existing linked heart-rate/stress chart; its measurement guards
  and non-causality warning stay intact. Sleep's implementation is unchanged.
- Weight entry must distinguish saving, confirmed save, and failure; never clear an
  unconfirmed input or claim it was queued offline when it was not.
- Keep sync status, retry, cached-data provenance and illness notices without recreating
  the old dashboard. No invented values for loading/empty/error states.

## Engineering process

| ID | Status | Decision |
|---|---|---|
| X1 | Delegated, not a rules change | Owner permits changes to engineering conventions. Earlier proposal of a 600-line cap was not applied to the binding standards or CI. Follow existing gates until changed together in a separate, justified patch. |
| X2 | Accepted approach | Small, reviewable changes with tests. Preserve BLE parsing, science formulas, owner isolation and upload integrity. Tags/commits do not substitute for regression coverage. |
| X3 | In progress | Establish a measured local build/test baseline before deletion. Report pre-existing failures and unavailable hardware checks honestly. Never run tests against the live health database. |

### Offline weight and delivery order (2026-09-23)

- **A8 — accepted:** manual weight entries must survive a server outage like strap
  data: stored durably on the phone first, uploaded later, never duplicated.
- **X4 — accepted order:** mobile trimming → QR enrollment → offline guarantees →
  full-history mirroring → local LLM → deferred cleanup.
- **R1 — open blocker:** the release signing key is unknown. The fork has no
  `HEALTHEE_KEYSTORE_BASE64` secret and no releases; the installed app is most likely
  upstream `afkcodes/healthee` v1.0.7, signed by that repository's key. Until that key
  is obtained (or a supervised one-time reinstall is chosen after draining unsent data),
  no build from this branch can be installed over the existing app.

## Resolved questions from the interview

- **Q1:** Food tracker: do not build (U10).
- **Q2:** Today: sleep, recovery, log weight (U11).
- **Q3:** Insights: tentative first-build review, not an unconditional cut (U13).
- **Q4:** GPS/maps out; workouts retained; no requirement to remove diagnostics/update checks.
- **Q5:** Landing page explained; isolated from mobile work (U17).
- **Q6:** Proceed with replacing old Today composition, subject to shared callers (U18).
- **Q7:** No caffeine/alcohol logging (U14); does not eliminate sensor correlations (A7).
- **Q8:** No gym-style logging for now; recorded workouts stay (U19/U16).

## Implementation approval

2026-09-22: owner approved proceeding and suggested reusing local Android tooling.
Initial work is local baseline verification, then a small tested mobile slice. No
production deployment, password reset, data migration or installation over the owner's
existing app is implied. Signing-key compatibility must be checked before any upgrade.
