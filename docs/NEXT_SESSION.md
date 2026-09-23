# Next session — handoff (written 2026-09-23, updated same day after the fix session)

## 000. Open/close bugs B6–B8 — found, fixed, released as 1.0.9 (2026-09-23 evening)

Owner report: "a weird bug when opening and closing the app", in 1.0.8 and in the
upstream 1.0.7. Investigated over wireless adb on the Pixel 8 Pro (1.0.8 release).
Three separate bugs; only B6 is the visual one the owner meant. All three are
fixed on `fix/lifecycle-b6-b8` (1.0.9, versionCode 11), each with a failing-first
test and mutations in `test/mutations.sh` (all caught). Each was checked on the
phone with a locally built 1.0.9, signed with the owner's key and installed over
1.0.8 with `adb install -r` (data kept). The full suite passes (1937). The full
mutation file was **not** re-run, only the six new mutations.

| Id | Bug | Fix | On the phone |
|---|---|---|---|
| B6 | Every open/close switches the panel's **resolution** → flash / garbled frame | `2396513` | `mActiveModeId` stays 3 (1008×2244 @120) open and closed |
| B7 | Close with **Back**, reopen → "Nothing has been read from your strap yet"; the strap is not reconnected for up to 30 min | `6a1ed08`, `ddb05ae` | same pid, new engine scans and connects within 1 s; no false card |
| B8 | A BLE scan is left running (LOW_LATENCY) after a sync, for as long as the process lives | `3eec6ca` | both scans stop after registration; no scanner left registered |

**B6 — the display changes resolution on every open and close.** Not a Flutter
bug. `RefreshRate.enable()` (`refresh_rate` 1.0.2, added in `099afa3`, so already in
1.0.7) picks a display mode by refresh rate only (`setSurfaceFrameRate`:
`supportedModes.filter { refreshRate >= rate - 1 }.minByOrNull { … }`) and ignores
resolution. The phone is set to "High resolution", so its default is mode 3
(1008×2244 @120). Modes 2 (1344×2992 @120) and 3 tie, the first wins, and the panel
switches:
```
adb shell dumpsys display | grep mActiveModeId
launcher 3 → healthee 2 → launcher 3 → healthee 2 → launcher 3   (every time)
```
Fix: plugin removed (`pubspec.yaml`, `pubspec.lock`, `lib/main.dart`);
`android/app/src/main/kotlin/codes/afk/healthee/MainActivity.kt` asks for the peak
rate among modes **at the current physical size** only (still 120 Hz here, no
switch; SurfaceFlinger reports 1008x2244 @120.00 Hz with the app open). Guard:
`test/core/display_mode_test.dart`.

**B7 — Back, then reopen, leaves the strap locked by a dead isolate.** Back
destroys the Activity **and its FlutterEngine**, but Android keeps the **process**
alive (same pid). Reopening starts a new engine and a new Dart isolate in that
process. Two faults stack up:
1. *The lease is never released.* The old isolate's `toBackground` → `_release` →
   `DeviceLease.release()` is async, and the engine is torn down before it runs. The
   logcat shows the BLE disconnect coming from the plugin's `onDetachedFromEngine`,
   not from Dart. The new isolate's `acquire()` finds a row
   `<other-uuid>:<expiry>:<same pid>`, and `_reclaimIfOwnerIsGone` treats
   `owner == _pid` as alive (`data/sync/device_lease.dart`). So it waits out the
   30-minute expiry. `ForegroundLink._connect` just logs "background sync owns the
   strap; retrying shortly" and publishes no state. Logcat is consistent with this:
   the new engine makes **no** FBP method calls at all. (Inferred from the code plus
   that log. The lease row itself was not read: the release build is not
   debuggable, so `run-as` fails. Confirm it on a debug build.)
2. *The screen then says something false.* `SyncController.build()` starts at
   `const Disconnected()` with `lastCompleteSync == null`, and nothing replaces it.
   So `connection_health.dart` shows `never_synced`, "Nothing has been read from
   your strap yet", ten seconds after a complete sync.
   The strap battery also turns grey.

Repro: open the app, let it sync, press **Back**, reopen, then screenshot. Home
instead of Back does not trigger it (same engine).

Fix: (1) the isolate that runs `main()` calls `DeviceLease.markUiIsolate()` and
stamps its lease rows `<owner>:<expiry>:<pid>:<ui-token>`. A process hosts one UI
isolate at a time, so a same-pid row with a *different* UI token is reclaimed at
once. Unstamped rows (WorkManager's `backgroundDispatcher`, which never runs
`main()`) and rows from this same isolate are judged as before. Tests:
`test/background/device_lease_ui_isolate_test.dart`, `device_lease_test.dart`.
(2) `ForegroundLink._connect` now publishes
`Disconnected(lastCompleteSync: <stored>)` when the lease is refused, instead of
nothing (`test/sync/foreground_link_lease_test.dart`). **Still true:** a
*background* isolate cannot tell whether a stamped UI row is still live, so if
the owner never reopens after Back, background collection waits out the expiry
(≤ 30 min) as before.

**B8 — the preflight scan is never stopped.** `bluetooth_strap_scanner.dart`
listens to `FlutterBluePlus.scanResults`, which **re-emits the previous scan's
results** on listen (FBP docs; `onScanResults` is the variant that does not). On any
sync after the first, the old sighting of the strap completes the `Completer`
immediately, so `finally { stopScan }` runs about 5 ms after `startScan`, before
Android has registered the scanner:
```
17:53:59.935 onMethodCall: startScan
17:53:59.940 onMethodCall: stopScan
17:53:59.940 E BluetoothLeScanner: stopLeScan(): Error state, mScannerId=0
17:53:59.941 D BluetoothLeScanner: onScannerRegistered(status=0, scannerId=2)
```
The stop is dropped and the scan runs on. FBP now believes it is stopped
(`mIsScanning=false`), so even its `onDetachedFromEngine` cleanup skips it.
`dumpsys bluetooth_manager` showed "Ongoing 1 scans: [17:53:59.947] Elapsed
1207544ms … 3420 results" (20 min, LOW_LATENCY), and an earlier one lasting 558 s
until a force-stop. Costs: battery drain, and a preflight "in range" answer that
can come from a stale sighting. After a Back/reopen it also produces the
`invokeMethodUIThread: tried to call method on closed channel: OnScanResponse`
logcat spam. Fix: listen to `FlutterBluePlus.onScanResults`. A result can only
come from a registered scanner, so the stop can no longer arrive before
registration. The scan step is the top-level `scanForStrap` so a fake radio
(`test/ble/strap_scan_test.dart`) can drive it; that adds
`flutter_blue_plus_platform_interface` as a dev dependency.

## 00. Current state (end of 2026-09-23) — read this first

**The owner runs their own signed release now.** `v1.0.8` (versionCode 10) was built by
`release.yml` from this fork and signed with the owner's own key (SHA-256
`fe52d627…435c`); Obtainium on the phone tracks `TheCommishDeuce/healthee`, so future
releases update in place. Tag `vX.Y.Z` on `main` with a matching `version: X.Y.Z+N` in
`apps/mobile/pubspec.yaml` (N greater than the last) to release.

- **Signing key:** owner-held, backed up by the owner; the working copy is
  `~/.healthee-release/` on the dev Mac (`healthee-release.jks` + `credentials.env`).
  Fork secrets `HEALTHEE_KEYSTORE_BASE64`, `HEALTHEE_KEYSTORE_PASSWORD`,
  `HEALTHEE_KEY_ALIAS`, `HEALTHEE_KEY_PASSWORD` are set. Losing the key = another
  uninstall/reinstall switch. This settles R1 (upstream key no longer needed).
- **Phone:** only `codes.afk.healthee` (user 0), now 1.0.9 (a local build of the same
  commit, owner-signed, `adb install -r` over 1.0.8, see §000; the release APK is the same versionCode). The upstream 1.0.7 and both
  debug copies are uninstalled (debug had 0 unsent rows). Paired via Zepp, enrolled by
  QR — token `87539f07…` "Pixel 8 Pro"; the four leftover tokens (two `debug app`, two
  sign-in `ingest`) revoked. Background collection → ON and Wireless debugging → OFF were
  the owner's last steps.
- **Server:** `main` @ `7fc9c99`+ deployed (R9). PRs #10 (R9), #11 (debug-app work),
  #12 (1.0.8) merged.
- **Debug builds** still install side by side as `codes.afk.healthee.debug` when needed
  (`flutter build apk --debug`, `adb install`).
- **Still open:** GoTrue removal (now possible — QR enrollment runs on the real app;
  see §6), edge hardening, local LLM, the smaller §6 items.

## 0. Update — what the second session did

All owner feedback F1–F4 and bugs B1–B5 are implemented on `feat/debug-side-by-side`
(pushed; still **no PR**), each with tests, a mutation in `test/mutations.sh`, and a
`DESIGN_DECISIONS.md` entry under *First on-phone review*. The debug APK on the phone
has all of it.

| Item | Commit | Checked on phone |
|---|---|---|
| B4 sleep history in h/min | `9097689` | yes |
| B3 calendar months in mirror card | `2938a2e` | yes |
| B2 signed out → "sign in", no request | `c2f4607` | no (would need sign-out + QR re-enrol) |
| F2 overnight rows open their own metric | `1b84c91` | yes |
| B1 pairing re-runs the sync | `9c25ec7` | no (would need unpair + Zepp re-pair) |
| F2 Sleep trimmed; naps only on a nap day (owner chose this) | `87e94ac` | yes |
| F4 Insights trimmed (findings list cut, owner confirmed) — also B5 | `51145d3` | yes |
| F3 Activity bridges → Fitness→age + Recovery entry cards | `657b62c` | yes |
| F1 Today: steps / heart rate / stress day cards below sleep, recovery, weight | `65ae0ef`, `e1f1be4` | yes |

Later the same session (owner: "proceed"; accepted the F5 recommendations):

| Item | Commit |
|---|---|
| F5 R1 R2 R3 R5 R8 consolidation ([REDUNDANCY_INVENTORY.md](REDUNDANCY_INVENTORY.md)) | `142f7d6` |
| B2 on every server-backed screen: `/api/*` refused with no session, sign-in card | `a034a53` |
| R10 one `hoursMinutes`; Recovery baseline reads `6h 56m` not `416 min` | `81b2962` |

Full mutation run after F5: **311 caught, 0 survived** (more added since, each checked).

**Open now:**
- ~~R9~~ **done**: PR #10 merged (`7fc9c99`) and deployed via `deploy.sh` 2026-09-23
  (image `sha-7fc9c99`, digest `sha256:3d583569…`; rollback tag `sha-1b14b71`). Backup
  taken by the deploy: `/var/backups/healthee/healthee_2026-09-23_155939.sql.gz`
  (584 KB, gzip verified). The app half of R9 (absence wording) is on `main`, not yet on
  this branch — merge `main` in before the debug branch's PR.
- ~~B1/B2 on the phone~~ **confirmed by the owner** after a QR re-enrol.
- `V02LinkedChart` has no caller since R3 (kept with its tests on purpose).
- `RecoveryDetail.now` is unused since R2 (harmless; the screen's `now` feeds it).
- `durationLabel` (`48m`, workouts) and `hoursMinutes` (`0h 48m`, sleep) are two
  duration formats by design; revisit if the owner finds that inconsistent.
- The rest of §4–§6 below is unchanged (offline weigh-in test, clean-up, R1 key, …).

Sections 1–3 below are the original handoff, kept for context; their F/B items are done.


Start here. It carries everything needed to resume without the previous context:
owner feedback from the first on-phone session, bugs found, the live state of the
server and phone, open tests, and remaining setup. Background: [REVIEW_PLAN.md](REVIEW_PLAN.md)
(what was built and why), [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) (decision ids),
[QR_ENROLLMENT.md](QR_ENROLLMENT.md), [MIRROR.md](MIRROR.md),
[LOCAL_VERIFICATION.md](LOCAL_VERIFICATION.md) (build/test commands).

## 1. Where things stand

| Thing | State |
|---|---|
| Server | Deployed from fork `main` @ `1b14b71` (PR #9) via `infra/dockge/deploy.sh`; migration 0023 applied. Image `ghcr.io/thecommishdeuce/healthee-api:main` (`sha-1b14b71`, digest `sha256:389eba2b63e8…`). Rollback tag: `sha-448693c`. |
| Branch `feat/debug-side-by-side` | `6ae3fab` pushed, **not merged, no PR yet**: debug builds install as `codes.afk.healthee.debug` ("healthee debug"). Base the bug-fix work on it. |
| Real app on phone | `codes.afk.healthee` 1.0.7 (versionCode 9), installed by Obtainium 2026-09-22, upstream-signed. **Untouched.** The owner was asked to turn its background collection OFF for the test session — turn it back ON when testing ends. |
| Debug app on phone | `codes.afk.healthee.debug` installed for user 0 (the owner). Paired to the strap via Zepp sign-in, enrolled by QR (token label `debug app`, scope `phone`), synced and uploaded 109k readings. A second never-launched copy sits in user 10 ("Google" profile). |
| Phone | Pixel 8 Pro, Android 17 / API 37, wireless debugging was ON. |

On-phone results (all passed): side-by-side install; Zepp pairing (key + MAC stored,
Zepp password not kept); first strap sync (109,160 samples, 30 nights, 50 workouts,
2026-08-24 → 09-23); QR enrollment (scan → host confirmation → phone token); backlog
upload (0 pending, outcome `sent`, paged drain paused once then continued); server
data on Today (recovery 56/100); full-history download (439 records, 7 stream-months,
0.1 MB; rerun fetched nothing). Server history starts 2026-08-24.

## 2. Owner feedback (to implement)

Keep ids stable; record the decision in DESIGN_DECISIONS when implemented.

**F1 — Today.** Cards, in this set:
- day's **steps**, **heart rate**, **stress** — may reuse the Activity heart/stress
  chart (`features/activity/v02/heart_stress_panel.dart`) but expanded into detailed,
  **separate** overviews (steps / heart rate / stress each its own card);
- last night's **sleep**, **recovery**, **log weight** — already right, keep as is.
Code: `features/today/today_sections.dart`, `today_screen.dart`,
`features/today/widgets/`. Movement card lives in `features/activity/v02/movement_panels.dart`.
Note this partly reverses U11/U20 (Today was cut to sleep/recovery/weight); record it.

**F2 — Sleep.** "Fantastic", but:
- rows in **"Your body overnight"** must open the metric that row names; today every
  tap anywhere in the section lands on the HRV graph. Code path:
  `features/sleep/v02/vitals_panel.dart` → `shared/v02/vitals_table.dart`
  (`onOpenMetric(vitals[i].metric)`) → `shared/history_link.dart::openMetricHistory`
  → `/history?metric=`. Suspects: row metric keys not matching history metric ids so
  `HistoryScreen` falls back to its first metric (HRV), or the panel head's
  `onOpenAll`/a wrapping tap target swallowing row taps. Write the failing widget test first.
- everything from **"Beyond a single night"** down is redundant — remove it
  (`features/sleep/sleep_sections.dart`, `kSleepTrendsChapter` and below). **Naps: owner
  unsure** — ask before deleting `naps_panel.dart`.

**F3 — Activity.** Good, except the "stupid text between the cards". Those are
`ContextBridge` sentences in `features/activity/activity_sections.dart`
(`ageBridge(...)` → "See the calculation" → `/body`; `kActivityRecoveryBridge` →
"View recovery" → `/recovery`). The destinations (biological age, recovery) are "very
cool" and deserve **more visibility**: replace the bridge prose with proper entry
cards/rows, don't just delete the links.

**F4 — Insights.** Keep only: the **top 2 cards** (relationship grid:
`FindingEntryCard` + `AgeEntryCard`), **"Your longer patterns"** (`TrendsGrid`),
**notable days** (`NotableEvents`), and the **Sleep history** + **Fitness estimates**
rows. Remove the current-day material (`EffortStressPanel` and `kJournalBridge` in
`features/insights/insights_sections.dart`). **Confirm with the owner** whether the
"What changed together?" findings list stays (it was not in the keep-list).
This settles U13 (Insights kept, trimmed).

**F5 — Redundancy.** "A lot of redundancy in sections and screens" — e.g.
`features/sleep/sleep_history_screen.dart` shares plots with the Sleep screen. Do an
inventory (screen × panel) and propose a consolidation before deleting; keep one
definition per chart. Shared panels: `features/sleep/v02/*`, `shared/v02/*`.

## 3. Bugs to fix (none affects stored or uploaded data)

| Id | Bug | Where to look |
|---|---|---|
| B1 | Right after pairing, Today still shows the stale "No strap is paired with this phone" card from the auto-sync attempted before pairing; clears only after a manual pull. Pairing success should re-run the sync (or reset the link state). | `ble/strap_failure.dart::StrapNotPaired`, `data/sync/sync_controller.dart`, `data/sync/preflight_scan.dart`, pairing completion in `features/pairing/` |
| B2 | Not signed in, Today shows "Couldn't reach your server for today's judgements" beside "not signed in". It must say sign-in is needed, not blame the server (and not attempt the request). | `features/today/today_sections.dart` (`_dataHealth`, failure sections), `data/today_repository.dart` |
| B3 | History card says "439 records across **7 months**" — it counts stream-months; data spans 2 calendar months. Also "7 months downloaded, 0 already current" in the run message. Count distinct months, or say "7 month-blocks". | `features/settings/widgets/history_mirror_card.dart`, `data/mirror/mirror_sync.dart::stats` (+ `test/mirror/`) |
| B4 | Sleep history: sleep duration chart is in **minutes** (unit `min`, e.g. 416) — must be hours-minutes like the rows (`hoursMinutes`). | `features/sleep/v02/history_panels.dart` (~lines 118–140) |
| B5 | Orphaned sentence on Insights: `kJournalBridge` ("Sensors cannot tell what was happening around a busy hour.") introduced the removed journal link; now dangles. Goes away with F4. | `features/insights/v02/pattern_panels.dart`, `insights_sections.dart` |

Each fix: failing test first, then the fix, analyzer, full suite, a targeted mutation
in `test/mutations.sh`, debug APK, and a look on the phone.

## 4. Tests not yet done on the phone

- **Offline weigh-in (A8).** Airplane mode kills wireless adb, so simulate the outage:
  `cd /opt/stacks/healthee && docker compose stop api` → owner enters their **real**
  weight in the debug app (never a made-up value in their history) → expect "Saved on
  this phone…" → verify the held row
  (`sqlite3 … "SELECT * FROM pending_weights"`, see §7) →
  `docker compose start api` → Sync now → row gone → "Download full history" now shows
  a `weight_log` month.
- **Insights decision:** given as F4 above.

## 5. Clean-up when on-phone testing ends

```bash
adb uninstall --user 0 codes.afk.healthee.debug          # debug app only, owner profile
adb uninstall --user 10 codes.afk.healthee.debug         # the unused copy in the 'Google' profile
```
Server: `docker compose exec -T api python -m healthee.db.enroll devices --email <owner>`
→ `… enroll revoke <token-id of 'debug app'>`. Phone: real app → Settings → Background
→ ON; Developer options → Wireless debugging → OFF. **Never** uninstall, update or clear
`codes.afk.healthee`.

## 6. Remaining setup (not blocking the fixes above)

- **R1 release signing key.** Updating the real app in place needs the upstream
  `afkcodes/healthee` key (repo secret `HEALTHEE_KEYSTORE_BASE64`), or a supervised
  reinstall after draining unsent data. Until then the owner uses the release app plus
  the side-by-side debug build.
- **GoTrue removal** — only after QR enrollment runs on the *real* app (needs R1):
  remove `auth` from `infra/dockge/compose.yaml`, the Traefik `/auth/v1` router, and the
  app's email form. Separate change.
- **Local LLM (P2).** `LLM_BASE_URL` exists (`core/llm_endpoint.py`). Endpoint
  `https://alpaca.homelab-nn.com` answered 404 on `/v1/models` from the dev Mac (with and
  without the key from `prime_slop/.env`). From the home network, with the isolated test
  DB (§7):
  `cd apps/server && LLM_BASE_URL=<url>/v1 OPENROUTER_API_KEY=<key> DEFAULT_MODEL=<id> COACH_MODEL=<id> POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5599 POSTGRES_USER=healthee POSTGRES_DB=healthee POSTGRES_PASSWORD=local-test-only .venv/bin/python ../../scripts/model_eval.py`.
  Watch for a Gemma chat template that rejects the **system** role (the pipeline sends
  system prompts). Only after it passes: set `LLM_BASE_URL` in the stack `.env`.
- **Paid-plan layer:** kept, disabled by config — `SELF_HOST_UNLOCKED=true`,
  `PREMIUM_COACH_QUESTIONS=0` in the stack `.env` (X5). Confirm the owner set them.
- **Edge hardening:** Traefik forwards all of `/auth/v1/*` to GoTrue, including
  `/auth/v1/admin/*` (protected by the service-role JWT only). Block `/auth/v1/admin` at
  the edge (`infra/traefik/healthee.yml.template` + test in `test_edge_traefik.py`).
- **Traefik `healthee-enroll` router** — owner was given the render/install steps;
  verify it is live (`POST /api/enroll` → 401 either way).
- **Mirror reader:** no screen reads the downloaded history yet (offline fallback for
  history screens is the intended first use).
- **Weigh-in retries** run on foreground pushes only; add the background task.
- **Different-owner limit:** unsent strap rows and held weigh-ins upload to whichever
  owner the phone is signed in to.
- **Flaky tests (watch in CI):** `auto_sync_wiring` ×2, `today_minimal`,
  `today_withheld` failed once under load, passed on rerun.
- `code-review-findings.md` MEDIUM/LOW items were never revalidated.

## 7. How to resume on the dev Mac

```bash
# toolchain (not in any shell profile)
export FLUTTER_ROOT="$HOME/.local/share/healthee-tools/flutter-3.44.7"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH"

git switch feat/debug-side-by-side && git pull
cd apps/mobile && flutter pub get && flutter build apk --debug

# phone: owner enables Wireless debugging and pairs; then
adb pair <ip:pairing-port> <code>; adb connect <ip:port>; adb devices -l
adb install --user 0 -r build/app/outputs/flutter-apk/app-debug.apk   # debug app ONLY

# server tests: isolated TimescaleDB (never the live DB)
colima start --profile healthee --cpu 4 --memory 6 --vm-type vz
docker --context colima-healthee start healthee-test-local
```

Tips learned this session:
- Our app logs via `developer.log`, which does **not** reach logcat (a
  `flutter:*` logcat filter shows other Flutter apps instead). Inspect the debug app's
  state directly — it is debuggable:
  `adb exec-out run-as codes.afk.healthee.debug cat files/healthee.sqlite > /tmp/h.sqlite`
  (also `-wal`, `-shm`), then `sqlite3`. Secure-storage key *names* (never values):
  `adb shell run-as codes.afk.healthee.debug cat shared_prefs/FlutterSecureStorage.xml`.
- Screenshots: `adb exec-out screencap -p > apps/mobile/build/screens/x.png` (ignored
  path), `sips -Z 1200` to shrink; the image reader sees new files only after ~20 s.
- Tap coordinates: screenshots scaled to 539×1200 map to the 1344×2992 screen ×2.4935.
