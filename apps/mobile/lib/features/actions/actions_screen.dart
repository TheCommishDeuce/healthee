/// Actions — the v02 screen: what to try, what is running, and what changed.
///
/// ## The prototype's order, and it is the order
///
/// `screens-actions.js::H.screens.actions` is five things and this list is those
/// five things:
///
/// ```text
///   header                       date · "Small steps. / Your pace." · avatar
///   focus-card                   Today’s suggestion
///   section  What you’re working on   challenge card(s) + program row
///   section  Look back, learn a little   outcomes · previous suggestions
///   footer
/// ```
///
/// `test/features/actions_order_test.dart` asserts it against that list rather
/// than against a scroll position, for the reason `_screen_data.dart` gives:
/// order is a decision, and scrolling until something appears asserts what
/// happened to be on screen when the drag stopped.
///
/// ## What is here that Today does not show
///
/// Today draws the top recommendation under `Suggested today`. This screen draws
/// the whole ranked set, each in the prototype's focus card and each naming the
/// reading that raised it. Adoption records **intent**, never completion —
/// `v02/suggestion_card.dart` holds that sentence and the reason for it.
///
/// ## A quiet day draws nothing rather than a heading over nothing
///
/// Every block is gated on what the payload carried. The one sentence about an
/// empty day is drawn by `SuggestionList` itself, beside the ring that counts
/// the set — a sentence about the day, not an absent section, and written where
/// the count already lives so the two cannot disagree.
///
/// ## The set's own day, when it is not the day in the header
///
/// `read/today.py::_recommendations_for` reaches **two days back** for the newest
/// set at or before the day being served. The header eyebrow here names the day the
/// PAYLOAD is for, so a two-day-stale set was relabelled as today's — while the Today
/// card next door said "written for &lt;day&gt;" about the identical rows. One surface
/// fixed, one not, and the fix in the file next door: audit C5, the same class as A4
/// and the third instance of it.
///
/// The decision now lives in `shared/format/other_day.dart` and both screens call it,
/// so a fix cannot land on one of them again.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/features/actions/v02/suggestion_list.dart';
import 'package:healthee/features/actions/v02/working_on.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/format/other_day.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/rows.dart';
import 'package:healthee/shared/v02/screen_head.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's own h1 for this screen, its line break included.
const String kActionsTitle = 'Actions';

/// What Actions cannot date. `screens.actions`'s own past-day heading.
const String kActionsPastTitle = 'No saved suggestion';

/// The heading over recorded outcomes and previous suggestions.
///
/// It is the screen's ONLY section head now. `What you’re working on` moved
/// into `WorkingOn`, which draws it with its content so an empty section takes
/// its title with it; `Your daily check-in` and `Look back` collapsed into this
/// one card of three rows.
const String kRecordHeading = 'Your own record';

/// The Actions tab.
class ActionsScreen extends ConsumerWidget {
  /// [now] is injected by tests so the freshness labels are deterministic.
  const ActionsScreen({this.now, super.key});

  /// The instant every "x min ago" is measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InstrumentScreen(
      now: now,
      sections: (data) => actionsSections(data, ActionsLinks.of(context)),
      onRefreshed: () => ref.invalidate(commitmentRepositoryProvider),
    );
  }
}

/// Where this screen can go. Passed in so the section list stays a pure
/// function of the payload and a test can build one with no router at all.
@immutable
class ActionsLinks {
  /// Every destination the screen offers.
  const ActionsLinks({
    this.onOpenProfile,
    this.onOpenOutcomes,
    this.onOpenHistory,
  });

  /// The set bound to a real router.
  factory ActionsLinks.of(BuildContext context) => ActionsLinks(
    onOpenProfile: () => unawaited(context.push(Routes.settings)),
    onOpenOutcomes: () => unawaited(context.push(Routes.outcomes)),
    onOpenHistory: () => unawaited(context.push(Routes.recommendations)),
  );

  /// The avatar.
  final VoidCallback? onOpenProfile;

  /// `What changed?`
  final VoidCallback? onOpenOutcomes;

  /// `Previous suggestions`.
  final VoidCallback? onOpenHistory;
}

/// Builds the ordered section list for one render of Actions.
List<PageSection> actionsSections(ScreenData data, ActionsLinks links) {
  final past = data.view.isPast;
  // Null on a past day. A suggestion is written overnight FOR the current day
  // and `/api/today` takes no other; the challenge and program a reader is on
  // are current state for the same reason. Showing either under an older date
  // would be dating today's advice to a day it was not given on.
  final snapshot = past ? null : data.snapshot;
  final recommendations = snapshot?.recommendations ?? const <Recommendation>[];
  return <PageSection>[
    PageSection(
      ScreenHead(
        eyebrow: past
            ? data.view.line
            : (snapshot == null
                  ? null
                  : '${prettyDate(snapshot.date)} · ${data.view.status}'),
        title: kActionsTitle,
      ),
      gap: 0,
    ),
    if (past)
      const PageSection(
        PastDayNotice(title: kActionsPastTitle, body: kPastDayReason),
        gap: PageSpacing.block,
      ),
    if (!past) ...<PageSection>[
      if (data.serverFailure case final PageSection failure) failure,
      if (data.serverPending case final PageSection pending) pending,
    ],

    // ── the set's own day ──────────────────────────────────────────────────
    // Said in words whenever it is not the day the payload answers for. Above
    // the cards because it qualifies the whole set.
    if (recommendationsFromDay(recommendations, snapshot?.asOf?.day)
        case final String day)
      PageSection(
        PanelNote(writtenForDay(day)),
        gap: PageSpacing.panel,
      ),
    // ── the suggestions ────────────────────────────────────────────────────
    //
    // **The screen's subject, and the whole of its top half.** It replaces the
    // stack of `SuggestionCard`s AND the suggested half of the commitments —
    // one list showing every open question at once, because a daily
    // recommendation and a 7-day challenge are the same decision at different
    // horizons. A deck that marched through them one at a time was built and
    // rejected: you cannot choose what to read if you cannot see what is on
    // offer. See `v02/suggestion_list.dart`.
    //
    // On a past day there is nothing to decide: an intention recorded against a
    // day the owner navigated away to is not a decision, it is a mistake.
    //
    // A quiet day is said INSIDE the list, beside the ring that counts the
    // set — one place that knows how many suggestions there are, rather than a
    // second empty state the screen would have to keep in step. `snapshot` is
    // already null on a past day, so there is no second branch to reach.
    if (snapshot != null)
      PageSection(
        SuggestionList(recommendations: recommendations),
        gap: PageSpacing.block,
      ),

    // ── what you’re working on ─────────────────────────────────────────────
    // Only what is RUNNING. What was merely on offer is in the deck above,
    // where it is a question rather than a claim about the owner's week.
    // Absent on a past day: a challenge's progress and a program's week are
    // both "as of now", and `screens.actions`'s own past-day view drops them.
    if (!past)
      const PageSection(
        WorkingOn(scope: CommitmentScope.running),
        gap: PageSpacing.block,
      ),

    // Recorded outcomes and previous suggestions remain readable.
    const PageSection(SectionHead(title: kRecordHeading), gap: 0),
    PageSection(
      RowCard(<Widget>[
        ListRow(
          icon: SolarIconsOutline.chartSquare,
          title: 'What changed?',
          subtitle: 'Review outcomes without jumping to conclusions',
          tone: Tone.movement,
          onTap: links.onOpenOutcomes,
        ),
        ListRow(
          icon: SolarIconsOutline.clockCircle,
          title: 'Previous suggestions',
          subtitle: 'Your intentions and action history',
          tone: Tone.fitness,
          onTap: links.onOpenHistory,
        ),
      ]),
      gap: 0,
    ),
    const PageSection(DataFooter(), gap: 0),
  ];
}
