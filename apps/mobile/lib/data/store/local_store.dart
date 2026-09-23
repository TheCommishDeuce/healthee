/// The on-device 60-day tier: what the app can render before the network answers.
///
/// ## Why drift and not raw sqflite
///
/// Engineering Standards §3 requires typed models at the data boundary — "feature
/// code never reads raw `Map<String, dynamic>`". A hand-rolled sqflite layer hands
/// back exactly that map and asks every call site to remember the column names.
/// drift generates a row class per table and checks the queries at build time, so
/// the same guarantee the API models give us at the wire boundary holds at the
/// storage boundary too, and a renamed column is a compile error rather than a
/// null at 6 a.m.
///
/// ## What this table stores, and what it deliberately does not
///
/// One row per (day, metric): the **payload as the server sent it**, kept whole.
/// It is not a shredded copy of the server's schema — that would be a second
/// definition of every metric, which is the failure CLAUDE.md names first ("ONE
/// canonical definition per metric"). The cache holds bytes and dates; meaning
/// stays in [package:healthee/data/models] and is re-derived on read by the same
/// parser the network path uses. A cache that parses differently from the network
/// is a cache that can show a number the server never sent.
///
/// The 60-day horizon is a product decision from `docs/ARCHITECTURE.md`, enforced
/// in one place — [LocalStore.pruneBeyondHorizon] — for the same reason the
/// server keeps its freshness horizons in one module: a retention window that two
/// call sites can disagree about is a window nobody can state. The two day
/// windows and their arithmetic live at the bottom of this file; what they mean
/// per table, and why a measurement outlives them, is `horizon_prune.dart`.
library;

import 'package:drift/drift.dart';
import 'package:healthee/data/store/connection.dart';
import 'package:healthee/data/store/gps_tables.dart';
import 'package:healthee/data/store/horizon_prune.dart';
import 'package:healthee/data/store/mirror_table.dart';
import 'package:healthee/data/store/prune_report.dart';
import 'package:healthee/data/store/push_reader.dart';
import 'package:healthee/data/store/strap_reader.dart';
import 'package:healthee/data/store/strap_writer.dart';
import 'package:healthee/data/store/tables.dart';
import 'package:healthee/data/store/weight_outbox_table.dart';

part 'local_store.g.dart';

/// How many days of history the device keeps. Beyond this the app asks the server.
///
/// **This is a READ horizon, not a delete-by date.** A row the server has
/// acknowledged is dropped here; a measurement the server has never seen is
/// kept past it. See `horizon_prune.dart`.
const int localHorizonDays = 60;

/// How long an unsent per-minute sample is kept past [localHorizonDays].
///
/// One year, and `horizon_prune.dart`'s docstring is where the number is argued
/// — briefly: no transient cause of a stuck push queue lasts a year, the owner
/// has been shown a loud line about it every day of that year, and the measured
/// ceiling is ~240 MB. It is the only bound in this app that can end a
/// measurement's life, and doing so is counted, dated and surfaced.
const int kUnsentSampleRetentionDays = 365;

/// One cached server payload, keyed by the day it describes and the metric it is.
///
/// ## `day` is TEXT, and that is the whole point
///
/// A server payload is a claim about an owner-local **calendar date** — never an
/// instant. Those are different types and this repo has shipped the confusion
/// twice. drift's `dateTime()` column makes the mistake for you: it stores a Unix
/// timestamp and hands it back in the *device's* local zone, so a date written as
/// `2026-06-01Z` reads back as `2026-06-01 05:30` in Asia/Kolkata and as
/// `2026-05-31 19:00` in America/Denver. The row would then be filed, compared and
/// pruned under a different day depending on where the phone was — and the test
/// suite would only catch it in one of the two timezones CI runs.
///
/// So the key is the ISO date string the server itself sent, stored verbatim.
/// `YYYY-MM-DD` sorts lexicographically exactly as it sorts chronologically, so
/// range queries and the horizon prune below work directly on it. There is no
/// conversion, therefore no zone, therefore nothing to get wrong.
@DataClassName('CachedPayload')
class CachedPayloads extends Table {
  /// Opaque sign-in namespace. No token or personal identifier is stored here.
  TextColumn get scope => text().withDefault(const Constant(''))();

  /// The owner-local calendar date this payload describes, as `YYYY-MM-DD`.
  TextColumn get day => text().withLength(min: 10, max: 10)();

  /// Which payload it is — `today`, `sleep`, `activity`, … (the endpoint's name).
  TextColumn get metric => text().withLength(min: 1, max: 64)();

  /// The response body, verbatim, as JSON text.
  TextColumn get payload => text()();

  /// When we received it. A genuine instant, so a DateTime is the right type
  /// here — and `storeDateTimeAsText` below keeps it in UTC across the round
  /// trip. It drives staleness display, never correctness.
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {scope, day, metric};
}

/// The device's local tier — the server's cache AND the strap's own raw record.
///
/// ONE instance, provided by [localStoreProvider] — never constructed in a
/// widget. The two halves live in one database on purpose: they share the 60-day
/// horizon, and a retention window applied by two schedulers to two files is a
/// window nobody can state.
@DriftDatabase(
  tables: [
    CachedPayloads,
    StrapSamples,
    SleepSessions,
    StoredWorkouts,
    DeviceTotals,
    SyncMeta,
    GpsRecordings,
    GpsFixes,
    PendingWeights,
    MirrorMonths,
  ],
  daos: [StrapWriter, StrapReader, PushReader, HorizonPrune],
)
class LocalStore extends _$LocalStore {
  /// Opens the app's on-disk database.
  LocalStore() : super(openLocalStore());

  /// Opens a throwaway in-memory database. Tests only.
  LocalStore.memory() : super(openInMemory());

  /// Opens a database in a real file. Tests only — see [openFileAt] for the one
  /// kind of claim that needs it.
  LocalStore.at(String path) : super(openFileAt(path));

  @override
  int get schemaVersion => 9;

  /// v1 → v2 added the five raw-strap tables beside the payload cache.
  /// v2 → v3 added the per-row push marker to the four measurement tables.
  ///
  /// v5 → v6 added two tables for the interactive coach's conversations.
  /// v6 → v7 drops them again: the coach UI was removed (DESIGN_DECISIONS P3)
  /// and the owner chose to delete the stored conversations with it. Only those
  /// two tables are touched; every measurement and pending upload survives.
  /// `deleteTable` is `DROP TABLE IF EXISTS`, so an install older than v6, which
  /// never had them, upgrades through the same branch harmlessly.
  ///
  /// v7 → v8 adds the weigh-in outbox (`weight_outbox_table.dart`). Additive.
  /// v8 → v9 adds the full-history mirror (`mirror_table.dart`). Additive.
  ///
  /// v3 → v4 scopes cached server responses to a sign-in. Old cache rows have
  /// no attributable owner and are discarded; every raw measurement and pending
  /// upload survives. Earlier upgrades are additive.
  ///
  /// The v3 columns arrive NULL on every existing row, which is the honest
  /// starting state: this build has never pushed, so nothing on a phone
  /// upgrading into it has reached the server. The first push sends the 60 days
  /// it holds, and the server upserts them by their own identity.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(strapSamples);
        await m.createTable(sleepSessions);
        await m.createTable(storedWorkouts);
        await m.createTable(deviceTotals);
        await m.createTable(syncMeta);
      }
      if (from < 3) {
        await m.addColumn(strapSamples, strapSamples.pushedAtMs);
        await m.addColumn(sleepSessions, sleepSessions.pushedAtMs);
        await m.addColumn(storedWorkouts, storedWorkouts.pushedAtMs);
        await m.addColumn(deviceTotals, deviceTotals.pushedAtMs);
      }
      if (from < 4) {
        // Old cached responses have no provable owner. Only this disposable
        // cache is rebuilt; raw strap data and pending uploads remain intact.
        await m.deleteTable('cached_payloads');
        await m.createTable(cachedPayloads);
      }
      if (from < 5) {
        await m.createTable(gpsRecordings);
        await m.createTable(gpsFixes);
      }
      if (from < 7) {
        await m.deleteTable('stored_coach_turns');
        await m.deleteTable('stored_coach_threads');
      }
      if (from < 8) {
        await m.createTable(pendingWeights);
      }
      if (from < 9) {
        await m.createTable(mirrorMonths);
      }
    },
  );

  /// Instants are stored as ISO-8601 text, which preserves UTC across the round
  /// trip. drift's default (a Unix timestamp read back in the device's local
  /// zone) is the same class of bug the `day` column's doc describes.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  /// The cached payload for one day, or null when we have never stored it.
  ///
  /// Null means "we have not stored this", which is a different state from "the
  /// server sent an empty payload" — a caller must be able to tell them apart
  /// (Standards §1: "No data" and "operation failed" are different states).
  Future<CachedPayload?> read(String metric, String day, {String scope = ''}) {
    final query = select(cachedPayloads)
      ..where(
        (row) =>
            row.scope.equals(scope) &
            row.metric.equals(metric) &
            row.day.equals(day),
      )
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// The NEWEST cached payload of [metric], whatever day it describes.
  ///
  /// The offline read path. [read] answers "do we hold today's?", which is the
  /// wrong question after midnight with no network: the honest answer is not
  /// "nothing", it is "the last thing the server said, and here is its date".
  /// The row carries both, so the screen can date what it is showing rather than
  /// presenting yesterday as today — the stale-as-current failure this product
  /// exists to refuse.
  Future<CachedPayload?> readLatest(String metric, {String scope = ''}) {
    final query = select(cachedPayloads)
      ..where((row) => row.scope.equals(scope) & row.metric.equals(metric))
      // `day` is `YYYY-MM-DD`, which sorts lexicographically exactly as it sorts
      // chronologically — the reason the column is TEXT at all.
      ..orderBy([(row) => OrderingTerm.desc(row.day)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// The cached payloads of [metric], newest day first, at most [limit] of them.
  ///
  /// [readLatest] answers "what is the last thing the server said"; this answers
  /// "what is the last day it said anything about X", which is a different
  /// question and cannot be built from the first: the newest row is exactly the
  /// one that withheld the value, so a search has to walk backwards past it.
  ///
  /// Bounded on purpose. The horizon is 60 days, so a scan is bounded anyway;
  /// the limit is here so the bound is stated at the query rather than inferred
  /// from a prune that runs somewhere else.
  Future<List<CachedPayload>> readRecent(
    String metric, {
    String scope = '',
    int limit = localHorizonDays,
  }) {
    final query = select(cachedPayloads)
      ..where((row) => row.scope.equals(scope) & row.metric.equals(metric))
      // `YYYY-MM-DD` sorts lexicographically exactly as it sorts
      // chronologically — the reason the column is TEXT at all.
      ..orderBy([(row) => OrderingTerm.desc(row.day)])
      ..limit(limit);
    return query.get();
  }

  /// Stores (or replaces) one day's payload. [day] is `YYYY-MM-DD`.
  Future<void> write({
    required String metric,
    required String day,
    required String payload,
    required DateTime fetchedAt,
    String scope = '',
  }) {
    return into(cachedPayloads).insertOnConflictUpdate(
      CachedPayloadsCompanion.insert(
        scope: Value(scope),
        day: day,
        metric: metric,
        payload: payload,
        fetchedAt: fetchedAt,
      ),
    );
  }

  /// Applies the retention window, given the owner's [today] (`YYYY-MM-DD`).
  ///
  /// The ONE entry point, so the device's retention window cannot mean 60 days
  /// to one caller and 90 to another. It takes the day the owner is living in
  /// and leaves no arithmetic at the call site, which is where a retention
  /// window quietly becomes two windows.
  ///
  /// The policy itself — which tables lose a row at 60 days, which keep an
  /// unsent one past it, and the one table with a second bound — is
  /// [HorizonPrune]. It hands back a [PruneReport] rather than an `int` because
  /// "rows removed" and "measurements destroyed" must not be the same number.
  Future<PruneReport> pruneBeyondHorizon(String today, {DateTime? at}) =>
      horizonPrune.run(today: today, at: at);
}

/// The oldest calendar date the device keeps a **sent** measurement for.
///
/// Separate from the queries so the arithmetic is testable without a database,
/// and so there is exactly one expression of "60 days back".
String horizonStart(String today) => _daysBack(today, localHorizonDays);

/// The oldest calendar date an **unsent** sample survives to.
///
/// The second, wider bound. Everything before it has been waiting a year for a
/// server that never took it, and is destroyed — loudly. See
/// [kUnsentSampleRetentionDays].
String unsentSampleFloor(String today) =>
    _daysBack(today, kUnsentSampleRetentionDays);

String _daysBack(String today, int days) {
  final anchor = DateTime.parse(today);
  final start = DateTime.utc(
    anchor.year,
    anchor.month,
    anchor.day,
  ).subtract(Duration(days: days));
  return isoDay(start);
}

/// An instant rendered as the `YYYY-MM-DD` key these tables use.
///
/// Reads the calendar date **in whatever zone [day] carries**, which is the
/// behaviour both callers need and neither should have to think about: the
/// horizon arithmetic above works in UTC, while a strap sample's `DateTime` is
/// local wall-clock, and each is asking for its own day. Converting either one
/// to the other's zone is what files a row under the wrong date.
String isoDay(DateTime day) => day.toIso8601String().substring(0, 10);
