/// `GET /api/mirror/manifest`, typed at the boundary (`docs/MIRROR.md`).
library;

import 'package:meta/meta.dart';

/// One month of one stream, as the server describes it.
@immutable
class MirrorMonth {
  /// Built by [MirrorManifest.fromJson].
  const MirrorMonth({
    required this.month,
    required this.rows,
    required this.digest,
  });

  /// `YYYY-MM`.
  final String month;

  /// How many rows the server holds for it.
  final int rows;

  /// The digest the phone compares against what it stored.
  final String digest;
}

/// Every stream's months.
@immutable
class MirrorManifest {
  /// Built by [MirrorManifest.fromJson].
  const MirrorManifest({required this.version, required this.streams});

  /// Parses the server's reply; throws [FormatException] on any other shape.
  factory MirrorManifest.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final streams = json['streams'];
    if (version is! int || streams is! Map<String, Object?>) {
      throw const FormatException('a mirror manifest this app cannot read');
    }
    return MirrorManifest(
      version: version,
      streams: <String, List<MirrorMonth>>{
        for (final MapEntry(:key, :value) in streams.entries)
          key: <MirrorMonth>[
            for (final month in value! as List<Object?>)
              _month(month! as Map<String, Object?>),
          ],
      },
    );
  }

  /// The contract version; a change means every month is fetched again.
  final int version;

  /// Stream name → its months, oldest first.
  final Map<String, List<MirrorMonth>> streams;

  static MirrorMonth _month(Map<String, Object?> json) {
    final month = json['month'];
    final rows = json['rows'];
    final digest = json['digest'];
    if (month is! String || rows is! int || digest is! String) {
      throw const FormatException('a mirror month this app cannot read');
    }
    return MirrorMonth(month: month, rows: rows, digest: digest);
  }
}
