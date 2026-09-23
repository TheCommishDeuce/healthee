import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/background/background_store.dart';
import 'package:healthee/data/notifications/reminder_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// All scheduling is serialized, including session-change cancellation.
///
/// Only the wind-down and bedtime reminders remain. The daily-focus reminder
/// and challenge-completed notices went with the Actions tab
/// (DESIGN_DECISIONS P5); every reschedule starts with `cancelAll`, so a daily
/// reminder an older build scheduled is cancelled on the first restore.
class NotificationService {
  NotificationService(this.plugin, this.store);
  final FlutterLocalNotificationsPlugin plugin;
  final BackgroundStore store;
  final destinations = StreamController<String>.broadcast();
  Future<void>? _initialized;
  Future<void> _queue = Future<void>.value();
  static const windDownId = 1002;
  static const bedtimeId = 1003;
  static const windDownMinutes = 45;
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'healthee_reminders',
      'Reminders',
      channelDescription: 'Your chosen reminders',
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> initialize() => _initialized ??= _init().onError<Exception>((error, stack) {
    _initialized = null;
    Error.throwWithStackTrace(error, stack);
  });
  Future<void> _init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(
      tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
    );
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => _open(response.payload),
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _open(launch?.notificationResponse?.payload);
    }
  }

  void _open(String? payload) {
    // An older build's 'actions' payload has nowhere to go and is ignored.
    if (payload == 'sleep') destinations.add(payload!);
  }

  Future<ReminderPreferences> preferences() async =>
      ReminderPreferences.decode(await store.read('reminder_preferences'));

  Future<void> save(ReminderPreferences value, AccountApi api) =>
      _serialize(() async {
        await initialize();
        await api.ensureCurrent();
        if (value.bedtime) {
          await _permission();
        }
        await api.ensureCurrent();
        await plugin.cancelAll();
        await _schedule(value);
        await api.ensureCurrent();
        await store.write('reminder_preferences', value.encode());
      });

  Future<void> restore(String? scope) => _serialize(() async {
    await initialize();
    await plugin.cancelAll();
    final value = await preferences();
    if (scope != null && value.scope == scope) await _schedule(value);
  });

  Future<void> _permission() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final allowed = android != null
        ? await android.requestNotificationsPermission()
        : await ios?.requestPermissions(alert: true, sound: true, badge: false);
    if (allowed != true) {
      throw const FormatException(
        'Notifications were not allowed. Enable them in phone settings, then save again.',
      );
    }
  }

  Future<void> _schedule(ReminderPreferences value) async {
    // Refresh timezone on every reschedule, including foreground return after travel.
    tz.setLocalLocation(
      tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
    );
    if (value.bedtime) {
      await _daily(
        windDownId,
        (value.bedtimeMinute - windDownMinutes) % 1440,
        'Wind-down reminder',
        'Your chosen bedtime is in 45 minutes.',
        'sleep',
      );
      await _daily(
        bedtimeId,
        value.bedtimeMinute,
        'Bedtime reminder',
        'It is your chosen bedtime.',
        'sleep',
      );
    }
  }

  Future<void> _daily(
    int id,
    int minute,
    String title,
    String body,
    String destination,
  ) => plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: nextLocalTime(tz.TZDateTime.now(tz.local), minute),
    notificationDetails: details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
    payload: destination,
  );

  static tz.TZDateTime nextLocalTime(tz.TZDateTime now, int minute) {
    var next = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      minute ~/ 60,
      minute % 60,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day + 1,
        minute ~/ 60,
        minute % 60,
      );
    }
    return next;
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    // The caller receives the failure; the queue remains usable for cancellation.
    _queue = result.onError<Exception>((error, stack) {
      AppLog.failure('notifications', 'applying reminders', error, stack);
    });
    return result;
  }
}
