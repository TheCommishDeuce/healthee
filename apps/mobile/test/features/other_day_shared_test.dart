/// C5 · ONE "these are from another day" decision, and every surface that needs it.
///
/// Three surfaces have now needed the same fix. `read/today.py::_recommendations_for`
/// reaches **two days back** for the newest recommendation set, and
/// `read/health_metrics.py` treats an illness flag as active for **two days**. Both are
/// correct server behaviour; what is not correct is a screen drawing either under a
/// heading that says "today".
///
/// `ActionsSection` fixed it for the Today card. The v02 Actions screen labelled the
/// identical set with `prettyDate(snapshot.date)` — the VIEWED day — and its
/// `SuggestionCard` never read `rec.date`, so the same two-day-stale rows were relabelled
/// as today's on one surface while the other named the day. The illness banner never got
/// it at all.
///
/// The decision now lives in `shared/format/other_day.dart`. This file asserts the two
/// things that keep it there: the rule itself, and that the callers are calling it rather
/// than each carrying a copy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/shared/format/other_day.dart';

Recommendation _rec(String? date) => Recommendation.fromJson(<String, Object?>{
  'id': 1,
  'date': ?date,
  'action': 'Walk 30 minutes.',
  'rationale': null,
  'expected_effect': null,
  'category': 'activity',
  'evidence_grade': 3,
  'research_note_ids': const <String>[],
  'signal_source': 'mvpa_gap',
  'adopted': false,
});

void main() {
  group('the rule', () {
    test('a different day is returned', () {
      expect(otherDay('2026-09-06', '2026-09-08'), '2026-09-06');
    });

    test('the same day is null — there is nothing to say', () {
      expect(otherDay('2026-09-08', '2026-09-08'), isNull);
    });

    test('AN UNDATED BLOCK IS NEVER FILLED IN FROM THE DAY ON SCREEN', () {
      // "We do not know this block's day" and "it is this day's" are different
      // statements, and filling one in from the other is the claim this file exists to
      // stop making.
      expect(otherDay(null, '2026-09-08'), isNull);
    });

    test('no viewed day means no comparison, never a device clock', () {
      // An older server sends no `as_of`. `as_of.dart` makes the same argument about
      // `isToday`: a phone whose clock has drifted must not answer a question the
      // server has already answered.
      expect(otherDay('2026-09-06', null), isNull);
    });
  });

  group('BOTH SURFACES ASK THE SAME QUESTION', () {
    test('the recommendation set speaks through its first row', () {
      // All rows in a set share a date — the server keeps only the newest date found.
      final items = <Recommendation>[_rec('2026-09-06'), _rec('2026-09-06')];

      expect(recommendationsFromDay(items, '2026-09-08'), '2026-09-06');
      expect(recommendationsFromDay(items, '2026-09-06'), isNull);
    });

    test('an empty set has no day', () {
      expect(
        recommendationsFromDay(const <Recommendation>[], '2026-09-08'),
        isNull,
      );
    });

  });

  group('the two wordings are different on purpose', () {
    test('written-for is about authored advice', () {
      expect(
        writtenForDay('2026-09-06'),
        'Written for 6 Sep — nothing was written for this day.',
      );
    });

    test('raised-on is about a MEASURED signal, and says nothing about a job', () {
      // An illness flag is not advice authored for a day; it is a reading taken on one,
      // still inside the server's active window. "Nothing was written for this day"
      // would be a claim about a nightly job that did not fail.
      expect(raisedOnDay('2026-09-06'), 'Raised on 6 Sep, not on this day.');
      expect(raisedOnDay('2026-09-06'), isNot(contains('written')));
    });
  });
}
