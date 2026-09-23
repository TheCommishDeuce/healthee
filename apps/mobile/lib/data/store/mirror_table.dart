/// The owner's full history, mirrored from the server one month at a time (v9).
///
/// `docs/MIRROR.md`. One row per (owner, stream, month) holding that month's rows
/// exactly as the server served them, with the digest they were served under.
/// A month is always replaced whole, so there is no per-row merge to get wrong.
///
/// **Never read by the push.** The upload queue reads the strap tables'
/// `pushed_at_ms`; nothing here has one, so a mirrored row cannot be re-uploaded
/// as a fresh measurement.
library;

import 'package:drift/drift.dart';

/// Mirrored months.
@DataClassName('MirrorMonthRow')
class MirrorMonths extends Table {
  /// The owner's server UUID (`/api/account`), not a sign-in scope: re-enrolling
  /// the same owner keeps the mirror, and a different owner never sees it.
  TextColumn get owner => text()();

  /// `derived_daily`, `sleep_session`, … — the server's stream name.
  TextColumn get stream => text()();

  /// `YYYY-MM`.
  TextColumn get month => text()();

  /// The digest the server served these rows under.
  TextColumn get digest => text()();

  /// How many rows [payload] holds.
  IntColumn get rows => integer()();

  /// The mirror contract version the month was fetched under.
  IntColumn get version => integer()();

  /// The month's rows, as the JSON array the server sent.
  TextColumn get payload => text()();

  /// When this month was last written, Unix milliseconds.
  IntColumn get syncedAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {owner, stream, month};
}
