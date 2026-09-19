/// The subject a link carries into the coach, all the way from tap to wire.
///
/// `Discuss this workout` and `Talk this through` used to open a sheet and lose
/// what they were about: a sheet has no location, so there was nowhere for the
/// subject to travel. `/api/coach` has nowhere for it either — it takes
/// `messages` and nothing else — so the topic can only be the conversation's
/// **first user turn**, written client-side.
///
/// `/api/coach` now takes an optional `topic` beside `messages`, so the subject
/// travels twice and the two are different facts: the seeded first turn is what
/// the owner is ASKING, in their own editable words, and the field is what
/// screen they came FROM. Neither is a claim.
///
/// That makes four things worth pinning, and they are the four groups here:
///
///   1. `coachLocation` encodes a topic into the route and `coachTopicOf` reads
///      it back, and both drop a blank one;
///   2. the screen puts it in the input and **does not send it** — a navigation
///      that spent one of twenty on arrival is the silent spend this whole
///      surface is built to refuse;
///   3. pressing the control sends exactly the seeded sentence, unaltered, and
///      the topic beside it — on every turn, not only the first;
///   4. a screen opened with no topic sends none.
///
/// The wording itself is `coach_topics.dart`'s, and is asserted for what it must
/// never do: characterise. These sentences are read as the owner's own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_screen.dart';
import 'package:healthee/features/coach/coach_topics.dart';
import 'package:healthee/features/coach/v02/coach_openers.dart';

import '_coach_overrides.dart';

final DateTime _now = DateTime(2026, 8, 5, 9);

/// The topic a workout detail would send.
const String _topic = 'What should I take from my Running session on 31 Jul?';

/// A subscriber with questions left, so the input exists at all.
Entitlement _premium() => Entitlement.fromJson(const <String, Object?>{
  'premium': true,
  'status': 'active',
  'locked': <String>[],
  'included': <Object?>[
    <String, Object?>{
      'feature': 'coach',
      'limit': 20,
      'used': 3,
      'remaining': 17,
      'window_days': 30,
      'resets_at': null,
    },
  ],
  'upgrade': 'https://example.test/upgrade',
});

/// Records every question that actually reached the wire.
class _RecordingCoach with AskAsStream implements CoachClient {
  final List<List<CoachTurn>> asked = <List<CoachTurn>>[];
  final List<String?> topics = <String?>[];

  @override
  Future<Entitlement> entitlement() async => _premium();

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async {
    asked.add(messages);
    topics.add(topic);
    return CoachAnswer.fromJson(const <String, Object?>{
      'reply': 'Steady effort for that distance.',
      'citations': <String>[],
      'validated': true,
    });
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
  group('coachLocation — the topic rides in the route', () {
    test('a topic is encoded into the query', () {
      expect(
        coachLocation('Two words & a symbol'),
        '${Routes.coach}?topic=Two+words+%26+a+symbol',
      );
    });

    test('the encoded topic decodes back to exactly what went in', () {
      // The round trip is the assertion, not the encoding: a topic that came
      // back double-escaped would put `%20` in the owner's own first sentence.
      final Uri uri = Uri.parse(coachLocation(_topic));
      expect(uri.queryParameters['topic'], _topic);
    });

    test('THE ROUND TRIP SURVIVES THE ROUTE, NOT JUST THE ENCODING', () {
      // `coachTopicOf` is what the route builder reads. It used to be five
      // lines inside that builder, where nothing could ask it anything — and a
      // topic dropped there looks exactly like a caller that passed none,
      // because the coach opens with an empty box either way.
      expect(coachTopicOf(Uri.parse(coachLocation(_topic))), _topic);
      expect(
        coachTopicOf(Uri.parse(coachLocation('Two words & a symbol'))),
        'Two words & a symbol',
      );
    });

    test('a blank topic in the QUERY is no topic either', () {
      // The reader is as strict as the writer. A hand-built or stale link is
      // the case the writer cannot cover.
      expect(coachTopicOf(Uri.parse('${Routes.coach}?topic=')), isNull);
      expect(coachTopicOf(Uri.parse('${Routes.coach}?topic=%20%20')), isNull);
      expect(coachTopicOf(Uri.parse(Routes.coach)), isNull);
    });

    test('NO TOPIC AND A BLANK TOPIC BOTH GIVE THE PLAIN COACH', () {
      // A caller that built the query from a label it did not have would
      // otherwise open the coach with an empty box pretending to hold one.
      expect(coachLocation(), Routes.coach);
      expect(coachLocation(null), Routes.coach);
      expect(coachLocation(''), Routes.coach);
      expect(coachLocation('   '), Routes.coach);
    });
  });

  group('THE TOPIC IS WRITTEN INTO THE INPUT, AND NOT SENT', () {
    testWidgets('the opening question is in the field on arrival', (
      tester,
    ) async {
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client, topic: _topic));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, _topic),
        findsOneWidget,
        reason: 'the subject a link was tapped about has to be visible',
      );
    });

    testWidgets('ARRIVING WITH A TOPIC SPENDS NOTHING', (tester) async {
      // The rule this test exists for. A question costs one of twenty per
      // rolling thirty days; asking on arrival would charge for a tap that was
      // navigation, and the owner would never have seen the sentence first.
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client, topic: _topic));
      await tester.pumpAndSettle();

      expect(client.asked, isEmpty);
    });

    testWidgets('the send control sends the seeded sentence unaltered', (
      tester,
    ) async {
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client, topic: _topic));
      await tester.pumpAndSettle();

      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(client.asked, hasLength(1));
      expect(client.asked.single.single.role, 'user');
      expect(client.asked.single.single.content, _topic);
    });

    testWidgets('THE SUBJECT ALSO GOES ON THE WIRE, AS A TOPIC', (
      tester,
    ) async {
      // The gap this closes: `/api/coach` used to take `messages` only, so the
      // server never learned what a question was about and grounding was
      // whatever the model inferred from prose. The field is CONTEXT — the
      // server screens it with the refusal gate and fences it as a label, and
      // nothing downstream is relaxed for it.
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client, topic: _topic));
      await tester.pumpAndSettle();

      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(client.topics, <String?>[_topic]);
    });

    testWidgets('the topic stays with the THREAD, not just the first turn', (
      tester,
    ) async {
      // The thread is still the thread that was opened about that workout after
      // the owner edits the opening sentence away, so the server's grounding
      // must not stop knowing it on turn two.
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client, topic: _topic));
      await tester.pumpAndSettle();

      await tester.tap(sendButton);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'And the week after?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(client.topics, <String?>[_topic, _topic]);
    });

    testWidgets('AND AN OPENING PROMPT CARRIES IT TOO', (tester) async {
      // **The screen has two ways to ask**, and only one of them was covered.
      // The composer's send button routes through `CoachComposer.onAsk`; a
      // prompt chip routes through the screen's own `ask` helper. A thread
      // opened about a workout and started from a chip is the same thread, so
      // it must reach the server carrying the same subject — the mutation that
      // drops `topic:` from that second call site survived this suite.
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client, topic: _topic));
      await tester.pumpAndSettle();

      final chip = find.text(kGenericOpeners.last);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(client.asked.single.single.content, kGenericOpeners.last);
      expect(client.topics, <String?>[_topic]);
    });

    testWidgets('WITHOUT A TOPIC THE INPUT IS EMPTY', (tester) async {
      // Today's card and the FAB ask nothing in particular, and a leftover
      // sentence from the last screen would be a question they did not raise.
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();

      expect(find.text(_topic), findsNothing);
      expect(client.asked, isEmpty);
    });

    testWidgets('A SCREEN OPENED ABOUT NOTHING SENDS NO TOPIC', (tester) async {
      // Today's card and the FAB ask nothing in particular. A topic invented
      // here would be the app telling the server a subject nobody chose.
      final client = _RecordingCoach();
      await tester.pumpWidget(_screen(client));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How did I sleep?');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(client.topics, <String?>[null]);
    });
  });

  group('the openings this app writes in the owner’s voice', () {
    test('the trend opener names the metric and asks an open question', () {
      final String topic = trendTopic('hrv_sleep_avg');

      expect(topic, contains('overnight HRV'));
      expect(topic, endsWith('?'));
    });

    test('the workout opener names the session it was tapped from', () {
      expect(workoutTopic(sport: 'Running', date: '31 Jul'), _topic);
    });

    test('the finding opener trims the title’s own full stop', () {
      // `findingTitle` ends in one, so inlining it produced a sentence with a
      // stop in the middle of it.
      final String topic = findingTopic('Caffeine & your sleep.');

      expect(
        topic,
        'Talk me through this pattern in my own data: '
        'Caffeine & your sleep.',
      );
      expect(topic, isNot(contains('sleep..')));
    });

    test('A GENERIC FINDING TITLE STILL READS AS A SENTENCE', () {
      // `findingTitle` returns this when the server named neither metric, and
      // an opener built by inlining it would have been ungrammatical.
      expect(
        findingTopic('A pattern in your own data.'),
        'Talk me through this pattern in my own data: '
        'A pattern in your own data.',
      );
    });

    test('NO OPENER CHARACTERISES WHAT IT NAMES', () {
      // These sentences are read as the owner's. A claim smuggled into one is
      // this product asserting something in their voice — and the coach's job
      // is to answer that against the corpus, with its grade floor attached.
      const List<String> verdicts = <String>[
        'improv',
        'better',
        'worse',
        'good',
        'bad',
        'poor',
        'excellent',
        'declin',
      ];
      for (final String topic in <String>[
        trendTopic('hrv_sleep_avg'),
        workoutTopic(sport: 'Running', date: '31 Jul'),
        findingTopic('Caffeine & your sleep.'),
      ]) {
        for (final String verdict in verdicts) {
          expect(topic.toLowerCase(), isNot(contains(verdict)), reason: topic);
        }
      }
    });
  });
}
