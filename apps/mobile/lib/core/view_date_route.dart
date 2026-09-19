/// The selected day, kept in the route — one redirect, in both directions.
///
/// `data/store/view_date.dart` already owns *what day is being read*, and this
/// file does not duplicate any of it. It owns the much smaller question of how
/// that selection reaches, and survives in, the URL:
///
/// ```text
///   a link in  →  ?date=2026-07-29  →  ViewDate.select      (route wins once)
///   the control →  ViewDate.state   →  ?date=2026-07-29     (state wins after)
/// ```
///
/// ## Why a redirect rather than a listener per screen
///
/// The day is global view state — the prototype's parameter survives a tab
/// switch (`docs/V02_CONNECTIVITY.md` section 0) — so every navigation has to
/// carry it, including the ones nobody wrote for it: the tab bar's five `go`s,
/// every `push` from a panel's Details link, a restored stack, a deep link.
/// Threading a day through those call sites would be a rule enforced by memory,
/// and the first caller to forget it would drop the day silently.
///
/// `GoRouter.redirect` runs on **every** navigation, before anything is built,
/// and it is allowed to answer with a different location. So one function
/// rewrites the URL from the selection, and `buildRouter` bumps its refresh
/// listenable when the selection moves — which makes the control's tap a
/// navigation, and the URL correct without any screen knowing it exists.
///
/// ## The route may name a day; it may not name one this phone has pruned
///
/// A day inside the retention window is adopted. A day outside it — a bookmark
/// kept past the horizon, a hand-typed link, a notification built from a stale
/// payload — is **not**: the URL is rewritten back to the day actually on
/// screen, so the address bar and the header cannot disagree. Clamping was the
/// alternative and it is worse in the same way `ViewDate.select` says: it
/// answers a request for one day with a different day, under a date nobody
/// chose.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';

/// Where [state] should actually go, so the URL and the selection agree.
///
/// Null means "as asked". Non-null is the corrected location, which go_router
/// then re-runs this against — the second pass finds nothing to change and
/// stops, so the redirect never loops.
String? viewDateRedirect(
  WidgetRef ref,
  GoRouterState state,
  ViewDateLinks links,
) {
  if (!isDateAwareRoute(state.uri.path)) {
    return null;
  }
  final ViewDateDecision decision = decideViewDate(
    location: state.uri.toString(),
    requested: viewDateOf(state.uri),
    selected: ref.read(viewDateProvider),
    latest: ref.read(todayProvider),
    honoured: links.honoured,
  );
  links.honoured = decision.honoured;
  final String? adopt = decision.adopt;
  if (adopt != null) {
    // Applied off the routing pass, because a provider written while go_router
    // is resolving a location is a state change during a build.
    scheduleMicrotask(() => ref.read(viewDateProvider.notifier).select(adopt));
  }
  return decision.redirectTo;
}

/// The one piece of memory the redirect needs: **the day the URL is already
/// known to carry.**
///
/// Without it "the link wins — once" was "the link wins — forever". The
/// selection is mirrored into the URL, so after the first pick the URL named a
/// past day; on the next pick the redirect saw a URL day that differed from the
/// selection, took it for a link, and re-selected it — the control could leave
/// the newest day exactly once and then never move again, not even back to
/// today. A day that is already [honoured] is the URL lagging behind the
/// control, not a link, and the selection wins.
///
/// Owned by `buildRouter` (one per router), not a global: two routers in one
/// test process must not share a memory.
class ViewDateLinks {
  String? honoured;
}

/// What one routing pass should do. Pure, so every case is a unit test.
@immutable
class ViewDateDecision {
  const ViewDateDecision({this.redirectTo, this.adopt, this.honoured});

  /// The corrected location, or null for "as asked".
  final String? redirectTo;

  /// A day the LINK chose, to hand to `ViewDate.select`; null when none.
  final String? adopt;

  /// The day the URL carries once this pass settles — next pass's memory.
  final String? honoured;
}

/// Reconciles the URL's day ([requested]) with the selection ([selected]).
///
/// A [requested] day wins only when it is NEW — different from [honoured] — and
/// inside the window. Otherwise the selection wins and the URL is rewritten to
/// it (the parameter removed on [latest]).
ViewDateDecision decideViewDate({
  required String location,
  required String? requested,
  required String selected,
  required String latest,
  required String? honoured,
}) {
  final bool isLink =
      requested != null &&
      requested != selected &&
      requested != honoured &&
      isViewableDay(requested, latest);
  if (isLink) {
    return ViewDateDecision(adopt: requested, honoured: requested);
  }
  final String wanted = dateLocation(location, selected, latest);
  return ViewDateDecision(
    redirectTo: wanted == location ? null : wanted,
    honoured: selected == latest ? null : selected,
  );
}
