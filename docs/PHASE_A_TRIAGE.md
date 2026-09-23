# Rebuild triage — verified facts versus proposals

Reference: `c071c15`. Decisions: [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md).
This document replaces the earlier mechanical deletion list, which inferred too much
from import counts and contained stale defect claims. **It is not a `git rm` script.**

## Inventory limits

The earlier walk counted about 99,465 lines across 584 Dart files, including generated
code, comments, tests' shared definitions and multiple classes per file. Every file was
reachable through imports, which does **not** prove every symbol or feature is used.

Removing feature nodes from that graph produced projections of 79,836 and 67,015 lines.
Those were not compilable builds: the graph did not repair imports, preserve shared
symbols, implement replacement screens, or account for replacement tests. Do not cite
those numbers as measured savings or evidence of safety. APK size, battery use and
rendering performance need separate measurement.

## Current mobile disposition

| Area | Decision | Dependency check / first action |
|---|---|---|
| Today composition | Replace with sleep, overnight recovery and weight entry | `today_sections.dart`, `today_screen.dart`; preserve loading, stale, offline, illness and navigation behavior. |
| `features/today` helpers | Not a blanket deletion | Other screens and details import these. Delete only confirmed-orphaned code after rewiring. |
| Sleep | Preserve, minimal changes | Shared sleep panels and dated history remain load-bearing. |
| Activity | Preserve; add heart rate/stress | Move the existing chart rather than create a second definition; check density. |
| Workouts | Keep | Strap session history/detail, not sets/reps or an exercise library. |
| GPS/maps | Remove in its own slice | Recorder, routes, theme tokens, tests and permissions; check older-Android BLE location requirements before stripping permissions. |
| General journal | Remove visible clutter, retain weight capability | `LogSheet`, `JournalRepository`, `LogDraft` and `/api/log` currently implement weight. They cannot all be deleted. |
| Insights | Tentative first-build review | Do not remove on the claim that the owner definitely rejected it. |
| Actions/interactive coach | Candidates for a separate scoped removal | Router, shell FAB, notifications and shared recommendation panels must be reviewed together. |
| Sign-in | Replace only after QR path is complete | Preserve owner UUID/history and installed-client compatibility; do not disable auth to simplify screens. |
| History | Keep until a replacement exists | `InstrumentScreen` reads dated history. It is not dead because History is not a tab. |
| BLE, local store, sync, push | Preserve | Regression-test interrupted pulls/uploads, acknowledgements, replay, ownership and retention. |
| Honesty/confidence UI | Preserve | Also protects measured/derived non-LLM readings. |
| Settings, pairing, diagnostics, updater | Keep | Needed to operate and diagnose a self-hosted collector. |

## Server and infrastructure boundaries

- Keep ingest and canonical science functions unchanged during UI work.
- `jobs/correlate.py` computes sensor correlations **and** manual-event cutoffs; nightly
  recommendations consume findings. No blanket correlation deletion.
- Historical review C1 is already fixed: owner ID is threaded into cutoff persistence.
  Revalidate old audit findings before treating them as current defects.
- Keep `jobs/chain.py` and grounding/validation available for the later local-LLM phase.
- Commercial entitlements may be removed later without removing auth, resource limits,
  owner isolation, or historical migrations/tables as an incidental cleanup.
- Full phone history needs a real owner-scoped export/delta contract with cursor,
  deletion/correction semantics and idempotent local import. Mirrored rows must not be
  re-uploaded as newly collected samples. Do not remove current history first.
- QR enrollment requires a security review and migration plan, not promotion of every
  ingest token to unrestricted account access.
- Existing Traefik deployment remains unchanged during local mobile work.
- HA integration and the separate landing site are outside the first slice.

## Offline checks

Existing BLE pushes are send-before-mark with idempotent server writes. This needs tests,
not a claim that every outage is solved. Check:

1. Server failure before/after committing a page; retry must not lose or duplicate rows.
2. App restart with pending rows and expired/revoked credentials.
3. Reauthentication to the same owner versus switching owners/servers.
4. Retention: pending events are preserved, but samples have a 365-day hard limit.
5. Partial ACKs, corrected samples, cursor progress and backlog drain bounds.
6. Manual weight entry: existing implementation is online-only, outside the BLE queue.

## Verification required for each slice

- Reproducible Flutter analyze/tests and Android build, compared with a pre-edit baseline.
- Tests for changed behavior, not wholesale removal of failed safety tests.
- A review of reverse imports/callers before deleting a file.
- Isolated test TimescaleDB for server changes; never the live database.
- Real phone checks (BLE/offline replay/visual review) before release; a debug APK or
  widget test cannot prove radio/background behavior.
- Preserve the installed app's signing key and unsent data. A new debug signature cannot
  safely update a release signed by somebody else; do not suggest uninstalling it.
