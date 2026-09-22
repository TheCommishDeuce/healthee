import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/notifications/notification_service.dart';
import 'package:healthee/data/notifications/reminder_preferences.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(data.initializeTimeZones);
  test('tomorrow uses a calendar date across daylight-saving transition', () {
    final zone = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(zone, 2026, 3, 7, 23);
    final next = NotificationService.nextLocalTime(now, 9 * 60);
    expect(next.day, 8);
    expect(next.hour, 9);
    expect(next.timeZoneOffset, const Duration(hours: -4));
  });
  test(
    'reminders default off; chosen times and account survive serialization',
    () {
      expect(ReminderPreferences.decode(null).bedtime, isFalse);
      const prefs = ReminderPreferences(
        scope: 'owner',
        bedtime: true,
        bedtimeMinute: 1321,
      );
      final restored = ReminderPreferences.decode(prefs.encode());
      expect(restored.scope, 'owner');
      expect(restored.bedtimeMinute, 1321);
      expect(restored.bedtime, isTrue);
    },
  );
  test('an older record with the removed daily fields still decodes', () {
    final restored = ReminderPreferences.decode(
      '{"scope":"owner","daily":true,"bedtime":true,"completions":true,'
      '"daily_minute":540,"bedtime_minute":1350}',
    );
    expect(restored.bedtime, isTrue);
    expect(restored.bedtimeMinute, 1350);
    expect(restored.encode(), isNot(contains('daily')));
  });
}
