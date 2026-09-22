// Keep data-boundary tests after retiring Today's general journal panel.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/routine.dart';

Routine _routine(Map<String, Object?> logs) => Routine.fromJson({
  'workouts': const <Object?>[],
  'meditation_today': const {'count': 0, 'minutes': 0},
  'open_fast': null,
  'logs_summary': logs,
});

void main() {
  test('isEmpty follows the logged data, not just workouts', () {
    final routine = _routine({
      'caffeine': {'count': 1, 'total': 80.0},
    });
    expect(routine.isEmpty, isFalse);
    expect(routine.logs.single.kind, 'caffeine');
  });
  test('a day with nothing logged is empty', () {
    expect(_routine({}).isEmpty, isTrue);
  });
  test('zero-count log kinds are omitted', () {
    final routine = _routine({
      'caffeine': {'count': 0, 'total': 0.0},
    });
    expect(routine.logs, isEmpty);
    expect(routine.isEmpty, isTrue);
  });
  test('meditation and fasting are not duplicated in other logs', () {
    final routine = _routine({
      'meditation': {'count': 1, 'total': 10.0},
      'fasting': {'count': 1, 'total': 0.0},
      'caffeine': {'count': 2, 'total': 160.0},
    });
    expect(routine.logs, hasLength(3));
    expect(routine.otherLogs.map((log) => log.kind), ['caffeine']);
  });
  test('meditation alone does not invent other logs', () {
    expect(
      _routine({
        'meditation': {'count': 1, 'total': 10.0},
      }).otherLogs,
      isEmpty,
    );
  });
}
