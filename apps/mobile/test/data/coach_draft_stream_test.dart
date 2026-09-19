/// `CoachClient.askStream` — the `draft` event, split out of
/// `coach_client_stream_test.dart` at the 400-line gate.
///
/// The owner's "feel like claude — stream it as it starts and swap" decision
/// added one event to the wire this app already parses defensively: `draft`
/// carries the WHOLE draft prose so far, never a delta, and this app must
/// replace what it showed for the previous one rather than append to it.
/// `coach_stream_event_test.dart` covers the payload parsing in isolation;
/// this file proves it reaches `askStream`'s own event sequence, in order,
/// beside the stages and the answer it already yields.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';

/// An adapter that answers with a raw SSE body, status 200. Duplicated from
/// `coach_client_stream_test.dart` rather than shared — each of this app's
/// test doubles stays walkable from its own file (Standards §5's
/// review-before-commit rule reads one file at a time).
class _SseReply implements HttpClientAdapter {
  _SseReply(this.text);

  final String text;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    text,
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/event-stream'],
    },
  );

  @override
  void close({bool force = false}) {}
}

CoachClient _clientWith(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://healthee.example.test',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  )..httpClientAdapter = adapter;
  return CoachClient(dio);
}

const List<CoachTurn> _oneTurn = <CoachTurn>[
  CoachTurn(role: 'user', content: 'hi'),
];

void main() {
  test('drafts arrive in order, ahead of the validated answer', () async {
    final client = _clientWith(
      _SseReply(
        'event: stage\n'
        'data: {"stage":"thinking","round":1}\n'
        '\n'
        'event: draft\n'
        'data: {"round":1,"text":"Sleep"}\n'
        '\n'
        'event: draft\n'
        'data: {"round":1,"text":"Sleep earlier"}\n'
        '\n'
        'event: answer\n'
        'data: {"reply":"Sleep earlier.","citations":[],"validated":true}\n'
        '\n',
      ),
    );

    final events = await client.askStream(_oneTurn).toList();

    expect(events, hasLength(4));
    expect(
      events[1],
      isA<CoachDraftEvent>()
          .having((e) => e.round, 'round', 1)
          .having((e) => e.text, 'text', 'Sleep'),
    );
    expect(
      events[2],
      isA<CoachDraftEvent>().having((e) => e.text, 'text', 'Sleep earlier'),
      reason:
          'the second draft REPLACES the first, and both are yielded '
          'in the order the wire sent them',
    );
    expect(events[3], isA<CoachAnswerEvent>());
  });

  test(
    'a rewrite is just another draft — a higher round, reset text',
    () async {
      final client = _clientWith(
        _SseReply(
          'event: draft\n'
          'data: {"round":1,"text":"Sleep earlier tonight."}\n'
          '\n'
          'event: stage\n'
          'data: {"stage":"revising","round":2}\n'
          '\n'
          'event: draft\n'
          'data: {"round":2,"text":""}\n'
          '\n'
          'event: draft\n'
          'data: {"round":2,"text":"Move bedtime up."}\n'
          '\n'
          'event: answer\n'
          'data: {"reply":"Move bedtime up.","citations":[],"validated":true}\n'
          '\n',
        ),
      );

      final events = await client.askStream(_oneTurn).toList();
      final drafts = events.whereType<CoachDraftEvent>().toList();

      expect(drafts, hasLength(3));
      expect(drafts[0].round, 1);
      expect(
        drafts[1],
        isA<CoachDraftEvent>().having((e) => e.round, 'round', 2),
      );
      expect(
        drafts[1].text,
        isEmpty,
        reason:
            'a rewrite starts the draft over, short or empty, not '
            'continuing the rejected one',
      );
      expect(drafts[2].text, 'Move bedtime up.');
    },
  );

  test('a malformed draft is skipped, not a crash and not an event', () async {
    final client = _clientWith(
      _SseReply(
        'event: draft\n'
        'data: {"round":1}\n'
        '\n'
        'event: answer\n'
        'data: {"reply":"ok","citations":[],"validated":true}\n'
        '\n',
      ),
    );

    final events = await client.askStream(_oneTurn).toList();

    expect(events, hasLength(1));
    expect(events.single, isA<CoachAnswerEvent>());
  });
}
