/// `CoachConversation.draft` — set on each `draft` event, replaced wholesale
/// by the next one, cleared at the start of a fresh [CoachController.ask] and
/// when the answer lands.
///
/// The rendering is `coach_waiting_test.dart`'s job (it owns `CoachWaiting`,
/// which is the only place a draft is drawn); this file is the seam
/// `coach_charge_honesty_test.dart` already established for the controller —
/// read state directly off a `ProviderContainer`, because the question here
/// is what the STATE becomes at each step, not how it looks.
///
/// It also pins [CoachReply.live]: the owner decided a reply the thread
/// already watched being written, a piece at a time, must not be
/// sentence-revealed again once it is validated — only a reply with no
/// preceding draft (the non-streaming fallback, or a server old enough not
/// to send one) keeps that reveal.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_controller.dart';
import 'package:healthee/features/coach/coach_conversation.dart';

Entitlement _entitlement() => Entitlement.fromJson(const <String, Object?>{
  'premium': true,
  'status': 'active',
  'locked': <String>[],
  'included': <Object?>[],
});

CoachAnswer _answer(String reply) => CoachAnswer.fromJson(<String, Object?>{
  'reply': reply,
  'citations': const <String>[],
  'validated': true,
});

/// Replays one scripted list of events, each gated behind its own 1 ms
/// delay — real (simulated) elapsed time, exactly like
/// `coach_progress_test.dart`'s fake, so a listener attached before `ask()`
/// sees every intermediate state rather than only the last one a bare
/// `await` would flush to.
class _Scripted implements CoachClient {
  _Scripted(this.events);

  final List<CoachStreamEvent> events;

  @override
  Future<Entitlement> entitlement() async => _entitlement();

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      throw UnimplementedError('this fake only exercises askStream');

  @override
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    for (final event in events) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      yield event;
    }
  }
}

/// A client whose one call yields a draft, then drops the connection — the
/// shape `CoachController.ask`'s docstring says does NOT clear a draft on
/// its own; only the START of the next `ask` may.
class _DraftThenDrop implements CoachClient {
  @override
  Future<Entitlement> entitlement() async => _entitlement();

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      throw UnimplementedError('this fake only exercises askStream');

  @override
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    yield const CoachDraftEvent(round: 1, text: 'stale');
    await Future<void>.delayed(const Duration(milliseconds: 1));
    throw const CoachUnreachable('dropped mid-turn', CoachCharge.unknown);
  }
}

ProviderContainer _container(CoachClient client) {
  final container = ProviderContainer(
    overrides: [coachClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'a draft event sets draft; the next one REPLACES it, never merges',
    () async {
      final container = _container(
        _Scripted(<CoachStreamEvent>[
          const CoachDraftEvent(round: 1, text: 'Sleep'),
          const CoachDraftEvent(round: 1, text: 'Sleep earlier'),
          CoachAnswerEvent(_answer('Sleep earlier tonight.')),
        ]),
      );
      final drafts = <CoachDraft?>[];
      container.listen<CoachConversation>(
        coachControllerProvider,
        (previous, next) => drafts.add(next.draft),
      );

      await container
          .read(coachControllerProvider.notifier)
          .ask('How is my sleep?');

      expect(
        drafts.map((draft) => draft?.text).toList(),
        containsAllInOrder(<String>['Sleep', 'Sleep earlier']),
        reason: 'each draft event replaces the last, never appends to it',
      );
      expect(
        drafts.last,
        isNull,
        reason: 'the answer landing clears the draft',
      );
    },
  );

  test(
    'a rewrite (a higher round) still just REPLACES the draft, same as any other',
    () async {
      final container = _container(
        _Scripted(<CoachStreamEvent>[
          const CoachDraftEvent(round: 1, text: 'Sleep earlier tonight.'),
          const CoachStageEvent(stage: CoachStage.revising, round: 2),
          const CoachDraftEvent(round: 2, text: ''),
          const CoachDraftEvent(round: 2, text: 'Move bedtime up.'),
          CoachAnswerEvent(_answer('Move bedtime up.')),
        ]),
      );

      await container
          .read(coachControllerProvider.notifier)
          .ask('How is my sleep?');

      // No assertion on intermediate drafts here — `coach_client_stream_test
      // .dart` already proves the wire's rounds arrive in order; this only
      // needs the final, settled state.
      expect(container.read(coachControllerProvider).draft, isNull);
    },
  );

  test(
    'a draft left by a DROPPED turn is not cleared by the failure itself',
    () async {
      final container = _container(_DraftThenDrop());

      await container.read(coachControllerProvider.notifier).ask('first');

      expect(
        container.read(coachControllerProvider).draft?.text,
        'stale',
        reason:
            'a refusal or a dropped connection does not clear a draft — '
            'only the next question asked does',
      );
    },
  );

  test(
    'the NEXT ask clears a stale draft synchronously, before anything new arrives',
    () async {
      final container = _container(_DraftThenDrop());
      await container.read(coachControllerProvider.notifier).ask('first');
      expect(container.read(coachControllerProvider).draft, isNotNull);

      // Not awaited: `CoachController.ask` clears the draft as the very
      // first thing it does, before its first `await` — so the assertion
      // below runs in the same synchronous turn the call started in, ahead
      // of this fake's own 1 ms delay producing anything.
      final settling = container
          .read(coachControllerProvider.notifier)
          .ask('second');
      expect(
        container.read(coachControllerProvider).draft,
        isNull,
        reason:
            'CoachWaiting must not open the next question on a draft '
            'that belongs to the one before it',
      );
      await settling;
    },
  );

  test(
    'a reply preceded by a draft is NOT live — the words are already on screen',
    () async {
      final container = _container(
        _Scripted(<CoachStreamEvent>[
          const CoachDraftEvent(round: 1, text: 'Sleep'),
          CoachAnswerEvent(_answer('Sleep earlier tonight.')),
        ]),
      );

      await container
          .read(coachControllerProvider.notifier)
          .ask('How is my sleep?');

      final reply = container
          .read(coachControllerProvider)
          .entries
          .whereType<CoachReply>()
          .single;
      expect(reply.live, isFalse);
    },
  );

  test('a reply with NO preceding draft is live — the fallback path keeps its '
      'sentence reveal', () async {
    final container = _container(
      _Scripted(<CoachStreamEvent>[
        CoachAnswerEvent(_answer('Sleep earlier tonight.')),
      ]),
    );

    await container
        .read(coachControllerProvider.notifier)
        .ask('How is my sleep?');

    final reply = container
        .read(coachControllerProvider)
        .entries
        .whereType<CoachReply>()
        .single;
    expect(reply.live, isTrue);
  });
}
