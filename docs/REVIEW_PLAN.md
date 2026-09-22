# Personal-use rebuild plan

Starting revision: `c071c15`. Working branch: `feat/mobile-simplification`.

- [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md): owner decisions, proposals and corrections.
- [PHASE_A_TRIAGE.md](PHASE_A_TRIAGE.md): safe boundaries and dependency checks.
- `ENGINEERING_STANDARDS.md` and `HOW_WE_VERIFY.md`: existing binding gates.

## Current progress

- Local Android debug builds work; verification commands/results are in
  [LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md).
- `0ea9902`: corrected a Linux-only lease-test expectation for macOS, without changing
  runtime code.
- `b3c4e47`: removed mobile GPS/maps, their entry points and geolocation dependency;
  kept strap workouts, old stored data and BLE permissions intact.
- Today now shows sleep, overnight recovery and direct weight entry. The linked HR/stress
  chart moved to Activity; Sleep and recorded-workout behavior are retained. Old Today
  chapters and the floating coach button are removed. Widget screenshots are in
  `docs/screenshots/personal-today-{light,dark}.png` (fixtures, not personal data).
- `2fc4c41`: removed the general journal route/page and links. Weight entry now exposes
  only stored fields (kg/time), preserves observation identity on retry and prevents
  double submissions. Existing observations and server logging APIs remain intact.
- Latest mobile gate: **2,054 passed, 6 skipped**, analyzer clean, debug APK built;
  **6 targeted weight/journal mutations caught**, none survived. The preceding Today
  slice also passed 12 targeted checks. Neither was a full mutation sweep.
- **Next:** review remaining Actions/interactive-coach navigation and plan the QR auth
  migration without deleting nightly analytics. Insights remains available for review.
- QR enrollment, full-history mirroring and local-LLM integration remain later work.

## Outcome

A simpler Android app retaining useful BLE data collection, reliable offline uploads and
server-owned history:

- **Today:** sleep summary, overnight recovery, log weight.
- **Sleep:** minimal changes.
- **Activity:** activity plus heart rate/stress; preserve recorded workouts.
- No food tracker, new gym logger, built-in GPS/maps, or general journal dashboard.
- QR enrollment instead of email/password; preserve owner/history across phones.
- Local-model nightly analysis later; HA integration deferred.
- Insights remains tentative for review rather than automatically deleted.

## 0. Establish a baseline

1. Locate/reuse Java and the Android SDK; install repo-pinned Flutter 3.44.7.
2. Resolve the committed dependencies, run analyzer and the full mobile tests.
3. Build an unmodified debug APK. Record all failures before changing implementation.
4. Run server tests with a throwaway TimescaleDB and an explicit test-only configuration.
   Report skipped/network-dependent tests separately from passes.
5. Record repeatable local commands and tool versions. Do not edit live deployment
   credentials or reset the owner's password as part of testing.

A platform-specific test error gets its own small correction. Do not change Android
runtime behavior merely to make an inappropriate Linux-only assertion pass on macOS.

## 1. First mobile slice

- Recompose Today around the three requested content areas.
- Preserve dated server/cache provenance, raw local sleep fallback, retry and illness
  notices; stable morning recovery must not silently mean live readiness.
- Reuse the weight validation/write path; retain the form on unconfirmed saves. Explicitly
  distinguish current online-only manual logging from the durable BLE outbox.
- Remove redundant Today composition/navigation only after reviewing shared callers.
- Tests: populated, missing/withheld, cached/stale, server-down, narrow layout, navigation,
  weight validation and failed save. Preserve existing Sleep/Activity safety assertions.

## 2. Small feature-removal slices

- Move heart rate/stress to Activity without making that page equally crowded.
- Remove GPS/maps and its dependencies, retaining recorded workout history. Check Android
  BLE permission requirements before deleting location permissions.
- Remove unwanted journal/Actions/interactive-coach entry points and orphaned code in
  separate reviewable changes. Do not delete weight plumbing or nightly analytics.
- Keep history and shared detail pages until working replacements exist.

## 3. Identity and historical mirroring

Separate from the screen cleanup:

- One-time, expiring QR enrollment; revocable scoped credentials; administrator recovery.
- Migrate the existing owner without creating a new UUID or losing access to old rows.
- Maintain installed-client compatibility until replacement is verified.
- Design and test an owner-scoped, resumable snapshot/delta download. Include corrections,
  deletions and a non-reuploading local import path; never download the raw server DB.
- Add durable offline manual weight logging if it is expected to share the BLE outage
  guarantee. Do not describe the existing online form as an offline queue.

## 4. Later intelligence

Retain canonical metrics, the graded corpus and output guardrails. Evaluate the actual
local model before integration; `prime_slop` provides client experience, not proof of
health-answer quality. Use supervised nightly generation, explicit stale/failed status,
and no model calls in collection or screen-read paths. Keep resource limits despite
removing commercial entitlement logic.

## Verification and delivery

For every slice: tests for behavior changes, analyzer, affected server checks, APK build,
and an explicit diff review. Report known baseline failures instead of hiding them.

Before release: review on a real Android phone, verify sync during a server outage and
replay afterwards, verify signing-key compatibility, and confirm existing data remains.
Do not uninstall the existing app to work around a signature mismatch: that can destroy
unsent measurements and credentials.

No production deploy, production DB changes, password reset, or APK installation is part
of initial local work. Keep a concise build/verification record and update decision status
as each slice is actually implemented, not when it is merely proposed.
