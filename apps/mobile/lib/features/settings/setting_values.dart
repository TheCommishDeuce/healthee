/// What each settings row is currently SET TO, in the owner's own words.
///
/// **A row that describes itself makes you open it to find out.** `Appearance ·
/// Light, dark or follow your device` names the choices and not the choice;
/// `Reminders · A gentle nudge, on your terms` is a sentence about the feature.
/// Nine of those is a menu. Nine carrying `Dark · Indigo`, `Off`, `On · Wi-Fi
/// only` is a status board, and the screen answers most of its own questions.
///
/// ## Null is a real answer here, and it is drawn as nothing
///
/// Every function returns null when the thing it reports is still loading or
/// genuinely unknown, and `ListRow` draws no value for null. Printing a
/// constructor's default as though it were the owner's setting is the
/// stale-as-current lie at its smallest scale — and this is the screen someone
/// opens precisely to check what a setting is.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/data/background/background_preferences.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/notifications/reminder_preferences.dart';
import 'package:healthee/shared/format/time_labels.dart';

/// `Paired · 60%` — the strap, and what it last said about itself.
String? strapValue({required bool paired, DeviceDay? day}) {
  if (!paired) {
    return 'Not paired';
  }
  return switch (day?.batteryPercent) {
    final int percent => 'Paired · $percent%',
    // Paired but silent about its charge. Saying only what is known.
    _ => 'Paired',
  };
}

/// `Synced 16 min ago` — the LAST COMPLETE sync, never the last attempt.
///
/// `strap_lines.dart` records why the distinction is load-bearing: an attempt
/// that failed halfway leaves data unread, and reporting it as a sync is the
/// stale-behind-a-healthy-screen failure the data-health strip exists to
/// prevent. This row is smaller than that strip and may not undo its work.
String? syncValue(DeviceDay? day, DateTime now) {
  if (day == null) {
    return null;
  }
  return switch (day.sync.lastCompleteSync) {
    final DateTime last => 'Synced ${ageLabel(last, now: now)}',
    // Not phrased as a fault: a phone paired a minute ago is in this state and
    // nothing is wrong with it.
    _ => 'No sync yet',
  };
}

/// `Dark · Indigo` — the theme and the chosen accent.
String? appearanceValue(ThemeMode? mode, AppearanceVariant? variant) {
  if (mode == null || variant == null) {
    return null;
  }
  final theme = switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };
  return '$theme · ${AppearanceVariant.accentNames[variant.accent]}';
}

/// `Bedtime`, or `Off` when the wind-down reminder is off.
String? remindersValue(ReminderPreferences? prefs) {
  if (prefs == null) {
    return null;
  }
  return prefs.bedtime ? 'Bedtime' : 'Off';
}

/// `On · Wi-Fi only`, or `Off`.
String? backgroundValue(BackgroundPreferences? prefs) {
  if (prefs == null) {
    return null;
  }
  if (!prefs.enabled) {
    return 'Off';
  }
  final limits = <String>[
    if (prefs.wifiOnly) 'Wi-Fi only',
    if (prefs.chargingOnly) 'charging only',
  ];
  return limits.isEmpty ? 'On' : 'On · ${limits.join(', ')}';
}
