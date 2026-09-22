import 'package:healthee/data/journal/log_kind.dart';

/// The server's own bounds on a weigh-in (`apps/server/src/healthee/core/bounds.py`,
/// `MIN_WEIGHT_KG` / `MAX_WEIGHT_KG`). Mirrored so an entry the server would refuse
/// is refused on the phone, before it can wait in the offline outbox for an upload
/// that can never succeed. `test/journal/weight_bounds_test.dart` reads the server
/// file, so the two cannot drift apart silently.
const double kMinWeightKg = 10;
const double kMaxWeightKg = 700;

/// The earliest instant the server reads as an event (`core/bounds.py`,
/// `EVENT_TS_MIN` = 10^12 ms, 2001-09-09).
final DateTime kEarliestEvent = DateTime.fromMillisecondsSinceEpoch(
  1000000000000,
  isUtc: true,
);

/// An explicit observation; no guessed body measurements or default doses.
class LogDraft {
  const LogDraft({
    required this.kind,
    required this.at,
    this.amount,
    this.name,
    this.notes,
  });

  final LogKind kind;
  final DateTime at;
  final double? amount;
  final String? name;
  final String? notes;

  String? validate(DateTime now) {
    if (at.isAfter(now)) return 'Choose a time that has already passed.';
    if (at.isBefore(kEarliestEvent)) return 'Choose a more recent time.';
    if (kind.needsName && (name?.trim().isEmpty ?? true)) {
      return 'Describe what you want to record.';
    }
    if (!kind.needsName &&
        (amount == null || !amount!.isFinite || amount! <= 0)) {
      return 'Enter an amount greater than zero.';
    }
    if (kind == LogKind.weight &&
        (amount! < kMinWeightKg || amount! > kMaxWeightKg)) {
      return 'Enter a weight between ${kMinWeightKg.round()} and '
          '${kMaxWeightKg.round()} kg.';
    }
    if (kind.isDuration && amount != amount?.roundToDouble()) {
      return 'Enter a whole number of minutes.';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'type': kind.name,
    'at': at.millisecondsSinceEpoch,
    if (kind.isDuration)
      'minutes': amount?.toInt()
    else if (amount != null)
      'amount': amount,
    if (kind.unit != null) 'unit': kind.unit,
    if (name != null) 'name': name!.trim(),
    if (notes?.trim().isNotEmpty ?? false) 'notes': notes!.trim(),
  };
}
