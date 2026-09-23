/// What one render of a tab screen is entitled to draw.
///
/// Split out of `instrument_screen.dart` at the 400-line gate (Standards section
/// 1), and the seam is a real one: the shell is about the FRAME — two sources,
/// their failure rules, a lazy sliver list and a reveal registry — while this is
/// about what a given render may say and under which date. The second question
/// grew a real answer when `/api/today` learned to answer for a day, and it is
/// the one every section list asks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/api/not_signed_in.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/as_of.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/view_day.dart';

/// Everything a screen's section list is built from.
@immutable
class ScreenData {
  /// Handed to a [SectionsBuilder] on every rebuild.
  const ScreenData({
    required this.day,
    required this.server,
    required this.reveals,
    required this.onRetryServer,
    required this.onRetryHistory,
    required this.view,
    this.history,
    this.now,
  });

  /// What the strap measured, and its refusals.
  final DeviceDay day;

  /// The day being read, and the wall-clock day it is judged against.
  ///
  /// Required rather than optional, and it is the difference between a section
  /// list that can be honest and one that cannot: [day] alone says *which* day
  /// this is, never whether it is the newest one, and every refusal on a
  /// date-aware screen turns on that second question.
  final ViewDay view;

  /// What the server made of it — including its loading and error states, which
  /// a section list is sometimes the right place to render.
  final AsyncValue<TodayView> server;

  /// Where "this chart has already animated" is remembered. The screen's.
  final RevealRegistry reveals;

  /// Re-reads `/api/today`. Handed to [serverErrorCard] by whichever section
  /// list decides to draw one.
  final VoidCallback onRetryServer;

  /// **The dated series, and null on the current day.**
  ///
  /// A third source, and it is read on a past day only. Nothing on the current
  /// day is drawn from it — the panels it feeds are `history-screens.js`'s, and
  /// those exist precisely because the derived half cannot answer for an older
  /// date — so watching it unconditionally would put a twenty-five-series
  /// request on every cold start to render nothing.
  ///
  /// Null therefore means *"not read, because this render is on the newest
  /// day"*, never "empty" and never "failed". Those two are inside the
  /// [AsyncValue], which is why this is a nullable [AsyncValue] rather than a
  /// [DatedHistory] that could be empty for three different reasons. The
  /// invariant — non-null exactly when [view] is past — is established in ONE
  /// place, [_InstrumentScreenState.build], so no section list can get it
  /// wrong.
  final AsyncValue<DatedHistory>? history;

  /// Re-reads the batched history. Always callable, because the retry belongs
  /// to the card that draws it and that card only exists on a past day.
  final VoidCallback onRetryHistory;

  /// The instant every "x min ago" is measured against.
  final DateTime? now;

  /// The server's payload for the day being read, or null.
  ///
  /// **A payload about ANOTHER day is not this day's answer**, and this is the
  /// one line that keeps that true. Riverpod holds the previous value through a
  /// refresh, so when the date control moves, the request for the new day is in
  /// flight while `server.value` still holds the old day's — and drawing that
  /// would put one day's recovery, debt and biological age under another day's
  /// date for the length of a round trip. Stale-as-current with a shorter
  /// lifetime is not a smaller version of it.
  ///
  /// ## The test is not "same date", and the difference is load-bearing
  ///
  /// On a PAST day the day must match exactly: the reader named a date, and only
  /// a payload about that date answers them.
  ///
  /// On the CURRENT day the test is the server's own `is_today`, not a string
  /// comparison — because a payload dated a few days back is a state this app
  /// already supports and must keep supporting. `TodayView.describesAnotherDay`
  /// and the data-health card's `cachedDate` line exist for exactly it: an
  /// offline phone falls back to the newest thing it holds, and that is served
  /// with its own date on it rather than withheld. Demanding an exact match here
  /// would blank a screen we know how to draw honestly, which is not a stricter
  /// guarantee — it is a different and worse one.
  ///
  /// Both directions of the in-flight frame are still caught: stepping back gives
  /// a past day a payload that says `is_today`, and stepping forward gives the
  /// current day one that does not.
  ///
  /// A payload with no `as_of` block is an older server, and it is drawn exactly
  /// as it was before the block existed: it can only ever answer for today, so
  /// there is no other day for it to be confused with.
  TodaySnapshot? get snapshot {
    final payload = server.value?.snapshot;
    if (payload?.asOf case final AsOf answered) {
      final bool answersThisDay = view.isPast
          ? answered.day == view.day
          : answered.isToday;
      if (!answersThisDay) {
        return null;
      }
    }
    return payload;
  }

  /// The one card the derived half collapses into when it cannot be reached.
  ///
  /// Null while a usable answer is on hand — a screen that drew this over a
  /// payload it can render would be calling a slow network a failure. Keyed on
  /// [snapshot] rather than on `server.value` so a retained answer about a
  /// DIFFERENT day counts as no answer here too; the two accessors then tile the
  /// null case exactly, and there is no state in which the derived half is absent
  /// and nothing says why.
  ///
  /// A [NotSignedIn] refusal is not a failure to reach anything — no request
  /// was made — so it draws [signInNeededCard] instead, with no retry (B2).
  PageSection? get serverFailure => snapshot == null && server.hasError
      ? PageSection(
          isNotSignedIn(server.error)
              ? signInNeededCard()
              : serverErrorCard(onRetryServer),
        )
      : null;

  /// The placeholder while the derived half is still in flight.
  ///
  /// Also covers the day-change frame: [snapshot] is null while the answer on
  /// hand is about a different day, so the screen says it is reading rather than
  /// drawing the previous day's numbers under the new date.
  PageSection? get serverPending => snapshot == null && !server.hasError
      ? const PageSection(
          LoadingState(label: "Reading the server's view of this day"),
        )
      : null;
}

/// What [signInNeededCard] leads with.
const String kSignInNeeded = 'Sign in to see what your server works out';

/// The phone holds no session, so the derived half was never asked for.
///
/// No retry: retrying cannot sign anyone in, and a retry button is how
/// [serverErrorCard] says "this was our failure", which this is not.
Widget signInNeededCard() => const EmptyState(
  message: kSignInNeeded,
  hint:
      'Your measurements are on this phone and are unaffected. Recovery, sleep '
      'health, debt, VO₂max and biological age are worked out on your server; '
      'sign in from Settings to see them.',
);

/// The derived half is unreachable. Says which half, and offers the retry.
///
/// A retry rather than a withheld card, because this is OUR failure and not an
/// answer: `WithheldCard` never offers a retry precisely so the two cannot be
/// confused. Shared because four screens draw the same card for the same reason.
Widget serverErrorCard(VoidCallback onRetry) => ErrorState(
  message: "Couldn't reach your server for today's judgements",
  detail:
      'Your measurements are on this phone and are unaffected. Recovery, sleep '
      'health, debt, VO₂max and biological age are worked out on the server, so '
      'they are not shown until it answers.',
  onRetry: onRetry,
);
