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

  test('one month is one month', () {
    final said = HistoryMirrorCard.summary(
      const MirrorStats(months: 1, rows: 40, bytes: 0, lastSynced: null),
      now,
    );
    expect(said, '40 records across 1 month (0.0 MB).');
  });

  test('a run reports calendar months, never stream-months (B3)', () {
    String said(int fetched, int months, int unchanged, int removed) =>
        HistoryMirrorCard.runSummary(
          MirrorRun(
            fetched: fetched,
            fetchedMonths: months,
            unchanged: unchanged,
            removed: removed,
          ),
        );
    expect(said(7, 2, 0, 0), 'Downloaded 2 months of history.');
    expect(said(1, 1, 6, 0), 'Downloaded 1 month of history.');
    expect(said(0, 0, 7, 0), 'Already up to date.');
    expect(
      said(1, 1, 5, 1),
      'Downloaded 1 month of history. Removed what the server no longer holds.',
    );
    expect(said(0, 0, 6, 1), 'Removed what the server no longer holds.');
  });
}
