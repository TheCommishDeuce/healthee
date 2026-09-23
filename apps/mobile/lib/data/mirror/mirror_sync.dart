/// Downloads the owner's full history onto the phone (`docs/MIRROR.md`).
///
/// DESIGN_DECISIONS A2. The server lists every stream's months with a digest;
/// this fetches the months whose digest differs from the stored one, replaces
/// each whole, and deletes months the server no longer lists. Each month is its
/// own write, so a run stopped at any point — no signal, app killed — resumes on
/// the next run by comparing digests again, and repeating a finished run fetches
/// nothing.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/mirror/mirror_manifest.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mirror_sync.g.dart';

/// The `sync_meta` key naming the owner whose history is mirrored.
const String kMirrorOwnerKey = 'mirror_owner';

/// What one run did. Counts only.
@immutable
class MirrorRun {
  /// All fields required.
  const MirrorRun({
    required this.fetched,
    required this.fetchedMonths,
    required this.unchanged,
    required this.removed,
  });

  /// Stream-months downloaded because they were new or had changed.
  final int fetched;

  /// Distinct calendar months among [fetched] — what a person calls "months".
  /// Three streams for September are three fetches and one month.
  final int fetchedMonths;

  /// Stream-months already current, so not downloaded.
  final int unchanged;

  /// Stream-months deleted because the server no longer lists them.
  final int removed;
}

/// How much history the phone holds for its owner.
@immutable
class MirrorStats {
  /// All fields required.
  const MirrorStats({
    required this.months,
    required this.rows,
    required this.bytes,
    required this.lastSynced,
  });

  /// Nothing mirrored.
  static const MirrorStats empty = MirrorStats(
    months: 0,
    rows: 0,
    bytes: 0,
    lastSynced: null,
  );

  /// Distinct calendar months held, whichever streams cover them. Not
  /// stream-months: history spanning August and September is two months even
  /// when five streams each hold both (B3).
  final int months;

  /// Rows across them.
  final int rows;

  /// Stored payload size, in bytes of JSON text.
  final int bytes;

  /// When a month was last written, or null when none ever was.
  final DateTime? lastSynced;
}

/// The mirror over the local store.
class MirrorSync {
  /// Reads and writes [LocalStore.mirrorMonths].
  const MirrorSync(this._store);

  final LocalStore _store;

  /// Brings the phone's copy up to the server's. Throws what the API throws;
  /// every month written before a failure stays written.
  Future<MirrorRun> run(AccountApi api, {DateTime? now}) async {
    final account = await api.get('/api/account');
    final owner = account['user_id'];
    if (owner is! String || owner.isEmpty) {
      throw const FormatException(
        'the server did not say whose account this is',
      );
    }
    final manifest = MirrorManifest.fromJson(
      await api.get('/api/mirror/manifest'),
    );
    final held = <String, MirrorMonthRow>{
      for (final row in await (_store.select(
        _store.mirrorMonths,
      )..where((r) => r.owner.equals(owner))).get())
        '${row.stream}/${row.month}': row,
    };
    var fetched = 0;
    final fetchedMonths = <String>{};
    var unchanged = 0;
    for (final MapEntry(key: stream, value: months)
        in manifest.streams.entries) {
      for (final month in months) {
        final stored = held.remove('$stream/${month.month}');
        if (stored != null &&
            stored.digest == month.digest &&
            stored.version == manifest.version) {
          unchanged++;
          continue;
        }
        await _fetch(api, owner, stream, month.month, manifest.version, now);
        fetched++;
        fetchedMonths.add(month.month);
      }
    }
    // Whatever is left was not in the manifest: the server no longer has it.
    for (final gone in held.values) {
      await (_store.delete(_store.mirrorMonths)..where(
            (r) =>
                r.owner.equals(owner) &
                r.stream.equals(gone.stream) &
                r.month.equals(gone.month),
          ))
          .go();
    }
    await _store
        .into(_store.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(name: kMirrorOwnerKey, value: owner),
        );
    return MirrorRun(
      fetched: fetched,
      fetchedMonths: fetchedMonths.length,
      unchanged: unchanged,
      removed: held.length,
    );
  }

  Future<void> _fetch(
    AccountApi api,
    String owner,
    String stream,
    String month,
    int version,
    DateTime? now,
  ) async {
    final reply = await api.get(
      '/api/mirror/$stream',
      query: <String, Object?>{'month': month},
    );
    final items = reply['items'];
    final digest = reply['digest'];
    final rows = reply['rows'];
    if (items is! List<Object?> || rows is! int) {
      throw const FormatException('a mirror month this app cannot read');
    }
    // A month the server emptied between the manifest and this read has no
    // digest; storing it would only be deleted by the next run.
    if (digest is! String) return;
    await _store
        .into(_store.mirrorMonths)
        .insertOnConflictUpdate(
          MirrorMonthsCompanion.insert(
            owner: owner,
            stream: stream,
            month: month,
            digest: digest,
            rows: rows,
            version: version,
            payload: jsonEncode(items),
            syncedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch,
          ),
        );
  }

  /// What the phone holds for the owner it last mirrored, or [MirrorStats.empty].
  Future<MirrorStats> stats() async {
    final meta = await (_store.select(
      _store.syncMeta,
    )..where((r) => r.name.equals(kMirrorOwnerKey))).getSingleOrNull();
    if (meta == null) return MirrorStats.empty;
    final rows = await (_store.select(
      _store.mirrorMonths,
    )..where((r) => r.owner.equals(meta.value))).get();
    if (rows.isEmpty) return MirrorStats.empty;
    return MirrorStats(
      months: rows.map((row) => row.month).toSet().length,
      rows: rows.fold(0, (sum, row) => sum + row.rows),
      bytes: rows.fold(0, (sum, row) => sum + utf8.encode(row.payload).length),
      lastSynced: DateTime.fromMillisecondsSinceEpoch(
        rows.map((row) => row.syncedAtMs).reduce((a, b) => a > b ? a : b),
      ),
    );
  }
}

/// The app's [MirrorSync].
@Riverpod(keepAlive: true)
MirrorSync mirrorSync(Ref ref) => MirrorSync(ref.watch(localStoreProvider));

/// What is mirrored; invalidated after a run.
@riverpod
Future<MirrorStats> mirrorStats(Ref ref) =>
    ref.watch(mirrorSyncProvider).stats();
