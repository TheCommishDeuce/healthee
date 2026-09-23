import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/features/today/today_sections.dart';
import 'package:healthee/features/today/v02/day_cards.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/features/today/widgets/data_health_section.dart';
import 'package:healthee/features/today/widgets/illness_banner.dart';
import 'package:healthee/features/today/widgets/sleep_summary.dart';
import 'package:healthee/features/today/widgets/weight_entry.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/states/reading_view.dart';

import '../_today_stubs.dart';
import '_screen_data.dart';

int indexOf<T>(List<PageSection> list) =>
    list.indexWhere((section) => section.child is T);

void main() {
  test(
    'Today is sleep, recovery and weight, then the day: steps, heart rate, stress (F1)',
    () {
      final list = todaySections(
        screenData(server: todayView()),
        const TodayExtras(),
      );
      expect(list.map((section) => section.child.runtimeType), [
        TodayHeader,
        DataHealthSection,
        IllnessBanner,
        SleepSummary,
        ReadingView<RecoveryScore>,
        WeightEntry,
        StepsDayCard,
        HeartRateDayCard,
        StressDayCard,
      ]);
      expect(list.every((section) => section.pinnedExtent == null), isTrue);
    },
  );

  test('a withheld recovery retains its slot between sleep and weight', () {
    final list = todaySections(
      screenData(
        server: todayView(mutate: (json) => {...json, 'recovery_score': null}),
      ),
      const TodayExtras(),
    );
    expect(
      indexOf<ReadingView<RecoveryScore>>(list),
      greaterThan(indexOf<SleepSummary>(list)),
    );
    expect(
      indexOf<ReadingView<RecoveryScore>>(list),
      lessThan(indexOf<WeightEntry>(list)),
    );
  });

  test('weight entry and local sleep are available before a server answer', () {
    final list = todaySections(screenData(), const TodayExtras());
    expect(indexOf<SleepSummary>(list), isNonNegative);
    expect(indexOf<WeightEntry>(list), isNonNegative);
    expect(indexOf<ReadingView<RecoveryScore>>(list), -1);
    // The strap's own half of the day cards needs no server either.
    expect(indexOf<StepsDayCard>(list), isNonNegative);
    expect(indexOf<HeartRateDayCard>(list), isNonNegative);
    expect(indexOf<StressDayCard>(list), isNonNegative);
    expect(list.every((section) => section.pinnedExtent == null), isTrue);
  });

  test('optional findings and recommendations never expand Today', () {
    final list = todaySections(
      screenData(server: todayView()),
      const TodayExtras(),
    );
    expect(list, hasLength(9));
    expect(list.last.child, isA<StressDayCard>());
  });
}
