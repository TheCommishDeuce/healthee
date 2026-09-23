/// One `hoursMinutes`, not three (R10).
///
/// Today's sleep card, Sleep and the charts each carried their own copy, and
/// they disagreed: Today wrote a 7-hour night as `7h 0m` where Sleep wrote
/// `7h 00m`, and rounded the minutes AFTER splitting off the hours, so 59.6
/// minutes read `0h 60m`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/shared/format/time_labels.dart';

void main() {
  test('minutes are padded, so every night reads the same way', () {
    expect(hoursMinutes(420), '7h 00m');
    expect(hoursMinutes(425), '7h 05m');
    expect(hoursMinutes(380), '6h 20m');
    expect(hoursMinutes(0), '0h 00m');
  });

  test('it rounds BEFORE splitting, so it never writes 60 minutes', () {
    expect(hoursMinutes(59.6), '1h 00m');
    expect(hoursMinutes(119.5), '2h 00m');
  });
}
