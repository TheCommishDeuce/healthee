/// `CoachClient.askStream` — the streaming twin of `coach_client_test.dart`.
///
/// Same discipline as that suite: a real 402, a real 401 and a real dead
/// socket each become the right one of [CoachRefusal]/[CoachUnreachable], and
/// no status code and no `DioException` type ever reaches a sentence. This
/// file adds what only exists once streaming does: stage events arriving
/// before the answer, a stream `error` event arriving instead of one, a
/// dropped connection mid-turn, and the fallback to `ask` against a server
/// old enough not to have this endpoint.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';

/// A dio adapter that answers every request with one scripted reply.
/// Duplicated from `coach_client_test.dart` rather than shared — each of this
/// app's test doubles stays walkable from its own file (Standards §5's
/// review-before-commit rule reads one file at a time).
class _OneReply implements HttpClientAdapter {
  _OneReply(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// An adapter that answers with a raw SSE body, status 200.
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

/// An adapter that fails the way a dead network does.
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'Failed host lookup',
  );

  @override
  void close({bool force = false}) {}
}

/// Routes each request to a different scripted adapter by path — the shape
/// the 404-fallback tests need: `/api/coach/stream` and `/api/coach` answer
/// differently on the SAME client.
class _RoutedAdapter implements HttpClientAdapter {
  _RoutedAdapter(this.routes);

  final Map<String, HttpClientAdapter> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final adapter = routes[options.path];
    if (adapter == null) {
      throw StateError('no scripted reply for ${options.path}');
    }
    return adapter.fetch(options, requestStream, cancelFuture);
  }

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
  test('stages arrive in order, then the validated answer', () async {
    final client = _clientWith(
      _SseReply(
        'event: stage\n'
        'data: {"stage":"context","round":1}\n'
        '\n'
        'event: stage\n'
        'data: {"stage":"tool","round":2,"detail":"get_knowledge"}\n'
        '\n'
        'event: answer\n'
        'data: {"reply":"Sleep earlier.","citations":[],"validated":true}\n'
        '\n',
      ),
    );

    final events = await client.askStream(_oneTurn).toList();

    expect(events, hasLength(3));
    expect(
      events[0],
      isA<CoachStageEvent>().having(
        (e) => e.stage,
        'stage',
        CoachStage.context,
      ),
    );
    expect(
      events[1],
      isA<CoachStageEvent>().having((e) => e.detail, 'detail', 'get_knowledge'),
    );
    expect(
      events[2],
      isA<CoachAnswerEvent>().having(
        (e) => e.answer.reply,
        'reply',
        'Sleep earlier.',
      ),
    );
  });

  test('an unknown stage is skipped, not an event of its own', () async {
    final client = _clientWith(
      _SseReply(
        'event: stage\n'
        'data: {"stage":"a_future_stage","round":1}\n'
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

  test('an `error` event carrying 402 BECOMES A REFUSAL', () async {
    final client = _clientWith(
      _SseReply(
        'event: error\n'
        'data: {"status":402,"message":"You have used all 20 questions."}\n'
        '\n',
      ),
    );

    await expectLater(
      client.askStream(_oneTurn).toList(),
      throwsA(
        isA<CoachRefusal>().having(
          (refusal) => refusal.message,
          'message',
          'You have used all 20 questions.',
        ),
      ),
    );
  });

  test(
    'an `error` event carrying 401 says the charge is not claimable',
    () async {
      final client = _clientWith(
        _SseReply(
          'event: error\ndata: {"status":401,"message":"Sign in again."}\n\n',
        ),
      );

      await expectLater(
        client.askStream(_oneTurn).toList(),
        throwsA(
          isA<CoachUnreachable>()
              .having((f) => f.message, 'message', 'Sign in again.')
              .having((f) => f.charge, 'charge', CoachCharge.notCharged),
        ),
      );
    },
  );

  test(
    'an `error` event carrying an unrelated status is an UNKNOWN charge',
    () async {
      final client = _clientWith(
        _SseReply(
          'event: error\ndata: {"status":500,"message":"Something broke."}\n\n',
        ),
      );

      await expectLater(
        client.askStream(_oneTurn).toList(),
        throwsA(
          isA<CoachUnreachable>().having(
            (f) => f.charge,
            'charge',
            CoachCharge.unknown,
          ),
        ),
      );
    },
  );

  test(
    'the byte stream ending with neither answer nor error is UNREACHABLE',
    () async {
      // The gate already ran — the server reached 200 — so this must NOT
      // read as "nothing was spent".
      final client = _clientWith(
        _SseReply('event: stage\ndata: {"stage":"context","round":1}\n\n'),
      );

      await expectLater(
        client.askStream(_oneTurn).toList(),
        throwsA(
          isA<CoachUnreachable>().having(
            (f) => f.charge,
            'charge',
            CoachCharge.unknown,
          ),
        ),
      );
    },
  );

  test(
    'an empty response body is UNREACHABLE, not a silent empty stream',
    () async {
      final client = _clientWith(_SseReply(''));

      await expectLater(
        client.askStream(_oneTurn).toList(),
        throwsA(isA<CoachUnreachable>()),
      );
    },
  );

  test('a 402 BEFORE STREAMING BEGINS is mapped exactly like `ask`', () async {
    final client = _clientWith(
      _OneReply(402, <String, Object?>{
        'detail': <String, Object?>{
          'locked': true,
          'feature': 'coach',
          'limit': 20,
          'used': 20,
        },
      }),
    );

    await expectLater(
      client.askStream(_oneTurn).toList(),
      throwsA(
        isA<CoachRefusal>().having(
          (refusal) => refusal.message,
          'message',
          contains('all 20'),
        ),
      ),
    );
  });

  test(
    'a dead socket before streaming begins says nothing was spent',
    () async {
      final client = _clientWith(_Offline());

      await expectLater(
        client.askStream(_oneTurn).toList(),
        throwsA(
          isA<CoachUnreachable>().having(
            (f) => f.message,
            'message',
            contains('nothing was spent'),
          ),
        ),
      );
    },
  );

  test('a 404 (an older server) falls back to `ask` transparently', () async {
    final client = _clientWith(
      _RoutedAdapter(<String, HttpClientAdapter>{
        '/api/coach/stream': _OneReply(404, const <String, Object?>{}),
        '/api/coach': _OneReply(200, const <String, Object?>{
          'reply': 'From the old endpoint.',
          'citations': <String>[],
          'validated': true,
        }),
      }),
    );

    final events = await client.askStream(_oneTurn).toList();

    expect(events, hasLength(1));
    expect(
      events.single,
      isA<CoachAnswerEvent>().having(
        (e) => e.answer.reply,
        'reply',
        'From the old endpoint.',
      ),
    );
  });

  test('a 405 falls back the same way a 404 does', () async {
    final client = _clientWith(
      _RoutedAdapter(<String, HttpClientAdapter>{
        '/api/coach/stream': _OneReply(405, const <String, Object?>{}),
        '/api/coach': _OneReply(200, const <String, Object?>{
          'reply': 'From the old endpoint.',
          'citations': <String>[],
          'validated': true,
        }),
      }),
    );

    final events = await client.askStream(_oneTurn).toList();

    expect(
      events.single,
      isA<CoachAnswerEvent>().having(
        (e) => e.answer.reply,
        'reply',
        'From the old endpoint.',
      ),
    );
  });
}
