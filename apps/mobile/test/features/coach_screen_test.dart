/// The coach SCREEN — and the rule that the input cannot exist without the meter.
///
/// It was a sheet until the coach became a route. Nothing here changed with the
/// frame: every assertion is about what the composition renders for a balance.
///
/// A coach question costs one of twenty per rolling thirty days. `PRICING.md` §0
/// argues that *"a stated number beats 'unlimited (fair-use)'"* because
/// *"'unlimited' with a silent throttle is the dishonest version of the same
/// thing"*, and #116 built `/api/entitlement.included` on the observation that a
/// stated limit nobody can observe until it stops them is most of the way back to
/// what that argument rejected.
///
/// So this suite is mostly about **what does not render**. Four states each get
/// their own sentence and no box to type in — checking, failed, locked, spent —
/// because a live input beside an unknown balance is the silent spend the feature
/// is not allowed to have.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_screen.dart';
import 'package:healthee/shared/format/note_names.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import '_coach_overrides.dart';

/// The client's own sentence for a request that never left the phone.
const String kUnreachable = "Couldn't reach your server. Nothing was spent.";

final DateTime _now = DateTime(2026, 8, 5, 9);

/// A subscriber with [remaining] of 20 questions left.
Entitlement _premium({required int remaining, DateTime? resetsAt}) =>
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
          'resets_at': resetsAt?.toIso8601String(),
        },
      ],
      'upgrade': 'https://example.test/upgrade',
    });

/// A free owner: nothing bought, so nothing to meter.
Entitlement _free() => Entitlement.fromJson(const <String, Object?>{
  'premium': false,
  'status': 'none',
  'locked': <String>['coach'],
  'included': <Object?>[],
  'upgrade': 'https://example.test/upgrade',
});

/// A subscriber with no cap on the coach at all.
Entitlement _uncapped() => Entitlement.fromJson(const <String, Object?>{
  'premium': true,
  'status': 'active',
  'locked': <String>[],
  'included': <Object?>[],
  'upgrade': 'https://example.test/upgrade',
});

/// A client that answers from a script and records what it was asked.
class _ScriptedCoach with AskAsStream implements CoachClient {
  _ScriptedCoach({required this.balances, this.answer, this.throws});

  /// One entitlement per read, so a test can show the meter moving.
  final List<Entitlement> balances;
  final CoachAnswer? answer;

  /// What `ask` should throw instead of answering. Typed as [Exception] rather
  /// than `Object` so the lint that forbids throwing arbitrary values stays on.
  final Exception? throws;

  int reads = 0;
  final List<List<CoachTurn>> asked = <List<CoachTurn>>[];

  @override
  Future<Entitlement> entitlement() async {
    final index = reads < balances.length ? reads : balances.length - 1;
    reads++;
    return balances[index];
  }

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async {
    asked.add(messages);
    if (throws case final Exception failure) {
      throw failure;
    }
    return answer!;
  }
}

Widget _screen(CoachClient client, {String? topic}) => coachScope(
  client: client,
  child: MaterialApp(
    theme: AppTheme.light,
    home: CoachScreen(topic: topic, now: _now),
  ),
);

void main() {
  group('THE METER IS VISIBLE BEFORE A QUESTION CAN BE SPENT', () {
    testWidgets('a subscriber sees the balance and the cost on the button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(_ScriptedCoach(balances: [_premium(remaining: 17)])),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('17 of 20 questions left'), findsOneWidget);
      expect(find.textContaining('over the last 30 days'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Ask — uses 1 of your 17'),
        findsOneWidget,
        reason: 'the cost is on the button, before the tap, in the number',
      );
    });

    testWidgets('while the balance is UNKNOWN there is no input at all', (
      tester,
    ) async {
      // The read is in flight and never lands. A text field here would be an
      // input beside a number nobody has yet.
      await tester.pumpWidget(_screen(_PendingEntitlement()));
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('Checking what your account includes'),
        findsOneWidget,
      );
    });

    testWidgets('a FAILED balance read leaves no input and offers a retry', (
      tester,
    ) async {
      await tester.pumpWidget(_screen(_FailingEntitlement()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining("Couldn't read what your account includes"),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a SPENT window leaves no input and says when it reopens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(
          _ScriptedCoach(
            balances: [
              _premium(
                remaining: 0,
                resetsAt: _now.add(const Duration(hours: 30)),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('All 20 of your questions'), findsOneWidget);
      expect(find.textContaining('reopens in 2 days'), findsOneWidget);
    });

    testWidgets('a FREE owner sees no meter reading zero', (tester) async {
      // "0 of 20 left" for somebody who was never sold twenty of anything is an
      // upsell disguised as a meter. `api/allowance_report.py` argues it and the
      // wire enforces it by sending an empty list.
      await tester.pumpWidget(_screen(_ScriptedCoach(balances: [_free()])));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('0 of 20'), findsNothing);
      expect(find.textContaining('part of the subscription'), findsOneWidget);
    });

    testWidgets('an UNCAPPED subscriber gets an input and no false zero', (
      tester,
    ) async {
      // Absent from PREMIUM_ALLOWANCE means unlimited, not zero — the asymmetry
      // an entry with `limit: 0` would invert.
      await tester.pumpWidget(_screen(_ScriptedCoach(balances: [_uncapped()])));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('no question limit'), findsOneWidget);
      expect(find.bySemanticsLabel('Ask'), findsOneWidget);
    });
  });

  group('A SPEND IS NEVER SILENT', () {
    testWidgets('the meter is RE-READ from the server after an answer', (
      tester,
    ) async {
      final client = _ScriptedCoach(
        balances: [_premium(remaining: 17), _premium(remaining: 16)],
        answer: CoachAnswer.fromJson(const <String, Object?>{
          'reply': 'Your HRV is where it usually is [hrv_recovery].',
          'citations': <String>['hrv_recovery'],
          'grade_floor': 'Probable',
          'refused': false,
          'validated': true,
        }),
      );
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How is my recovery?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(client.asked.single.single.content, 'How is my recovery?');
      expect(
        find.textContaining('16 of 20 questions left'),
        findsOneWidget,
        reason:
            'the server refunds three of the five outcomes, so a local '
            'subtraction would be wrong — and wrong the flattering way round',
      );
      expect(client.reads, greaterThan(1));
    });

    testWidgets('an answer carries its citations and its grade floor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(
          _ScriptedCoach(
            balances: [_premium(remaining: 5)],
            answer: CoachAnswer.fromJson(const <String, Object?>{
              'reply': 'Sleep earlier [sleep_need_debt].',
              'citations': <String>['sleep_need_debt'],
              'grade_floor': 'Probable',
              'refused': false,
              'validated': true,
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'What should I do?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Sleep earlier'), findsOneWidget);
      expect(
        find.textContaining('[sleep_need_debt]'),
        findsNothing,
        reason: 'the marker is rendered as a citation, never printed',
      );
      // Behind the bubble's ⓘ now, not under the sentence — the rule
      // `citation_sweep_test.dart` holds for every prose surface.
      final source = find.text(noteName('sleep_need_debt')!);
      expect(source, findsNothing, reason: 'a chip is back on the face');
      await tester.tap(find.byType(MetricInfoDot));
      await tester.pumpAndSettle();

      expect(source, findsOneWidget);
      expect(
        find.textContaining('PROBABLE'),
        findsWidgets,
        reason: 'the weakest grade among the notes cited, stated on the answer',
      );
    });

    testWidgets('an UNVALIDATED answer says it was not counted', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(
          _ScriptedCoach(
            balances: [_premium(remaining: 5)],
            answer: CoachAnswer.fromJson(const <String, Object?>{
              'reply': 'I do not have enough to answer that.',
              'citations': <String>[],
              'grade_floor': null,
              'refused': false,
              'validated': false,
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Anything?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('honest fallback'), findsOneWidget);
      expect(
        find.textContaining('not counted against your questions'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a TRANSPORT FAILURE stays in the thread and says nothing was charged',
      (tester) async {
        final client = _ScriptedCoach(
          balances: [_premium(remaining: 5)],
          // The app's own taxonomy, which is what the controller catches. The
          // DioException → taxonomy mapping belongs to the client and is tested
          // at that seam, in `test/data/coach_client_test.dart`.
          throws: const CoachUnreachable(kUnreachable, CoachCharge.notCharged),
        );
        await tester.pumpWidget(_screen(client));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Anything?');
        await tester.tap(sendButton);
        await tester.pumpAndSettle();

        expect(
          find.text('Anything?'),
          findsOneWidget,
          reason:
              'the question is not deleted — "did that use one?" must stay answerable',
        );
        expect(
          find.textContaining("Couldn't reach your server"),
          findsOneWidget,
        );
        expect(
          find.textContaining('Nothing was counted for this'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a 402 is an answer about the account, not a crash', (
      tester,
    ) async {
      final client = _ScriptedCoach(
        balances: [_premium(remaining: 1)],
        throws: CoachRefusal(
          message: 'You have used all 20 coach questions in this window.',
          resetsAt: _now.add(const Duration(days: 4)),
        ),
      );
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'One more?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('used all 20 coach questions'),
        findsOneWidget,
      );
      expect(
        find.textContaining('402'),
        findsNothing,
        reason: 'a status code is never shown to anybody',
      );
      expect(
        find.textContaining('Nothing was counted for this'),
        findsOneWidget,
      );
    });
  });
}

/// An entitlement read that never lands, so the "checking" state can be held.
class _PendingEntitlement with AskAsStream implements CoachClient {
  @override
  Future<Entitlement> entitlement() => Completer<Entitlement>().future;

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      throw StateError('a question must not be askable with no meter');
}

/// An entitlement read that fails. Its own class rather than a flag on
/// [_ScriptedCoach], because the sheet must render a different SHAPE for it.
class _FailingEntitlement with AskAsStream implements CoachClient {
  @override
  Future<Entitlement> entitlement() async =>
      throw const CoachUnreachable('no answer', CoachCharge.notCharged);

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      throw StateError('a question must not be askable with no meter');
}
