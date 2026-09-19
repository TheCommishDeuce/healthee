/// Parsing one SSE block's `data` into this app's own typed events.
///
/// `sse_parser_test.dart` covers the framing; this file covers what happens
/// to the JSON a block's `data` carries once the framing has handed it over —
/// including the payloads this app must never crash on: a stage it does not
/// know, a non-object body, and JSON that does not parse at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';

void main() {
  group('CoachStage.fromWire', () {
    test('parses every stage the wire contract names', () {
      expect(CoachStage.fromWire('context'), CoachStage.context);
      expect(CoachStage.fromWire('thinking'), CoachStage.thinking);
      expect(CoachStage.fromWire('tool'), CoachStage.tool);
      expect(CoachStage.fromWire('checking'), CoachStage.checking);
      expect(CoachStage.fromWire('revising'), CoachStage.revising);
    });

    test('a stage this app does not know is null, never a crash', () {
      expect(CoachStage.fromWire('a_future_stage'), isNull);
    });
  });

  group('parseCoachStageEvent', () {
    test('carries the round and the tool name through', () {
      final event = parseCoachStageEvent(
        '{"stage":"tool","round":3,"detail":"get_knowledge"}',
      );

      expect(event, isNotNull);
      expect(event!.stage, CoachStage.tool);
      expect(event.round, 3);
      expect(event.detail, 'get_knowledge');
    });

    test('detail is null when the stage is not a tool call', () {
      final event = parseCoachStageEvent('{"stage":"context","round":1}');

      expect(event!.detail, isNull);
    });

    test('an unknown stage name is ignored, not surfaced as a value', () {
      expect(
        parseCoachStageEvent('{"stage":"a_future_stage","round":1}'),
        isNull,
      );
    });

    test('a missing round defaults to 0 rather than throwing', () {
      expect(parseCoachStageEvent('{"stage":"context"}')!.round, 0);
    });

    test('malformed JSON is ignored, not a crash', () {
      expect(parseCoachStageEvent('not json'), isNull);
    });

    test('a JSON value that is not an object is ignored', () {
      expect(parseCoachStageEvent('"context"'), isNull);
      expect(parseCoachStageEvent('42'), isNull);
    });
  });

  group('parseCoachAnswerEvent', () {
    test('parses with the one CoachAnswer parser this app has', () {
      final answer = parseCoachAnswerEvent(
        '{"reply":"Sleep earlier.","citations":[],"validated":true}',
      );

      expect(answer, isNotNull);
      expect(answer!.reply, 'Sleep earlier.');
    });

    test('a payload that is not a JSON object is null', () {
      expect(parseCoachAnswerEvent('[]'), isNull);
      expect(parseCoachAnswerEvent('not json'), isNull);
    });
  });

  group('parseCoachStreamFailure', () {
    test('reads the status and the message the wire sent', () {
      final failure = parseCoachStreamFailure(
        '{"status":402,"message":"You have used all 20 questions."}',
      );

      expect(failure.status, 402);
      expect(failure.message, 'You have used all 20 questions.');
    });

    test('a payload with neither field still returns something sayable', () {
      // Never throws: a malformed `error` event must not crash the app on
      // top of whatever already went wrong server-side.
      final failure = parseCoachStreamFailure('{}');

      expect(failure.status, 0);
      expect(failure.message, isNotEmpty);
    });

    test('unparsable JSON still returns something sayable', () {
      final failure = parseCoachStreamFailure('not json');

      expect(failure.status, 0);
      expect(failure.message, isNotEmpty);
    });
  });
}
