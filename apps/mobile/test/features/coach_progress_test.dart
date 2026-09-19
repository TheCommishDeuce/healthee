/// The controller's typed stage reaching the waiting panel, end to end.
///
/// `coach_client_stream_test.dart` proves `askStream` turns the wire into
/// typed events; `coach_waiting_test.dart` proves each stage renders the
/// right label. This file is the seam between them: `CoachController`
/// consuming a live stream and `CoachWaiting` showing exactly what it has
/// seen so far, then settling into the same state an ordinary answer leaves
/// today once the stream ends.
///
/// Each fake `askStream` call is its own `async*` script, paced by a 1 ms
/// [Future.delayed] before every yield rather than a `StreamController` the
/// test drives and closes by hand across `pump()` calls: the delay is real
/// (simulated) elapsed time, so `tester.pump(Duration.zero)` right after
/// tapping the send control can assert nothing has arrived yet without
/// racing however many microtasks one bare `pump()` happens to flush, and
/// `pump(const Duration(milliseconds: 1))` advances exactly one event.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_screen.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';

import '_coach_overrides.dart';

const HealtheeColors _lightColors = HealtheeColors.light();

final DateTime _now = DateTime(2026, 8, 5, 9);

/// One step at a time: `tester.pump(_tick)` after each event, matched to the
/// generator's own delay so exactly one arrives per pump.
const Duration _tick = Duration(milliseconds: 1);

Entitlement _premium({required int remaining}) =>
    Entitlement.fromJson(<String, Object?>{
      'premium': true,
      'status': 'active',
      'locked': const <String>[],
      'included': <Object?>[
        <String, Object?>{
          'feature': 'coach',
          'limit': 20,
          'used': 20 - remaining,
          'remaining': remaining,
          'window_days': 30,
          'resets_at': null,
        },
      ],
      'upgrade': 'https://example.test/upgrade',
    });

CoachAnswer _answer(String reply) => CoachAnswer.fromJson(<String, Object?>{
  'reply': reply,
  'citations': const <String>[],
  'validated': true,
});

/// A client whose `askStream` replays one SCRIPT per call, in order — a real
/// server hands out a fresh connection for every question, and a fake that
/// reused one script across two turns would let the second turn's "before any
/// event" render see the first turn's already-exhausted stream.
class _StreamingCoach implements CoachClient {
  _StreamingCoach(this.scripts, this.balances);

  final List<List<CoachStreamEvent>> scripts;
  final List<Entitlement> balances;
  int reads = 0;
  int asks = 0;

  @override
  Future<Entitlement> entitlement() async {
    final index = reads < balances.length ? reads : balances.length - 1;
    reads++;
    return balances[index];
  }

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      throw UnimplementedError('this fake only exercises askStream');

  @override
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    final script = scripts[asks];
    asks++;
    for (final event in script) {
      await Future<void>.delayed(_tick);
      yield event;
    }
  }
}

Widget _screen(CoachClient client) => coachScope(
  client: client,
  child: MaterialApp(
    theme: AppTheme.light,
    home: CoachScreen(now: _now),
  ),
);

void main() {
  testWidgets(
    'the waiting panel shows nothing invented, then exactly what arrives',
    (tester) async {
      final client = _StreamingCoach(
        [
          [
            const CoachStageEvent(stage: CoachStage.context, round: 1),
            const CoachStageEvent(
              stage: CoachStage.tool,
              round: 2,
              detail: 'get_knowledge',
            ),
            CoachAnswerEvent(_answer('Sleep earlier.')),
          ],
        ],
        [_premium(remaining: 17), _premium(remaining: 16)],
      );
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How is my sleep?');
      await tester.tap(sendButton);
      // Zero elapsed time: the generator's first event is gated behind its
      // own 1 ms delay, so nothing has arrived yet regardless of how many
      // microtasks this pump happens to flush.
      await tester.pump();

      expect(
        find.textContaining('Reading your own data and the graded research'),
        findsOneWidget,
        reason: 'no stage has arrived yet, so today’s sentence still shows',
      );

      await tester.pump(_tick);
      expect(find.text('Reading your data'), findsOneWidget);

      await tester.pump(_tick);
      expect(find.text('Checking the research'), findsOneWidget);
      // The label cross-fades for 220 ms; the old one is gone once it has.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Reading your data'), findsNothing);

      await tester.pump(_tick);
      await tester.pumpAndSettle();

      expect(find.text('Checking the research'), findsNothing);
      expect(find.textContaining('Sleep earlier'), findsOneWidget);
      expect(
        find.textContaining('16 of 20 questions left'),
        findsOneWidget,
        reason: 'the meter is re-read after the turn exactly as it is today',
      );
    },
  );

  testWidgets(
    'a fresh question opens with no stage — nothing from the last turn leaks',
    (tester) async {
      final client = _StreamingCoach(
        [
          [
            const CoachStageEvent(stage: CoachStage.checking, round: 3),
            CoachAnswerEvent(_answer('First answer.')),
          ],
          [const CoachStageEvent(stage: CoachStage.context, round: 1)],
        ],
        [
          _premium(remaining: 17),
          _premium(remaining: 16),
          _premium(remaining: 15),
        ],
      );
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How is my sleep?');
      await tester.tap(sendButton);
      await tester.pump();
      await tester.pump(_tick);
      expect(find.text('Checking the citations'), findsOneWidget);
      await tester.pump(_tick);
      await tester.pumpAndSettle();

      // A fresh call gets its OWN script; the controller must not carry the
      // previous turn's last stage into this render.
      await tester.enterText(find.byType(TextField), 'And my steps?');
      await tester.tap(sendButton);
      await tester.pump();

      expect(
        find.textContaining('Reading your own data and the graded research'),
        findsOneWidget,
        reason: 'a fresh question must not open on a stage from the last one',
      );
      expect(find.text('Checking the citations'), findsNothing);

      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a draft renders muted while asking, then the answer replaces it in '
    'full ink with its sources dot — not before',
    (tester) async {
      final client = _StreamingCoach(
        [
          [
            const CoachStageEvent(stage: CoachStage.thinking, round: 1),
            const CoachDraftEvent(round: 1, text: 'Sleep earlier tonight.'),
            CoachAnswerEvent(
              CoachAnswer.fromJson(const <String, Object?>{
                'reply': 'Sleep earlier tonight, and hold your wake time.',
                'citations': <String>['sleep_need_debt'],
                'validated': true,
              }),
            ),
          ],
        ],
        [_premium(remaining: 17), _premium(remaining: 16)],
      );
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How is my sleep?');
      await tester.tap(sendButton);
      await tester.pump();
      await tester.pump(_tick); // the `thinking` stage
      await tester.pump(_tick); // the draft

      expect(find.text('Sleep earlier tonight.'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Sleep earlier tonight.')).style!.color,
        _lightColors.ink2,
        reason: "a draft hasn't been checked yet, so it reads muted",
      );
      expect(
        find.byType(MetricInfoDot),
        findsNothing,
        reason: 'nothing is validated yet, so nothing is cited yet',
      );

      await tester.pump(_tick); // the answer
      await tester.pumpAndSettle();

      expect(
        find.text('Sleep earlier tonight.'),
        findsNothing,
        reason: 'the draft is gone once the validated answer lands',
      );
      final Finder replyText = find.textContaining(
        'Sleep earlier tonight, and hold your wake time.',
      );
      expect(replyText, findsOneWidget);
      expect(
        tester.widget<Text>(replyText).style!.color,
        _lightColors.ink,
        reason:
            'the checked answer reads in full ink, not the draft’s muted one',
      );
      expect(find.byType(MetricInfoDot), findsOneWidget);
    },
  );
}
