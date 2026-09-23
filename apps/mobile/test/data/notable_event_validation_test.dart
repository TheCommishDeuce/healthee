import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/insights/notable_event.dart';

void main() {
  test(
    'unvalidated notable interpretation is withheld while observations remain',
    () {
      final event = NotableEvent.fromJson({
        'date': '2026-09-01',
        'metric': 'rhr_daily',
        'label': 'Resting HR',
        'value': 61,
        'median': 55,
        'meaning': 'Unvalidated advice',
        'note_ids': <String>[],
      }, validated: false);
      expect(event.meaning, isEmpty);
      expect(event.value, 61);
      expect(event.median, 55);
    },
  );
}
