/// The coach thread itself — the meter, the opener, the turns, the typing row
/// and the prompts — under the pinned composer `coach_screen.dart` owns.
///
/// Split out of `coach_screen.dart` at the 400-line gate when the screen
/// gained the scroll controller that keeps a chat's end in view. The rule the
/// two files share is [coachPermits]: an input or a prompt exists only when the
/// meter licenses one, and both halves ask the same function so the rule
/// cannot drift.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/coach/coach_controller.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/v02/coach_openers.dart';
import 'package:healthee/features/coach/v02/coach_opening.dart';
import 'package:healthee/features/coach/v02/coach_prompts.dart';
import 'package:healthee/features/coach/v02/coach_waiting.dart';
import 'package:healthee/features/coach/widgets/coach_meter.dart';
import 'package:healthee/features/coach/widgets/coach_thread.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/buttons.dart';

/// Whether this entitlement permits a question right now.
///
/// One function, called by the screen (for the pinned composer) and by the body
/// (for the prompts). Two copies of this rule could drift, and the direction that
/// matters is an input appearing beside a meter that does not license it.
bool coachPermits(Entitlement entitlement) {
  final allowance = entitlement.allowanceFor(kCoachFeature);
  // Uncapped means the feature is absent from PREMIUM_ALLOWANCE for a premium
  // owner — `api/gate.py`'s documented asymmetry, and the one case where a
  // missing meter is good news rather than an empty one.
  final uncapped = entitlement.premium && allowance == null;
  return uncapped || (allowance?.hasRemaining ?? false);
}

/// Everything under the head: the meter, the thread, the opening, the input.
///
/// Public so a test can host it with an entitlement in hand rather than
/// scripting a client to produce one.
class CoachBody extends ConsumerWidget {
  /// [entitlement] is the freshly-read `/api/entitlement`.
  const CoachBody({
    required this.entitlement,
    this.topic,
    this.now,
    this.onGrow,
    super.key,
  });

  /// What the server says this owner holds.
  final Entitlement entitlement;

  /// The opening question a caller asked about, written into the input.
  final String? topic;

  /// The instant the reset countdown is measured against.
  final DateTime? now;

  /// Called as a live reply reveals itself, so the screen can follow it.
  final VoidCallback? onGrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(coachControllerProvider);
    final canAsk = coachPermits(entitlement);
    // Today's coaching line, read from the snapshot the app already holds. A
    // `watch` rather than a fetch of its own: `/api/today` is cached locally and
    // every other screen reads it through this provider, so opening the coach
    // costs no request. A loading or failed snapshot yields null, and null draws
    // nothing — this line is a bonus on the screen, never a reason to show an
    // error on it.
    final TodaySnapshot? snapshot = currentAccountValue(
      ref.watch(todaySnapshotProvider),
    ).value?.snapshot;
    final String? openingLine = snapshot?.action;
    // [topic] rides with the question as well as seeding the input. Seeding it
    // puts the subject in the owner's own words, which is what they see and can
    // edit; SENDING it tells the server which screen this thread was opened
    // from, which is a different fact and one it could not otherwise have. It
    // goes on every ask from this screen, not only the first: the thread stays
    // the thread that was opened about that workout even after the owner edits
    // the opening sentence away. It is context and the server treats it as
    // context — screened by the refusal gate and fenced as a label, never a
    // claim (`insights/coach_thread.py`).
    void ask(String question) => unawaited(
      ref.read(coachControllerProvider.notifier).ask(question, topic: topic),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: CoachMeter(entitlement: entitlement, now: now),
        ),
        // Today's coaching line — already generated by the nightly chain, already
        // cited, and free to show. Only into an EMPTY thread: once the owner has
        // asked something, their own conversation is the content and a standing
        // line above it would compete with the answers they paid for.
        if (conversation.isEmpty && !conversation.asking) ...<Widget>[
          // The gap belongs to the opener, not to the screen. Rendered
          // unconditionally it left a blank band above the chips on every
          // morning before the chain had run — spacing for content that had
          // decided not to exist.
          if (openingLine != null || entitlement.premium) ...<Widget>[
            const SizedBox(height: Insets.lg),
            CoachOpening(line: openingLine, pending: entitlement.premium),
          ],
        ],
        for (final entry in conversation.entries)
          CoachEntryView(entry: entry, onGrow: onGrow),
        _tail(
          started: !conversation.isEmpty,
          asking: conversation.asking,
          canAsk: canAsk,
          progress: conversation.progress,
          draft: conversation.draft,
          onGrow: onGrow,
        ),
        // A conversation reads top to bottom and its input sits at the bottom,
        // which is the shape the legacy coach uses and the shape every messaging
        // surface uses. The opener, then what you might say next, then the box
        // you say it in.
        //
        // Kept on two lines exactly as it is: `test/mutations.sh` anchors a
        // guard on this call's `canAsk ? ask : null),` text, and a reflow
        // silently un-anchors it — the stale patch then runs the UNMUTATED
        // suite and reports a pass (HOW_WE_VERIFY section 2).
        if (conversation.isEmpty && !conversation.asking) ...<Widget>[
          const SizedBox(height: Insets.xl),
          // dart format off
          CoachPrompts(prompts: coachOpeners(snapshot), onAsk:
              canAsk ? ask : null),
          // dart format on
        ],

        // Only once there is something to end. An empty thread offering to be
        // ended is a control that does nothing, and the prototype's coach opens
        // empty. See `CoachController.newThread` for why this exists at all.
        if (!conversation.isEmpty && !conversation.asking) ...<Widget>[
          const SizedBox(height: Insets.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: HLinkButton(
              label: 'Start a new thread',
              onPressed: ref.read(coachControllerProvider.notifier).newThread,
            ),
          ),
        ],
      ],
    );
  }

  /// What sits under the last entry: the spinner, the opening, or nothing.
  Widget _tail({
    required bool started,
    required bool asking,
    required bool canAsk,
    required CoachStageEvent? progress,
    required CoachDraft? draft,
    required VoidCallback? onGrow,
  }) {
    if (asking) {
      // Not `LoadingState`: this wait was measured at 80-304 s, and a 16 px
      // spinner held for four minutes reads as a hang. `CoachWaiting` counts the
      // time it can actually see and names the stage the wire actually sent —
      // and, once `draft` arrives, the draft prose itself (`onGrow` fires on
      // every draft update so the thread keeps its end in view).
      return Padding(
        padding: const EdgeInsets.only(top: Insets.md),
        child: CoachWaiting(progress: progress, draft: draft, onGrow: onGrow),
      );
    }
    // The opening is what an EMPTY thread stands on. Once anything has been
    // asked it is gone, prompts included: three openers under a running
    // conversation are three more spends offered as decoration.
    if (started) {
      return const SizedBox.shrink();
    }
    // No permitting balance, no prompts — the same rule as the input, and the
    // card that replaces them carries the reason rather than leaving a dead box.
    // Nothing stands where the opening block used to.
    //
    // `.coach-intro` — a 56 pt symbol, "Let's make sense of your day." over two
    // lines at 26 pt, and a two-line paragraph — occupied roughly the first
    // THIRD of the owner's 2400 px screen and said nothing that screen did not
    // already say. The route header above it reads "A conversation with context /
    // Your coach."; the block under it repeated that in larger type and then
    // explained the product to someone already inside it.
    //
    // The legacy coach (`healthee-legacy/design_reference/.../v2-coach.png`) has
    // no such block: eyebrow, title, then CONTENT. It opens with something the
    // coach has actually said. We cannot open with that yet — the warm line the
    // nightly chain writes to `kv` is not served on any GET — and a headline is
    // not a substitute for it. An empty screen that gets out of the way is more
    // honest than filler that pretends to be content.
    return canAsk
        ? const SizedBox.shrink()
        : const EmptyState(
            message: 'No questions can be asked right now',
            hint:
                'The line above is your server’s own answer about this '
                'account, read just now. Nothing here has been spent.',
          );
  }
}
