/// Why a field on `/api/sleep` is missing — the one place the Sleep tab names it.
///
/// ## The problem this closes
///
/// `/api/today` sends a `withheld` block beside every value it declines, so
/// `envelope.dart` can fold the two into a [Reading] and the app never has to
/// guess. **`/api/sleep` sends no such block.** `read/sleep_page.py::_stub_night`
/// defaults every field to `None` and the router returns it as-is, so a night
/// arrives as a row of nulls with nothing saying why.
///
/// Legacy rendered each of those nulls as `—`. That is the exact failure this
/// product exists to avoid: a dash is a value-shaped mark that says nothing, and a
/// reader cannot tell "the strap was off your wrist" from "the server has not
/// derived this yet" from "we have a bug".
///
/// ## The app names the absence; it never invents the reason
///
/// The three cases below are **read off the payload's own shape**, not guessed:
///
/// ```text
///   session_source == null            → noSession   there is no sleep session
///   session present, physiology null  → notSampled  the strap logged no samples
///   session present, derived null     → notDerived  the server has not derived it
/// ```
///
/// SpO₂ and breathing sit between the two since R9: they are derived metrics, so
/// their absence is `notDerived` on a night the server has derived nothing for,
/// and `notSampled` on one it has (`sleep_night.dart` says which fields count).
///
/// Each carries a second-person sentence in the shape `withheld_block` uses on the
/// server, so a Sleep card and a Today card read the same way. What is authored
/// here is the *sentence*; the *fact* comes from the payload. If `/api/sleep` ever
/// starts sending real withheld blocks, `readingFrom` takes over and this file
/// shrinks to the fallback it should always have been.
library;

import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';

/// Why one field of a night or a nap has no value.
enum SleepGap {
  /// No main sleep session behind this night at all.
  noSession(
    'sleep_session_absent',
    'No sleep session was recorded for this night. Wear the strap overnight '
        'and sync, and the night appears here.',
  ),

  /// The session exists; the strap logged no samples of this signal inside it.
  notSampled(
    'sleep_signal_not_sampled',
    'The strap logged no readings of this during the sleep. It measures on a '
        'schedule, so a loose band or a short night can leave a gap.',
  ),

  /// The session exists; the server has not derived this night's value yet.
  notDerived(
    'sleep_metric_not_derived',
    'Your server has not worked this out for this night yet. It is derived '
        'after a sync, so pull to refresh once the strap has caught up.',
  );

  const SleepGap(this.reason, this.message);

  /// The stable id an operator filters on. Never shown on its own.
  final String reason;

  /// The second-person sentence the owner reads.
  final String message;

  /// This gap as a [Disclosure], ready for a [Withheld].
  Disclosure get disclosure => Disclosure(reason: reason, message: message);
}

/// Folds a nullable field and the reason it might be missing into a [Reading].
///
/// The caller supplies the reason because only the caller knows which of the
/// three shapes the payload was in. A default would be a guess, and a guess about
/// why data is missing is the one thing this file exists to prevent.
Reading<T> sleepReading<T extends Object>(T? value, SleepGap gap) =>
    value == null ? Withheld<T>(gap.disclosure) : Present<T>(value);
