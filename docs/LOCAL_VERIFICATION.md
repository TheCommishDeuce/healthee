# Local build and verification — 2026-09-22

Branch: `feat/mobile-simplification`, starting at `c071c15`.
This first slice establishes the baseline and removes **mobile GPS/maps only**.
Today/Sleep/Activity restructuring, QR auth, historical mirroring and nightly local LLM
integration are still pending. No production credentials, services or database changed.

Changes: `0ea9902` (portable lease test), `b3c4e47` (GPS removal). The latter deletes
27 mobile GPS/map source files and removes nine resolved dependencies; it is not the
full UI redesign.

## Toolchain on this Mac

- Flutter **3.44.7**, revision `84fc5cbb22`, Dart **3.12.2** (same Flutter pin as CI).
  Installed at `~/.local/share/healthee-tools/flutter-3.44.7` from the official git tag.
- Reused Homebrew Java **17.0.20.1** and SDK at
  `/opt/homebrew/share/android-commandlinetools` (not in `prime_slop`).
- Build installed SDK platforms 35/36, build-tools 36.0.0, NDK 28.2.13676358 and
  CMake 3.22.1 alongside the pre-existing platform/build-tools 34.
- Installed Docker CLI/Colima; dedicated `healthee` VM (4 CPUs, 6 GiB RAM).
- Server uses its existing Python **3.13.5** `.venv`.

No shell profile was modified. For a new terminal, from the repo root:

```sh
export FLUTTER_ROOT="$HOME/.local/share/healthee-tools/flutter-3.44.7"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$PATH"

cd apps/mobile
flutter pub get
flutter analyze --fatal-warnings --fatal-infos
flutter test --reporter expanded
flutter build apk --debug
```

The dependency lock was not upgraded: removing `geolocator` removed it and eight now-unused
transitive packages. Gradle warns about three existing plugins' legacy Kotlin Gradle
usage (`flutter_timezone`, `refresh_rate`, `workmanager_android`); the pinned build works.

## Results

| Check | Baseline | After GPS removal |
|---|---|---|
| Flutter analyzer | No issues | No issues |
| Full mobile tests | 2,204 passed, 6 skipped, **1 failed** | **2,161 passed, 6 skipped, 0 failed** |
| macOS lease-test correction, before removal | **2,205 passed, 6 skipped, 0 failed** | Same runtime behavior; only test expectation changed |
| Android debug APK | Built | Built |
| Server pytest, isolated DB, UTC and Asia/Kolkata | **3,235 passed, 5 skipped in each timezone** | No server implementation changes |
| Server ruff / format / pyright | Passed / 561 files formatted / zero errors | No server implementation changes |
| Repository 400-line gate | — | Passed |
| Targeted mutation tests | — | GPS removal: 2 caught; Activity: 4 caught; none survived |

The full mutation sweep was **not** run; these were explicitly filtered runs. No real
Android device is connected, so BLE hardware, background collection, visual review and
physical outage replay are **not verified** by this session.

### The one mobile baseline failure

`test/background/device_lease_test.dart` expected immediate dead-process reclamation on
all platforms. Production deliberately uses `/proc` on Android/Linux and waits for lease
expiry elsewhere. The test now checks both platform behaviors plus expiry. No BLE/lease
runtime code changed. The four focused lease tests and the complete suite pass on macOS.

### Coverage changes

Tests for the deleted GPS feature were removed with it, including its ten mutations.
Added regression coverage proves:

- Activity still renders a seeded strap workout and keeps history accessible;
- GPS routes/entry points and the workout GPS-record button are absent;
- fine/coarse location permissions are capped at API 30 while Bluetooth scan/connect
  and `neverForLocation` remain;
- dropping workout rows or restoring unrestricted location permission makes tests fail.

Local GPS tables and all migrations remain, deliberately: removing a screen is not
permission to destroy previously recorded data. Their UI/recorder/upload client is gone.
Backend GPS endpoints are unchanged for older clients. All BLE protocol, science formulas,
raw measurement storage and upload/outage logic remain unchanged.

## Isolated server tests

Never substitute the live deployment's database variables into these commands.
The tests make their own temporary database and least-privilege role inside the local
throwaway container. On this Mac, the test-only container uses:

```sh
colima start --profile healthee --cpu 4 --memory 6 --vm-type vz
# Run once; omit if this named container already exists.
docker --context colima-healthee run -d --name healthee-test-local \
  -e POSTGRES_USER=healthee -e POSTGRES_PASSWORD=local-test-only \
  -e POSTGRES_DB=healthee -p 127.0.0.1:5599:5432 \
  timescale/timescaledb:latest-pg17

docker --context colima-healthee start healthee-test-local
docker --context colima-healthee exec healthee-test-local pg_isready -U healthee
cd apps/server
TZ=UTC POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=5599 POSTGRES_USER=healthee \
  POSTGRES_DB=healthee POSTGRES_PASSWORD=local-test-only \
  .venv/bin/python -m pytest --no-cov
# Repeat with TZ=Asia/Kolkata; do not run two suites concurrently.
```

Image tested: `sha256:c79fa5891443d1cdf6de5258d4c2bdb8cde29052c45df2062b13d351e0202005`.
The initial no-DB run was not a valid full baseline: it skipped integration tests and an
unguarded contract test timed out on a missing pool. The isolated-DB run above replaces it.

## APK and safety

Artifact: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`.
Built with the local debug key, **not the original release key**. Do not uninstall the
existing app to install this APK: that can erase unsent data and credentials. This is a
build-validation artifact, not yet a verified upgrade for the owner's phone.

Baseline size: **176,020,049 bytes**; after removal: **176,014,473 bytes**.
The debug APK shrank only 5,576 bytes. Source/dependency removal is not evidence of a
large binary-size improvement; release size and performance were not benchmarked.
The actual packaged manifest was checked using build-tools `aapt dump permissions`.

Logs for this session: `/tmp/healthee-verification/` (temporary, not committed).
The throwaway DB and Colima VM were stopped after verification.
After testing, stop the disposable DB with
`docker --context colima-healthee stop healthee-test-local`; stop the VM with
`colima stop --profile healthee`. Neither command targets the deployed stack.
