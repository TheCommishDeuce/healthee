/// What the mirror card says about the history held on the phone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/mirror/mirror_sync.dart';
import 'package:healthee/features/settings/widgets/history_mirror_card.dart';

void main() {
  final now = DateTime(2026, 9, 20, 12);

  test('nothing mirrored says so, and says where the history is', () {
    final said = HistoryMirrorCard.summary(MirrorStats.empty, now);
    expect(said, startsWith('None yet.'));
    expect(said, contains('60 days'));
  });

  test('a mirror reports its records, months, size and age', () {
    final said = HistoryMirrorCard.summary(
      MirrorStats(
        months: 24,
        rows: 18234,
        bytes: 3 * 1024 * 1024,
        lastSynced: now.subtract(const Duration(hours: 3)),
      ),
      now,
    );
    expect(said, '18234 records across 24 months (3.0 MB). Updated 3 h ago.');
  });
}
