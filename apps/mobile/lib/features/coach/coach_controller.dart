/// Asking the coach — the one place a metered question is spent.
///
/// `keepAlive` so the thread survives the screen being left: a conversation that
/// vanished when the owner looked something up would cost them the context of a
/// question they have already paid for.
///
/// ## The meter is re-read after every attempt, always
///
/// Not decremented. `routers/coach.py` refunds the question on a refusal, on an
/// unvalidated answer and on a transport failure, so a local subtraction would be
/// wrong in three of the five outcomes — and wrong the flattering way round, which
/// is the direction this product treats as a defect rather than a rounding.
/// [ask] invalidates `coachEntitlementProvider` in a `finally`, so the number
/// beside the input is the server's after every attempt including the ones that
/// threw.
///
/// ## Every failure lands in the thread
///
/// A [CoachTrouble] entry is appended for each one, saying what happened and
/// whether anything was charged. Standards §1 forbids a swallowed failure, and
/// the honesty contract makes a silent one worse here than anywhere else in the
/// app: the surface has a running cost attached to it.
library;

import 'dart:async';
import 'dart:math';

import 'package:healthee/core/logging.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_history_store.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'coach_controller.g.dart';

/// The running conversation with the coach.
@Riverpod(keepAlive: true)
class CoachController extends _$CoachController {
  int _generation = 0;

  /// This conversation's id, minted when its first question is asked.
  ///
  /// Null until then, so an empty thread the owner opened and left writes no row
  /// — a history of conversations nobody had is noise, and it would make "you
  /// have 40 conversations" mean "you opened the screen 40 times".
  String? _threadId;
  @override
  CoachConversation build() {
    ref.watch(coachClientProvider);
    _generation++;
    return const CoachConversation();
  }

  /// Asks [question]. Spends one of the owner's included questions.
  ///
  /// Callers must have shown the meter first. That is not a convention here —
  /// `coach_screen.dart` cannot build an input without an [Entitlement] in hand,
  /// so there is no path from a screen to this method that skipped the number.
  /// [topic] is the subject the screen was opened about, when it was opened
  /// about one. It rides with every question asked from that screen rather than
  /// only the first: the thread stays the thread that was opened about a
  /// workout, and the server's grounding should not stop knowing that on turn
  /// two. It is sent as CONTEXT, never as a claim — `insights/coach_thread.py`
  /// screens it with the refusal gate and fences it in the prompt.
  Future<void> ask(String question, {String? topic}) async {
    final text = question.trim();
    if (text.isEmpty || state.asking) {
      return;
    }
    final asked = OwnerQuestion(text);
    // `clearProgress`/`clearDraft` because a stage or draft from a PREVIOUS,
    // unanswered turn (a refusal or a dropped connection does not clear
    // either) must not linger onto this one — `CoachWaiting` would open
    // showing a stage, or a stale draft, that belongs to a question already
    // resolved.
    state = state.copyWith(
      entries: [...state.entries, asked],
      asking: true,
      clearProgress: true,
      clearDraft: true,
    );
    final generation = _generation;
    // Written BEFORE the request, not after it. The process can end at any point
    // — that is the whole reason this store exists — and a question recorded
    // only on success would lose exactly the turns that went wrong, which are
    // the ones the owner most needs a record of because they were charged for
    // some of them.
    // NOT awaited. The docstring on `_remember` says a storage fault must never
    // cost the owner their answer, and awaiting it here would have made that
    // false in the worst way: a slow or stuck write would hold the question
    // itself. The sequence number is taken NOW rather than inside, so a write
    // that lands late still lands in the right place.
    unawaited(_remember(asked, seq: state.entries.length - 1, opening: text));
    // True once any `draft` event has arrived for this question. It decides
    // [CoachReply.live]: a reply the owner already watched being written, a
    // piece at a time, is shown whole rather than sentence-revealed again —
    // only a reply with NO preceding draft (the non-streaming fallback, or an
    // older server) gets the reveal.
    bool draftSeen = false;
    try {
      // Consumed as it arrives rather than awaited whole: `askStream` yields
      // zero or more typed [CoachStageEvent]s and [CoachDraftEvent]s before
      // its one [CoachAnswerEvent]; `CoachWaiting` renders whichever stage and
      // draft this loop last stored.
      await for (final event
          in ref
              .read(coachClientProvider)
              .askStream(state.toWire(), topic: topic)) {
        switch (event) {
          case CoachStageEvent():
            if (_isCurrent(generation)) {
              state = state.copyWith(progress: event);
            }
          case CoachDraftEvent(:final round, :final text):
            draftSeen = true;
            if (_isCurrent(generation)) {
              state = state.copyWith(
                draft: CoachDraft(round: round, text: text),
              );
            }
          case CoachAnswerEvent(:final answer):
            if (_isCurrent(generation)) {
              final reply = CoachReply(answer, live: !draftSeen);
              state = state.copyWith(
                entries: [...state.entries, reply],
                clearProgress: true,
                clearDraft: true,
              );
              unawaited(_remember(reply, seq: state.entries.length - 1));
            }
        }
      }
    } on CoachRefusal catch (refusal) {
      // The gate said no. It is an answer about the account, not a fault, and it
      // carries the instant the window reopens. A 402 is decided BEFORE the slot
      // is charged, so this is one of the two places the app may state flatly
      // that nothing was counted.
      if (_isCurrent(generation)) {
        _trouble(
          refusal.message,
          charge: CoachCharge.notCharged,
          resetsAt: refusal.resetsAt,
        );
      }
    } on CoachUnreachable catch (failure) {
      // Whatever the client worked out about the meter, unchanged. It used to
      // pass `spent: false` here whatever had happened, which is how a receive
      // timeout on a delivered, charged answer printed "nothing was spent".
      if (_isCurrent(generation)) {
        _trouble(failure.message, charge: failure.charge);
      }
    } finally {
      // Whatever happened — including the two `on` clauses above and anything
      // they did not catch — the balance is re-read from the server rather than
      // guessed at. See the library docstring.
      if (_isCurrent(generation)) {
        ref.invalidate(coachEntitlementProvider);
        state = state.copyWith(asking: false);
      }
    }
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  /// Drops the thread and starts an empty one.
  ///
  /// **Not a tidiness control — a cost and a clarity one.** [ask] sends
  /// `state.toWire()`, the WHOLE conversation, on every question, and this
  /// notifier is `keepAlive` so the thread outlives the screen. Without a way
  /// to end it, each question carries every earlier one: the owner's allowance
  /// is 20 questions per rolling 30 days at a measured $0.179 each, and a
  /// thread that only grows makes the twentieth cost far more than the first.
  ///
  /// It matters more since the coach became a route that can be opened **about
  /// something** (`?topic=`). Arriving from a workout on top of an unrelated
  /// ten-turn conversation asks the model to answer in a context the owner did
  /// not choose.
  ///
  /// The prototype's coach screen draws no such control, so this is a
  /// deliberate departure from it: the design never modelled a thread that
  /// persists, and the honesty layer is where that gets paid for.
  void newThread() {
    _threadId = null;
    state = const CoachConversation();
  }

  /// Replaces the live thread with a stored one, read back from this device.
  ///
  /// The reopened thread keeps its id, so continuing it appends rather than
  /// forking: a conversation the owner returns to is the same conversation.
  Future<void> reopen(String threadId) async {
    final scope = await _scope();
    final entries = await _history.entries(scope: scope, threadId: threadId);
    _generation++;
    _threadId = threadId;
    state = CoachConversation(entries: entries);
  }

  CoachHistoryStore get _history =>
      CoachHistoryStore(ref.read(localStoreProvider));

  Future<String> _scope() async =>
      (await CacheSession.capture(ref.read(credentialsProvider))).scope;

  /// Stores one entry, and never lets a storage fault cost the owner the answer.
  ///
  /// The conversation on screen is the source of truth for this turn; the
  /// database is a record of it. If the write fails the owner still has their
  /// answer, so this logs and returns rather than throwing into `ask` — the
  /// opposite trade would turn a full disk into a lost, already-paid-for reply.
  Future<void> _remember(
    CoachEntry entry, {
    required int seq,
    String? opening,
  }) async {
    try {
      final scope = await _scope();
      final id = _threadId ??= _mintThreadId();
      if (opening != null) {
        await _history.open(
          scope: scope,
          threadId: id,
          opening: opening,
          at: DateTime.now().toUtc(),
        );
      }
      await _history.append(
        scope: scope,
        threadId: id,
        seq: seq,
        entry: entry,
        at: DateTime.now().toUtc(),
      );
    } on Object catch (error) {
      AppLog.info('coach', 'could not store this turn: $error');
    }
  }

  static String _mintThreadId() {
    final random = Random();
    return '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}'
        '-${random.nextInt(1 << 32).toRadixString(36)}';
  }

  void _trouble(
    String message, {
    required CoachCharge charge,
    DateTime? resetsAt,
  }) {
    AppLog.info('coach', 'question not answered: $message');
    final trouble = CoachTrouble(
      message: message,
      charge: charge,
      resetsAt: resetsAt,
    );
    state = state.copyWith(entries: [...state.entries, trouble]);
    unawaited(_remember(trouble, seq: state.entries.length - 1));
  }
}
