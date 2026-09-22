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
/// The decision now lives in `shared/format/other_day.dart`. This file asserts the rule
/// itself. (The Actions screen and its recommendation wording were removed; the illness
/// banner is the remaining caller.)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/shared/format/other_day.dart';


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

  group('the raised-on wording', () {
    test('raised-on is about a MEASURED signal, and says nothing about a job', () {
      // An illness flag is not advice authored for a day; it is a reading taken on one,
      // still inside the server's active window. "Nothing was written for this day"
      // would be a claim about a nightly job that did not fail.
      expect(raisedOnDay('2026-09-06'), 'Raised on 6 Sep, not on this day.');
      expect(raisedOnDay('2026-09-06'), isNot(contains('written')));
    });
  });
}
