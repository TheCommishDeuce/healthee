/// The coach's OPENERS and its composer — the two controls a balance licenses.
///
/// Split out of `coach_screen_test.dart` at the 400-line gate (Standards section
/// 1). The seam is the one the screen itself draws: that suite is about the four
/// states of the meter, and this one is about the two controls that spend it. A
/// prompt button asks a question, so it costs one of twenty and is gated exactly
/// as the text input is — which is the assertion this file exists to make,
/// because nothing about a prompt button looks like a spend.
///
/// The composer cases are **rectangles**. The cost is on the button before the
/// tap, and a label that pushed the input off the page at 320 px would satisfy
/// "the label is present" while making the surface unusable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_screen.dart';
import 'package:healthee/features/coach/v02/coach_openers.dart';
import 'package:solar_icons/solar_icons.dart';

import '_coach_overrides.dart';

final DateTime _now = DateTime(2026, 8, 5, 9);

/// A subscriber with [remaining] of 20 questions left.
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

/// A free owner: nothing bought, so nothing to meter.
Entitlement _free() => Entitlement.fromJson(const <String, Object?>{
  'premium': false,
  'status': 'none',
  'locked': <String>['coach'],
  'included': <Object?>[],
  'upgrade': 'https://example.test/upgrade',
});

/// A client that answers from a script and records what it was asked.
class _ScriptedCoach with AskAsStream implements CoachClient {
  _ScriptedCoach({required this.balances, this.answer});

  /// One entitlement per read, so a test can show the meter moving.
  final List<Entitlement> balances;
  final CoachAnswer? answer;

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
  group('THE PROMPTS ARE A SPEND, AND ARE GATED LIKE ONE', () {
    testWidgets('a permitting balance offers the prototype’s three openers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(_ScriptedCoach(balances: [_premium(remaining: 17)])),
      );
      await tester.pumpAndSettle();

      for (final prompt in kGenericOpeners) {
        expect(find.text(prompt), findsOneWidget, reason: prompt);
      }
      // The opening block is GONE, and its absence is the assertion. It was a
      // 56 pt symbol, a two-line 26 pt headline and a paragraph — about a third
      // of the screen — restating the route header underneath it. A screen whose
      // purpose is asking a question should reach the input without scrolling.
      expect(find.text('Let’s make sense\nof your day.'), findsNothing);
      expect(find.byIcon(SolarIconsOutline.chatRoundDots), findsNothing);
    });

    testWidgets('a SPENT window offers no prompt either — a prompt costs one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screen(_ScriptedCoach(balances: [_premium(remaining: 0)])),
      );
      await tester.pumpAndSettle();

      for (final prompt in kGenericOpeners) {
        expect(
          find.text(prompt),
          findsNothing,
          reason: 'tapping "$prompt" would spend a question there is none of',
        );
      }
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a FREE owner is offered no prompt', (tester) async {
      await tester.pumpWidget(_screen(_ScriptedCoach(balances: [_free()])));
      await tester.pumpAndSettle();

      for (final prompt in kGenericOpeners) {
        expect(find.text(prompt), findsNothing, reason: prompt);
      }
    });

    testWidgets('a prompt spends through the same path as the input', (
      tester,
    ) async {
      final client = _ScriptedCoach(
        balances: [_premium(remaining: 17), _premium(remaining: 16)],
        answer: CoachAnswer.fromJson(const <String, Object?>{
          'reply': 'Your sleep is short [sleep_need_debt].',
          'citations': <String>['sleep_need_debt'],
          'grade_floor': 'Probable',
          'refused': false,
          'validated': true,
        }),
      );
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kGenericOpeners.first));
      await tester.pumpAndSettle();

      expect(client.asked.single.single.content, kGenericOpeners.first);
      expect(find.textContaining('16 of 20 questions left'), findsOneWidget);
    });
  });

  group('THE COMPOSER FITS, AND STILL SAYS WHAT A PRESS COSTS', () {
    for (final width in <double>[320, 360, 390, 414]) {
      testWidgets('the send and a usable input both fit at $width', (
        tester,
      ) async {
        tester.view
          ..physicalSize = Size(width * 3, 2400)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _screen(_ScriptedCoach(balances: [_premium(remaining: 17)])),
        );
        await tester.pumpAndSettle();

        final button = tester.getRect(sendButton);
        final field = tester.getRect(find.byType(TextField));
        // The cost is not printed any more — it is the control's accessible
        // name, which is the only place a screen-reader user is told it.
        expect(
          find.bySemanticsLabel('Ask — uses 1 of your 17'),
          findsOneWidget,
          reason: '\$width: the press must still announce what it spends',
        );
        // Painted geometry: neither runs off the page, and the input is wide
        // enough to be one.
        expect(button.right, lessThanOrEqualTo(width), reason: '\$width');
        expect(field.left, greaterThanOrEqualTo(0), reason: '\$width');
        expect(
          field.width,
          // The field is `Expanded` beside a fixed 44 pt control, so what is
          // being checked is that the remainder is genuinely usable rather than
          // that a negotiation came out right — there is no longer a negotiation.
          greaterThanOrEqualTo(160),
          reason: '\$width: an input this narrow is not one',
        );
      });
    }
  });

  // THE ROW WRAPS RATHER THAN SQUEEZING THE INPUT is gone with the control it
  // described. `fitsOneRow`/`minFieldWidth` decided whether a full-width
  // "Ask — uses 1 of your 16" bar could share a line with the input. That bar
  // printed the fact the meter already states three lines above it, so it became
  // a 44 pt circular send and there is no width left to negotiate. The rule those
  // tests protected — an input is never squeezed to something you cannot type in
  // — is now structural: the field is `Expanded` beside a fixed-width control.
}
