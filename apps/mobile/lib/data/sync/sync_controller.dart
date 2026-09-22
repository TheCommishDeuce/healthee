/// The app's live connection state, and the one way to start or stop a sync.
///
/// Thin on purpose. Everything that decides anything is in [SyncEngine] and
/// [ForegroundLink]; this holds the current [StrapConnection], forbids two syncs
/// at once, wires the lifecycle to the link, and tells the screen to re-read the
/// store when a sync finishes. Keeping the decisions out of a Riverpod notifier
/// is what lets both be tested against a fake strap and a real in-memory
/// database with no container at all.
///
/// `keepAlive` for two reasons now. A sync outlives the screen that started it —
/// a controller disposed on navigation would drop its state mid-handshake and
/// leave the strap holding a session nobody is going to close. And the held
/// foreground link is an app-level fact, not a screen-level one: tying it to a
/// widget would release the strap on every navigation.
///
/// ## One owner of the state, two producers
///
/// [ForegroundLink] publishes while it is opening or holding a session;
/// [SyncEngine] publishes while a pull is running. They cannot overlap: a sync
/// is refused while [StrapConnection.isBusy], and the link never opens a second
/// session while it holds one. When a sync over the held session fails, the
/// session is invalidated rather than kept — the state has just said the link
/// failed, and continuing to hold a session behind that would be the two
/// disagreeing.
///
/// ## Coming to the front does two things now
///
/// It always opens the link. It *also* starts a sync, unasked, when
/// [AutoSyncGate] allows one — which is what makes "Sync now" a button the owner
/// may press rather than one they must. The two entry points are separate on
/// purpose: [autoSyncNow] is debounced, [syncNow] never is. An explicit request
/// is not a heuristic, and a heuristic that could be triggered by asking would
/// make the button feel broken exactly when someone reached for it.
library;

import 'dart:async';

import 'package:healthee/ble/strap_client.dart';
import 'package:healthee/ble/strap_scanner.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/weight_outbox.dart';
import 'package:healthee/data/push/push_outcome.dart';
import 'package:healthee/data/push/push_service.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/sync/auto_sync.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/device_lease.dart';
import 'package:healthee/data/sync/foreground_link.dart';
import 'package:healthee/data/sync/foreground_watch.dart';
import 'package:healthee/data/sync/sync_engine.dart';
import 'package:healthee/data/sync/sync_outcome.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_controller.g.dart';

/// The app's sync engine, wired to the one client, store and scanner.
@Riverpod(keepAlive: true)
SyncEngine syncEngine(Ref ref) => SyncEngine(
  client: ref.watch(strapClientProvider),
  store: ref.watch(localStoreProvider),
  scanner: ref.watch(strapScannerProvider),
);

/// The wall clock, as a provider so a test can pin it.
///
/// Overriding `DateTime.now` is not possible and a test that waited out a
/// fifteen-minute window would not be a test. Everything time-dependent in this
/// file reads the clock through here.
@Riverpod(keepAlive: true)
DateTime Function() syncClock(Ref ref) => DateTime.now;

/// The debounce, reading the persisted "last complete sync" stamp.
@Riverpod(keepAlive: true)
AutoSyncGate autoSyncGate(Ref ref) => AutoSyncGate(
  lastCompleteSync: ref.watch(localStoreProvider).strapWriter.lastCompleteSync,
  now: ref.watch(syncClockProvider),
);

/// Holds what the link to the strap is doing, and drives it.
@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  SyncCancelToken? _token;
  ForegroundLink? _link;

  /// A phone that has just launched has no session open, and says so.
  ///
  /// Not "connected because we are paired" — that is the claim
  /// `connection_state.dart` exists to make unrepresentable. The link is asked
  /// to open one immediately afterwards, and publishes the truth as it goes.
  @override
  StrapConnection build() {
    final link = ForegroundLink(
      lease: DeviceLease(ref.watch(localStoreProvider)),
      client: ref.watch(strapClientProvider),
      scanner: ref.watch(strapScannerProvider),
      lastCompleteSync: ref
          .watch(localStoreProvider)
          .strapWriter
          .lastCompleteSync,
      onState: (next) => state = next,
    );
    final watch = ForegroundWatch(
      onForeground: () => unawaited(_cameToFront(link)),
      onBackground: () => unawaited(link.toBackground()),
    );
    _link = link;
    ref.onDispose(() {
      watch.dispose();
      unawaited(link.dispose());
    });
    // Deferred by a microtask, not called here: [ForegroundWatch.start] reports
    // the state the app is already in, and that report sets `state` — which a
    // notifier may not do from inside its own `build`.
    scheduleMicrotask(watch.start);
    return const Disconnected();
  }

  /// Opens the link, then syncs if the gate allows — the whole of "automatic".
  ///
  /// Sequenced rather than concurrent: the gate asks whether a session is held,
  /// and a session is held only once [ForegroundLink.toForeground] has finished
  /// its scan and handshake. Asking first would answer "no link" every time and
  /// nothing would ever sync unasked.
  ///
  /// A foreground that fails to connect syncs nothing and says nothing extra:
  /// the data-health card is already showing the named failure and its remedy,
  /// and the link's own backoff owns the retry.
  Future<void> _cameToFront(ForegroundLink link) async {
    await link.toForeground();
    await autoSyncNow();
  }

  /// Starts a sync the owner did not ask for, if [AutoSyncGate] allows one.
  ///
  /// The debounced entry point, and the ONLY debounced one. Every refusal is
  /// logged with its reason: a foreground that quietly does nothing is
  /// indistinguishable from a foreground that is broken, and this is background
  /// work, which Standards §1 requires to reach a surface rather than vanish.
  Future<SyncOutcome?> autoSyncNow() async {
    final decision = await ref
        .read(autoSyncGateProvider)
        .decide(linkHeld: holdsSession, busy: state.isBusy);
    if (!decision.shouldStart) {
      AppLog.info('sync', 'no automatic sync: ${decision.name}');
      return null;
    }
    AppLog.info('sync', 'starting an automatic sync — nobody asked');
    return syncNow();
  }

  /// Runs one sync, publishing every state it passes through.
  ///
  /// A no-op while one is already running: the strap accepts a single
  /// connection at a time, so a second attempt would fail on the radio and
  /// report a confusing "couldn't connect" for a strap that is right there and
  /// busy talking to us.
  ///
  /// **Never debounced.** This is what "Sync now" calls, and a button that
  /// silently declines because a heuristic says it is too soon is a button the
  /// owner learns not to trust. [autoSyncNow] is the entry point the window
  /// applies to.
  ///
  /// Near-instant while the app is in front, because the held session skips
  /// both the twelve-second scan and the handshake.
  ///
  /// ## The push runs after, and cannot undo the pull
  ///
  /// A sync now has two halves — read the strap, then send what is stored — and
  /// they are deliberately not one operation. The pull's success is already
  /// recorded by the time the push starts, so a server that is down cannot make
  /// a good sync look failed, and the measurements are on disk either way. The
  /// push reports itself through its own health surface (`PushStamp`), which is
  /// where a background failure belongs (Standards §1).
  Future<SyncOutcome?> syncNow() async {
    // `_token != null` and not `state.isBusy` alone. The state is published by
    // the engine, which does not get to run until this method's first await, so
    // between the call and that point `isBusy` is still false and a second
    // caller walks straight past the guard into a second session on a radio
    // that accepts one. That window was unreachable while the only caller was a
    // button; a foreground transition that syncs on its own can now land in it
    // beside a pull-to-refresh. The token is set synchronously below, so it
    // closes the window rather than narrowing it.
    if (state.isBusy || _token != null) {
      return null;
    }
    final token = SyncCancelToken();
    _token = token;
    final link = _link;
    try {
      final outcome = await ref
          .read(syncEngineProvider)
          .run(
            today: ref.read(todayProvider),
            onState: (next) => state = next,
            cancel: token,
            session: link?.held,
          );
      if (outcome is SyncFailed && link != null) {
        // The session we were handed did not carry a sync. Keeping it would
        // mean the chrome showing a failure over a link we still claim.
        await link.invalidate(outcome.failure);
      }
      return outcome;
    } finally {
      _token = null;
      // Whatever happened, the store may have moved. Re-reading is cheap and
      // reading stale is the failure this app is built against.
      ref.invalidate(deviceDayProvider);
      await pushNow();
    }
  }

  /// Sends everything the local tier is holding back, then re-reads Today.
  ///
  /// Separate from [syncNow] and callable on its own, because the two fail
  /// independently: a phone with no Bluetooth but a good network should still
  /// clear its backlog, and a phone with a strap in range but no signal should
  /// still store what it reads.
  ///
  /// [PushService.drain] rather than a single `run`, because a run stops at its
  /// own page cap: a phone holding tens of thousands of samples sent 80,000 and
  /// then waited for somebody to press a button again. The drain's termination
  /// argument is in `push_service.dart` — it repeats only while the pending
  /// count is verifiably falling.
  ///
  /// Returns the outcome so a caller can show it; it is stamped into the store
  /// regardless, so a caller that ignores it still leaves the health surface
  /// truthful.
  Future<PushOutcome> pushNow() async {
    final outcome = await ref.read(pushServiceProvider).drain();
    final weighIns = await _flushWeighIns();
    if (outcome.rowsSent > 0 || weighIns > 0) {
      // The server has new measurements, so its derived numbers have moved.
      // Invalidating only when something was actually sent keeps a failed push
      // from re-fetching a payload that cannot have changed.
      ref.invalidate(todaySnapshotProvider);
    }
    return outcome;
  }

  /// Uploads weigh-ins held on the phone (DESIGN_DECISIONS A8); how many landed.
  ///
  /// Beside the strap push because both are "what this phone is holding back",
  /// but not inside it: weigh-ins go to `/api/log`, and a phone that is not
  /// signed in has no repository to send them with — which is a quiet 0 here,
  /// not a fault, exactly as the strap push treats a missing token.
  Future<int> _flushWeighIns() async {
    final outbox = ref.read(weightOutboxProvider);
    final JournalRepository repository;
    try {
      // Nothing held is the usual case, and no session means nothing to send
      // with — a request without one would 401 and mark the session rejected.
      if ((await outbox.pending()).isEmpty ||
          await ref.read(credentialsProvider).serverSession() == null) {
        return 0;
      }
      repository = await ref.read(journalRepositoryProvider.future);
    } on Exception catch (error, stack) {
      AppLog.failure('weight', 'opening the weigh-in upload', error, stack);
      return 0;
    }
    final flushed = await outbox.flush(repository);
    ref.invalidate(pendingWeightCountProvider);
    if (flushed.sent > 0) ref.invalidate(journalFeedProvider);
    return flushed.sent;
  }

  /// Asks the running sync to stop at its next phase boundary.
  ///
  /// Not an abort. `sync_engine.dart` says why the activity-fetch rounds cannot
  /// be interrupted mid-flight, and what is kept when a run is stopped.
  void cancel() => _token?.cancel();

  /// The session held for the foreground, or null. For tests and for the chrome.
  ///
  /// Exposed so `a backgrounded app holds no session` can be ASSERTED rather
  /// than assumed — the one claim in this feature that cannot be checked from
  /// the outside.
  bool get holdsSession => _link?.held != null;
}
