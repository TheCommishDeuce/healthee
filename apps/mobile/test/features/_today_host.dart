/// The Today host every widget suite in this directory pumps.
///
/// Extracted on its second use (Standards §1). Two suites now render this
/// screen — one about what it draws, one about the connection strip in its
/// chrome — and a second copy of these overrides is a second chance to forget
/// one of them, which shows up as "pumpAndSettle timed out" rather than as
/// anything about the test.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/app.dart';
import 'package:healthee/ble/models/device_daily_totals.dart';
import 'package:healthee/ble/models/strap_sample.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/challenges/program_feed.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/honesty/last_known.dart';
import 'package:healthee/data/insights/notable_event.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_insight.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/notifications/notify_completions.dart';
import 'package:healthee/data/pairing/paired_strap.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/data/updates/update_check.dart';
import 'package:healthee/features/settings/app_version.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/app_tab_bar.dart';

import '../_sleep_stubs.dart';
import '../_today_stubs.dart';
import '../store/strap_store_test.dart' show nightOn, resultWith;

const String todayDate = '2026-08-04';
final DateTime now = DateTime(2026, 8, 4, 9, 30);

/// The screen over [store], with the day, the clock, the link and the payload
/// all pinned.
///
/// The connection is ALWAYS overridden, even when a test does not care about
/// it. The real controller opens a strap session as soon as anything watches it
/// — which is the point of the feature and exactly wrong inside a widget test,
/// where it would reach for a radio that does not exist. The lifecycle
/// behaviour has its own suite (`test/sync/foreground_lifecycle_test.dart`)
/// against a scripted device.
/// The server session is ALWAYS overridden too, and defaults to signed in. The
/// real provider reaches the platform keystore, which a `flutter test` host does
/// not have — and the data-health strip speaks up when there is no session, so
/// leaving it unpinned would make every "this section falls silent" assertion
/// depend on a plugin channel that is not there.
///
/// [reducedMotion] defaults to TRUE and almost every suite wants it — see the
/// `MediaQuery` in the body. `today_hero_test.dart` is the one that turns it off,
/// because the halo running is the thing it is about.
///
/// [home] is the screen under test and defaults to Today. Sleep, Activity, Coach
/// and Diagnostics read the SAME two providers through the same shell
/// (`shared/instrument_screen.dart`), so one host serves all five rather than
/// four more copies of these overrides.
Widget todayHost(
  LocalStore store, {
  StrapConnection? connection,
  SyncController? sync,
  TodayView? server,
  bool serverUnreachable = false,
  ThemeData? themeOverride,
  bool signedIn = true,
  bool reducedMotion = true,
  Widget? home,
  SleepPage? sleep,
  SleepConsistency? consistency,
  LastKnown<double>? lastKnownBioAge,
  List<HealthProgram> suggestedPrograms = const [],
  DatedHistory? history,
}) {
  return _scoped(
    store,
    connection: connection,
    sync: sync,
    server: server,
    serverUnreachable: serverUnreachable,
    signedIn: signedIn,
    sleep: sleep,
    consistency: consistency,
    lastKnownBioAge: lastKnownBioAge, suggestedPrograms: suggestedPrograms,
    history: history,
    child: MaterialApp(
      theme: themeOverride ?? AppTheme.light,
      // **Reduced motion, always.** Today's hero carries `BioHalo`, an ambient
      // particle field on a 30 fps ticker — a screen containing a running one
      // never becomes idle, so every `pumpAndSettle` in every suite that pumps
      // this screen would time out. `bio_halo.dart` reads
      // `MediaQuery.disableAnimations` and stops dead under it, which is the
      // same path a phone with the accessibility setting on takes. The halo's
      // own motion has its own suite (`test/shared/instruments/`), against a
      // pumped clock rather than a settled tree.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: home ?? TodayScreen(now: now),
    ),
  );
}

/// The whole app on its REAL router, so tab switching is the real thing.
///
/// [todayHost] pumps one screen with no router at all, which is right for asking
/// what a screen draws and useless for asking what a tab switch costs. The
/// pairing summary is pinned to a paired strap because `buildRouter` redirects an
/// unpaired app to `/pairing` — a test of the tab shell would otherwise never see
/// a tab.
Widget routedApp(LocalStore store) {
  // `HealtheeApp` builds its own `MaterialApp`, which installs
  // `MediaQuery.fromView` and overrides anything wrapped around it — so the
  // reduced-motion switch `todayHost` uses cannot be reached from out here.
  // The platform dispatcher is where that `MediaQuery` reads the flag from, and
  // the binding clears its test values after every test.
  //
  // Same reason as `todayHost`: Today's hero halo never lets a tree settle.
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  return _scoped(store, paired: true, child: const HealtheeApp());
}

/// The overrides that keep a widget test off the network and off the keystore,
/// wrapped around [child].
///
/// A wrapper rather than a returned override list, for the reason
/// `_today_stubs.dart` already records: `Override` is not exported by
/// `flutter_riverpod`, and reaching past that boundary to save a parameter is not
/// worth it. Extracted on its second use (Standards §1) — a second copy of these
/// is a second chance to forget one, which surfaces as "pumpAndSettle timed out"
/// rather than as anything about the test.
Widget _scoped(
  LocalStore store, {
  required Widget child,
  StrapConnection? connection,
  SyncController? sync,
  TodayView? server,
  bool serverUnreachable = false,
  bool signedIn = true,
  bool paired = false,
  SleepPage? sleep,
  SleepConsistency? consistency,
  LastKnown<double>? lastKnownBioAge,
  List<HealthProgram> suggestedPrograms = const [],
  DatedHistory? history,
}) {
  return ProviderScope(
    overrides: [
      // ALWAYS overridden, defaulting to "this phone holds no earlier value".
      // The real provider walks the cached-payload table through
      // `TodayRepository`, which reaches `credentialsProvider` and the api
      // client — a keystore and a socket a `flutter test` host does not have.
      // The walk has its own suite (`test/store/last_known_test.dart`).
      lastKnownBiologicalAgeProvider.overrideWith(
        (ref) async => lastKnownBioAge,
      ),
      challengeFeedProvider.overrideWith(
        (ref) => Stream.value(
          ServerSnapshot(
            const ChallengeFeed(
              active: [],
              suggested: [],
              recent: [],
              maxActive: 3,
            ),
            fetchedAt: now,
          ),
        ),
      ),
      programFeedProvider.overrideWith(
        (ref) => Stream.value(
          ServerSnapshot(
            ProgramFeed(active: null, suggested: suggestedPrograms, recent: const []),
            fetchedAt: now,
          ),
        ),
      ),
      notifyCompletionsProvider().overrideWith((ref) async {}),
      notableEventsProvider.overrideWith(
        (ref) => Stream.value(ServerSnapshot(<NotableEvent>[], fetchedAt: now)),
      ),
      commitmentRepositoryProvider.overrideWith(
        (ref) async => CommitmentRepository(
          AccountApi(Dio(), await CacheSession.capture(null)),
        ),
      ),
      localStoreProvider.overrideWithValue(store),
      todayProvider.overrideWithValue(todayDate),
      syncControllerProvider.overrideWith(
        () => sync ?? FixedConnection(connection ?? const Disconnected()),
      ),
      serverSessionProvider.overrideWith(
        (ref) async => signedIn
            ? const ServerSessionStatus(
                signedIn: true,
                baseUrl: 'https://healthee.example.com',
              )
            : const ServerSessionStatus.signedOut(),
      ),
      // **The override answers PER DAY, exactly as the endpoint does.** A fixed
      // payload dated today would be no answer at all on a past day now — the
      // shell drops a payload that is about a different day than the one being
      // read — and the screen would sit on its loading card forever, which reads
      // in a widget test as `pumpAndSettle timed out` and says nothing about why.
      //
      // A `server` handed in explicitly still wins whole: a test that built its
      // own payload is asserting something about THAT payload.
      todaySnapshotProvider.overrideWith(
        serverUnreachable
            ? todayUnreachable()
            : (server != null
                  ? todayIs(server)
                  : (ref) async => todayViewFor(
                      ref.watch(viewDateProvider),
                      today: todayDate,
                    )),
      ),
      // Settings is reachable from Today now, and its About row reads a platform
      // channel a test host never answers — which would leave that read's own
      // deadline pending after any test that navigated there.
      appVersionProvider.overrideWith((ref) async => null),
      // Same reason as the version above, twice over: the update check reads that
      // same platform channel AND reaches GitHub. A widget test must do neither,
      // and the read's own 3 s deadline would be left pending behind every test
      // that draws About.
      updateStatusProvider.overrideWith((ref) async => const UpdateUnknown()),
      // The batched dated series, ALWAYS pinned. The real provider is only
      // watched on a past day, but on a past day it reaches a socket — and an
      // unpinned read there leaves a spinner running that `pumpAndSettle` waits
      // on forever, which reads as a broken test rather than as a missing
      // override. Empty by default: a suite about what a screen DECIDES does
      // not need readings, and a suite about the panels passes its own.
      datedHistoryProvider.overrideWith(
        (ref) async => serverUnreachable
            ? throw StateError('no server')
            : history ??
                  const DatedHistory(
                    days: 90,
                    series: <String, List<TrendPoint>>{},
                  ),
      ),
      // Sleep reads three payloads of its own — `/api/sleep`,
      // `/api/sleep/consistency` and `/api/sleep/insight`. All three are
      // pinned for the same reason the Today one is: an unpinned provider
      // reaches for a socket and fails as "pumpAndSettle timed out", which
      // says nothing about the test. The insight defaults to LOCKED so no
      // suite leaves a spinner running that `pumpAndSettle` will wait on.
      sleepPageProvider.overrideWith(
        (ref) async => serverUnreachable
            ? throw StateError('no server')
            : sleep ?? sleepPageFixture(),
      ),
      sleepConsistencyProvider.overrideWith(
        (ref) async => serverUnreachable
            ? throw StateError('no server')
            : consistency ?? consistencyFixture(),
      ),
      sleepInsightProvider.overrideWith(
        (ref) async => const SleepInsight.locked(),
      ),
      if (paired)
        pairingSummaryProvider.overrideWith(
          (ref) async => (
            strap: const PairedStrap(
              mac: 'C0:FF:EE:00:00:01',
              authKey: '000102030405060708090a0b0c0d0e0f',
            ),
            zeppRemembered: false,
          ),
        ),
    ],
    child: child,
  );
}

/// A controller pinned to one state, so each case can be rendered on its own.
///
/// Public because Settings watches `syncControllerProvider` too now (its strap
/// row draws a Stop while a sync is running), so a second suite needs the same
/// override — and the real controller reaches for a radio and a platform store
/// the moment anything watches it.
class FixedConnection extends SyncController {
  /// [_state] is what `build` returns, forever.
  FixedConnection(this._state);

  final StrapConnection _state;

  @override
  StrapConnection build() => _state;
}

/// Seeds one ordinary day of strap measurements.
Future<void> seedDevice(LocalStore store) async {
  await store.strapWriter.saveSync(
    resultWith(
      totals: DeviceDailyTotals(
        steps: 9264,
        distanceM: 6710,
        calories: 412,
        readAt: DateTime(2026, 8, 4, 9, 12),
      ),
      samples: [
        StrapSample(DateTime(2026, 8, 4, 7), 'hr', 61),
        StrapSample(DateTime(2026, 8, 4, 9), 'hr', 68),
        StrapSample(DateTime(2026, 8, 4, 8), 'hrv', 47),
      ],
      sleep: [nightOn(DateTime(2026, 8, 3, 23, 40))],
      battery: 71,
    ),
  );
  await store.strapWriter.stampAttempt(
    at: DateTime(2026, 8, 4, 9, 12),
    outcomeId: 'complete',
    complete: true,
  );
}

/// Scrolls until [finder] is on screen. The list is a `ListView.builder`, so
/// most of Today is not built until it is needed — which is the point of it.
Future<void> reveal(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      400,
      // The page's own list, explicitly. Today's chapter nav is a horizontal
      // `SingleChildScrollView` inside it (`chapter.dart` says why), so the
      // default `find.byType(Scrollable)` resolves two and throws before it
      // scrolls anything. The outer list is an ancestor, so it is first.
      scrollable: find.byType(Scrollable).first,
    );

/// Taps the tab named [label], **scoped to the bar**.
///
/// `find.text('Sleep')` used to be unique while Today was drawing one screen of
/// index cards. It is not since the legacy port: the recovery card has a factor
/// row called "Sleep" and the signal ladder a marker called "Sleep duration".
/// The bar is the only place any of those words is a control, so that is where a
/// test taps.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Moves the screen to [iso] the way the owner now does.
///
/// **The two chevrons are gone.** The day is a pill that opens the month grid,
/// and the grid is the control — `Latest`, the retention window and every day
/// in it, in one place, instead of one day per press. Every test that used to
/// press `date.previous` presses a cell here instead; the claim each was making
/// is unchanged.
Future<void> chooseDay(WidgetTester tester, String iso) async {
  await tester.tap(find.byType(DayPill));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('calendar.$iso')));
  await tester.pumpAndSettle();
}

/// Opens the month grid and leaves it open.
Future<void> openCalendar(WidgetTester tester) async {
  await tester.tap(find.byType(DayPill));
  await tester.pumpAndSettle();
}
