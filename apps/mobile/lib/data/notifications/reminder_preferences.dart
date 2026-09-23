import 'dart:convert';

/// Times are local clock minutes, chosen by the owner rather than health targets.
///
/// Records written by older builds also carry `daily`, `completions` and
/// `daily_minute` for the removed daily-focus and challenge notices. They are
/// ignored on read rather than rejected, so an upgrade keeps the bedtime choice.
class ReminderPreferences {
  factory ReminderPreferences.decode(String? raw) {
    if (raw == null) return const ReminderPreferences();
    final data = jsonDecode(raw) as Map<String, Object?>;
    final bed = data['bedtime_minute']! as int;
    if (bed < 0 || bed >= 1440) {
      throw const FormatException('Invalid reminder time');
    }
    return ReminderPreferences(
      scope: data['scope']! as String,
      bedtime: data['bedtime']! as bool,
      bedtimeMinute: bed,
    );
  }
  const ReminderPreferences({
    this.scope = '',
    this.bedtime = false,
    this.bedtimeMinute = 1350,
  });
  final String scope;
  final bool bedtime;
  final int bedtimeMinute;
  String encode() => jsonEncode({
    'scope': scope,
    'bedtime': bedtime,
    'bedtime_minute': bedtimeMinute,
  });
}
