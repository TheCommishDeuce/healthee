import 'package:drift/drift.dart';

/// Legacy GPS sessions, retained so removing the recorder does not erase data.
/// No new recordings are made. Keep this schema until an explicit export/migration.
@DataClassName('GpsRecordingRow')
class GpsRecordings extends Table {
  TextColumn get id => text()();
  TextColumn get scope => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer().nullable()();
  TextColumn get status => text()();
  RealColumn get distanceM => real().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Legacy fixes preserved alongside their recordings.
@DataClassName('GpsFixRow')
class GpsFixes extends Table {
  TextColumn get recordingId => text()();
  IntColumn get atMs => integer()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitudeM => real().nullable()();
  RealColumn get accuracyM => real()();
  @override
  Set<Column<Object>> get primaryKey => {recordingId, atMs};
}
