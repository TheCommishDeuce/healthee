/// The host every settings suite pumps: the real router over pinned providers.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
///
/// The settings surface is **nine screens reached from one index**, so a host
/// that pumps a single widget cannot ask the questions that matter — whether a
/// row lands on the screen it names, and whether the appearance control on one
/// screen moves the theme the whole app renders in. So this stands up a real
/// `GoRouter` over the real routes, with only the platform-backed providers
/// pinned: the keystore, the local store, the version channel and the strap
/// radio, none of which a `flutter test` host has.
///
/// [themeMode] is deliberately NOT pinned by default. `appearance_test`'s whole
/// point is that choosing a mode changes the brightness the app is rendered in,
/// and a pinned controller would make that assertion vacuous.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/settings_routes.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/theme_controller.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/background/background_preferences.dart';
import 'package:healthee/data/background/background_scheduler.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/mirror/mirror_sync.dart';
import 'package:healthee/data/notifications/notification_providers.dart';
import 'package:healthee/data/notifications/reminder_preferences.dart';
import 'package:healthee/data/pairing/paired_strap.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/data/push/push_stamp.dart';
import 'package:healthee/data/push/push_stamp_provider.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/data/updates/update_check.dart';
import 'package:healthee/features/settings/app_version.dart';

import '../_today_stubs.dart';
import '../pairing/_pairing_fakes.dart';
import '_today_host.dart' show FixedConnection;

/// The instant every freshness label in these suites is measured against.
final DateTime settingsNow = DateTime(2026, 8, 5, 9, 30);

/// The day these suites describe.
const String settingsDate = '2026-08-05';

/// A strap that is paired, with a MAC a test can find by text.
const PairedStrap pairedStrap = PairedStrap(
  mac: 'C0:FF:EE:00:00:01',
  authKey: '000102030405060708090a0b0c0d0e0f',
);

/// A day with one complete sync and a battery reading behind it.
///
/// **Dated relative to the wall clock, not to [settingsNow].** These screens are
/// pumped through the real router, which builds `const DeviceScreen()` and so
/// cannot be handed an injected instant — the screen reads `DateTime.now()`. A
/// fixture pinned to a fixed date would therefore render "a month ago" and the
/// freshness assertion would be about the calendar rather than about the code.
/// The offset is what is fixed here; the instant it is measured from is the
/// same one the screen uses.
DeviceDay dayWithSync({Duration syncedAgo = const Duration(minutes: 12)}) {
  final at = DateTime.now();
  final empty = DeviceDay.empty(settingsDate);
  return DeviceDay(
    date: empty.date,
    steps: empty.steps,
    distanceKm: empty.distanceKm,
    deviceCalories: empty.deviceCalories,
    stepsReadAt: null,
    heartRate: empty.heartRate,
    heartRateSeries: empty.heartRateSeries,
    lastNight: empty.lastNight,
    metrics: empty.metrics,
    workouts: empty.workouts,
    sync: DeviceSyncStamp(
      lastCompleteSync: at.subtract(syncedAgo),
      lastAttempt: at,
      lastOutcomeId: 'complete',
    ),
    batteryPercent: 71,
  );
}

/// The whole app on the real router, starting at [location].
Widget settingsApp({
  String location = Routes.settings,
  PairedStrap? strap,
  DeviceDay? day,
  bool signedIn = false,
  String? version,
  HealthProfile? profile,
  ThemeMode? themeMode,
}) {
  final secrets = FakeSecretStore();
  return ProviderScope(
    // `Override` is not exported by `flutter_riverpod`, so the list is
    // inferred rather than annotated — the same note `_today_stubs.dart` makes.
    overrides: [
      credentialsProvider.overrideWithValue(Credentials(secrets)),
      // The data & sync screen's mirror card reads the local store; nothing
      // mirrored is its honest state in a harness with no store.
      mirrorStatsProvider.overrideWith((ref) async => MirrorStats.empty),
      pairingSummaryProvider.overrideWith(
        (ref) async => (strap: strap, zeppRemembered: false),
      ),
      serverSessionProvider.overrideWith(
        (ref) async => signedIn
            ? const ServerSessionStatus(
                signedIn: true,
                baseUrl: 'https://healthee.example.test',
              )
            : const ServerSessionStatus.signedOut(),
      ),
      deviceDayProvider.overrideWith(
        (ref) async => day ?? DeviceDay.empty(settingsDate),
      ),
      // The real read talks to a platform channel a test host never answers,
      // and its own deadline would leave a pending timer behind every widget
      // test that draws the About screen.
      appVersionProvider.overrideWith((ref) async => version),
      // Same reason as the version above, twice over: the update check reads that
      // same platform channel AND reaches GitHub. A widget test must do neither,
      // and the read's own 3 s deadline would be left pending behind every test
      // that draws About.
      updateStatusProvider.overrideWith((ref) async => const UpdateUnknown()),
      // The strap screen draws a Stop while a sync runs, so it watches the
      // controller — which opens a strap session as soon as anything does.
      syncControllerProvider.overrideWith(
        () => FixedConnection(const Disconnected()),
      ),
      pushStampProvider.overrideWith((ref) async => const PushStamp.never()),
      // The reminders and background screens read the account API and their own
      // stored preference rows. Left unpinned they reach a socket and a
      // platform store, which surfaces as "pumpAndSettle timed out" — a message
      // about the harness rather than about the screen.
      accountApiProvider.overrideWith(
        (ref) async => AccountApi(Dio(), await CacheSession.capture(null)),
      ),
      reminderPreferencesProvider.overrideWith(
        (ref) async => const ReminderPreferences(),
      ),
      backgroundPreferencesProvider.overrideWith(
        (ref) async => const BackgroundPreferences(),
      ),
      backgroundLastRunProvider.overrideWith((ref) async => null),
      healthProfileProvider.overrideWith(
        (ref) async => profile ?? const HealthProfile(),
      ),
      // Unreachable, not pinned to a payload: none of these screens is about
      // the server's view of today, and the one that peeks at it (Appearance's
      // preview) must fall silent rather than error when it cannot be had.
      todaySnapshotProvider.overrideWith(todayUnreachable()),
      if (themeMode case final ThemeMode pinned)
        themeControllerProvider.overrideWith(() => FixedTheme(pinned)),
    ],
    child: _ThemedRouter(location: location),
  );
}

/// The app under its real theme wiring, so the appearance tiles can be observed
/// changing the brightness rather than merely changing a provider.
class _ThemedRouter extends ConsumerStatefulWidget {
  const _ThemedRouter({required this.location});

  final String location;

  @override
  ConsumerState<_ThemedRouter> createState() => _ThemedRouterState();
}

class _ThemedRouterState extends ConsumerState<_ThemedRouter> {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.location,
    routes: settingsRoutes(),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ref.watch(themeControllerProvider),
    routerConfig: _router,
  );
}

/// A controller pinned to one mode, for the cases that need a starting point.
class FixedTheme extends ThemeController {
  /// [_mode] is what `build` returns, forever.
  FixedTheme(this._mode);

  final ThemeMode _mode;

  @override
  ThemeMode build() => _mode;
}

/// Gives a test a viewport tall enough to hold a whole settings screen.
void tallViewport(WidgetTester tester, {double width = 420}) {
  tester.view
    ..physicalSize = Size(width, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Scrolls [finder] into view inside the page's own list.
Future<void> revealRow(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
