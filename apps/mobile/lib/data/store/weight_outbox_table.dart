/// Weigh-ins held on the phone until the server has confirmed them (v8).
///
/// DESIGN_DECISIONS A8: a manual weight must survive a server outage like a
/// strap reading does. One row per observation, keyed by its instant — the same
/// identity the server upserts on (`read/logs.py`, `(user_id, ts)`), so a retry
/// after a lost response addresses the same observation rather than adding one.
/// A row is deleted once the server has confirmed it; nothing prunes it before
/// that, so an unsent weigh-in is never lost to a retention window.
library;

import 'package:drift/drift.dart';

/// The outbox table.
@DataClassName('PendingWeightRow')
class PendingWeights extends Table {
  /// When the weight was observed, Unix milliseconds. The identity.
  IntColumn get atMs => integer()();

  /// Kilograms, as entered and validated.
  RealColumn get kg => real()();

  /// When it was stored on this phone, Unix milliseconds.
  IntColumn get heldAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {atMs};
}
