/// Clock and age labels. One implementation, so two cards cannot round differently.
///
/// Hand-rolled rather than `intl`, for one reason that matters and one that does
/// not. The one that matters: every label here is a claim about *how old a
/// measurement is*, and the honesty rule is that it must never round in the
/// flattering direction. `2 h ago` for something 2 h 55 m old reads as fresher
/// than it is, so [ageLabel] floors — 2 h 55 m is `2 h ago`, and 59 minutes is
/// `59 min ago`, never "about an hour". The one that does not: `intl` is a
/// dependency for locale-aware formats this app does not yet have translations
/// for anyway.
///
/// Everything takes an explicit `now` so a test does not depend on the wall
/// clock, which is how a suite ends up failing once a day at midnight.
library;

/// `HH:MM` in the instant's own zone, zero-padded.
String clockLabel(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// How long ago [at] was, floored — "just now", "42 min ago", "3 h ago", "2 d ago".
///
/// Floors deliberately: a freshness label that rounds up is a label that makes
/// stale data look current, which is the exact failure `data_health` exists to
/// surface. Production has served stale numbers behind a healthy-looking screen
/// before (brief §5.8).
String ageLabel(DateTime at, {required DateTime now}) {
  final elapsed = now.difference(at);
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return 'just now';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes} min ago';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} h ago';
  }
  return '${elapsed.inDays} d ago';
}

/// How long until [at], **ceiled** — "in 3 min", "in 2 h", "in 6 days".
///
/// The mirror of [ageLabel] and it rounds the other way for the same reason. A
/// wait that is 2 h 55 m long shown as "in 2 h" promises something sooner than
/// it is; the flattering direction for a countdown is *down*, so this floors
/// nothing and never under-states a wait. An instant already past reads "now",
/// which is the only honest thing to say about a window that has reopened.
String untilLabel(DateTime at, {required DateTime now}) {
  final remaining = at.difference(now);
  if (remaining.isNegative || remaining.inSeconds == 0) {
    return 'now';
  }
  if (remaining.inMinutes < 60) {
    return 'in ${_ceilUnits(remaining.inSeconds, 60)} min';
  }
  if (remaining.inHours < 24) {
    return 'in ${_ceilUnits(remaining.inMinutes, 60)} h';
  }
  final days = _ceilUnits(remaining.inHours, 24);
  return 'in $days day${days == 1 ? '' : 's'}';
}

int _ceilUnits(int amount, int perUnit) => (amount + perUnit - 1) ~/ perUnit;

/// Minutes → `7h 05m`: THE hours-and-minutes label for sleep and every other
/// duration drawn that way (R10). Rounds the whole count first, so it never
/// writes `60m`, and always pads the minutes, so one night reads one way on
/// every screen. It replaced three copies that disagreed (`7h 0m` vs `7h 00m`).
String hoursMinutes(num minutes) {
  final whole = minutes.round();
  final rest = (whole % 60).toString().padLeft(2, '0');
  return '${whole ~/ 60}h ${rest}m';
}

/// A duration in minutes as `7h 20m`, or `48m` under an hour.
///
/// Used for sleep and workouts. Never decimal hours — "6.3 h of sleep" is a
/// number nobody thinks in, and the minutes are what the strap measured.
String durationLabel(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

/// `6a` · `12p` · `11p` — legacy's short clock, from a real hour.
///
/// Legacy hard-codes the five captions under its 24-hour heart rate and lays
/// them out `spaceBetween`, so on every partial day they describe hours the
/// curve above them does not cover. This turns an actual hour into legacy's own
/// format so the captions can be built from the series instead.
String shortClock(int hour) {
  final wrapped = hour % 24;
  final suffix = wrapped < 12 ? 'a' : 'p';
  final twelve = wrapped % 12 == 0 ? 12 : wrapped % 12;
  return '$twelve$suffix';
}
