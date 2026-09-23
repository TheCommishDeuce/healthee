/// Weigh-ins stored on the phone first, uploaded when the server can take them.
///
/// DESIGN_DECISIONS A8. The same guarantee the strap outbox gives a reading,
/// for the one thing the owner types in: an entry is written to the local store
/// BEFORE any upload is attempted, removed only after the server confirmed it,
/// and retried by [flush] on every foreground push. A response lost after the
/// server committed is harmless — the retry carries the same observation instant
/// and the server upserts on `(owner, instant)`.
///
/// Rows are not tied to a sign-in, like the strap's pending rows: re-enrolling
/// the same owner uploads them with the new credential. Signing a phone into a
/// DIFFERENT owner would upload them there too — the same known limit the strap
/// outbox has, recorded in `docs/REVIEW_PLAN.md`.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/log_draft.dart';
import 'package:healthee/data/journal/log_kind.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'weight_outbox.g.dart';

/// Whether [error] is the server REFUSING an entry, which no retry will change.
///
/// A 4xx that is not about the credential, a timeout or a rate limit, or the
/// server's own `ok: false` (surfaced by [JournalRepository] as a
/// [FormatException]). Everything else — no connection, a 5xx, a refused or
/// expired credential — is the server not being able to take it YET, so the
/// entry stays held.
bool isPermanentRefusal(Object error) {
  if (error is FormatException) return true;
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status != null &&
        status >= 400 &&
        status < 500 &&
        !const <int>{401, 403, 408, 429}.contains(status);
  }
  return false;
}

/// What one [WeightOutbox.flush] did.
class WeightFlush {
  /// Counts only; the entries themselves stay in the store.
  const WeightFlush({
    required this.sent,
    required this.remaining,
    this.refused = 0,
  });

  /// Entries the server confirmed during this flush.
  final int sent;

  /// Entries still held after it.
  final int remaining;

  /// Entries the server refused outright, and which were therefore dropped.
  final int refused;
}

/// The weigh-in outbox over the local store.
class WeightOutbox {
  /// Reads and writes [LocalStore.pendingWeights].
  const WeightOutbox(this._store);

  final LocalStore _store;

  /// Stores [draft] durably. Throws [FormatException] for anything that is not
  /// a valid weigh-in, so nothing invalid can wait in the queue for a retry that
  /// will never succeed. Holding the same instant twice keeps the newer weight.
  Future<void> hold(LogDraft draft, {DateTime? now}) async {
    final moment = now ?? DateTime.now();
    if (draft.kind != LogKind.weight) {
      throw const FormatException('Only weigh-ins are held on this phone.');
    }
    final problem = draft.validate(moment);
    if (problem != null) throw FormatException(problem);
    await _store
        .into(_store.pendingWeights)
        .insertOnConflictUpdate(
          PendingWeightsCompanion.insert(
            atMs: Value(draft.at.millisecondsSinceEpoch),
            kg: draft.amount!,
            heldAtMs: moment.millisecondsSinceEpoch,
          ),
        );
  }

  /// Forgets the entry observed at [at] — call only after the server confirmed it.
  Future<void> release(DateTime at) => (_store.delete(
    _store.pendingWeights,
  )..where((row) => row.atMs.equals(at.millisecondsSinceEpoch))).go();

  /// Every held entry, oldest observation first.
  Future<List<LogDraft>> pending() async {
    final rows = await (_store.select(
      _store.pendingWeights,
    )..orderBy([(row) => OrderingTerm.asc(row.atMs)])).get();
    return <LogDraft>[
      for (final row in rows)
        LogDraft(
          kind: LogKind.weight,
          at: DateTime.fromMillisecondsSinceEpoch(row.atMs),
          amount: row.kg,
        ),
    ];
  }

  /// How many entries are waiting.
  Future<int> count() async => (await pending()).length;

  /// Uploads held entries oldest first, stopping at the first failure that a
  /// retry could fix.
  ///
  /// Stopping keeps the owner's order and avoids hammering a server that is
  /// down. A permanent refusal ([isPermanentRefusal]) is different: the entry
  /// can never be accepted, so it is dropped — logged, and counted in
  /// [WeightFlush.refused] — rather than blocking every newer weigh-in behind
  /// it. [LogDraft.validate] mirrors the server's bounds, so this is the
  /// exception, not the path.
  Future<WeightFlush> flush(JournalRepository repository) async {
    final held = await pending();
    var sent = 0;
    var refused = 0;
    for (final draft in held) {
      try {
        await repository.save(draft);
        sent++;
      } on Exception catch (error, stack) {
        AppLog.failure('weight', 'uploading a held weigh-in', error, stack);
        if (!isPermanentRefusal(error)) break;
        refused++;
      }
      await release(draft.at);
    }
    return WeightFlush(
      sent: sent,
      refused: refused,
      remaining: held.length - sent - refused,
    );
  }
}

/// The app's [WeightOutbox].
@Riverpod(keepAlive: true)
WeightOutbox weightOutbox(Ref ref) =>
    WeightOutbox(ref.watch(localStoreProvider));

/// How many weigh-ins are waiting to upload.
///
/// A read, not a drift `watch()` stream (nothing in this app uses one, and its
/// cancel timer outlives a widget test): whoever changes the outbox — the weight
/// sheet and the foreground push — invalidates this.
@riverpod
Future<int> pendingWeightCount(Ref ref) =>
    ref.watch(weightOutboxProvider).count();
