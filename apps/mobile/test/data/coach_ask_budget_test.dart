/// A1 · what one ASK costs, and what this app may say it cost.
///
/// The sibling file (`coach_client_test.dart`) is about the vocabulary: a 402
/// becoming a refusal, a 401 becoming a sentence. This one is about the money.
///
/// `POST /api/coach` is the only metered call in the product. The server's gate
/// charges the slot **inside the dependency, before the handler starts** —
/// deliberately, so it cannot be raced — and refunds inside the handler on a
/// refusal, an unvalidated answer, a greeting or an exception. A *delivered*
/// answer is none of those. So a client that hangs up early cancels nothing: it
/// leaves the server producing an answer, charging one of the owner's twenty,
/// and returning it to a socket nobody is reading.
///
/// This call was the only generating one in the app still on `requestTimeout` —
/// ten seconds, derived from a p95 < 100 ms READ budget — while one coach turn
/// is bounded at up to 22 model calls. Both halves are pinned here: the timeout
/// that matches the work, and the fact that after a failure this app claims
/// nothing about the meter it did not watch.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/env.dart';
import 'package:healthee/data/coach/coach_client.dart';

/// An adapter that answers every request with one scripted reply.
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

/// An adapter that fails the way a server still thinking does: the request
/// arrived, the gate charged it, and the answer did not come back in time.
class _ReceiveTimeout implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.receiveTimeout(
    timeout: options.receiveTimeout ?? Duration.zero,
    requestOptions: options,
  );

  @override
  void close({bool force = false}) {}
}

/// Records the options and body one request was actually sent with.
class _Recording implements HttpClientAdapter {
  RequestOptions? seen;
  String? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen = options;
    body = jsonEncode(options.data);
    return ResponseBody.fromString(
      jsonEncode(const <String, Object?>{
        'reply': 'Steady.',
        'citations': <String>[],
        'validated': true,
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
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

void main() {
  test('A RECEIVE TIMEOUT NEVER SAYS NOTHING WAS SPENT', () async {
    // THE finding. The server charges the slot inside the gate before the
    // handler starts, keeps working, and returns 200 to a socket nobody is
    // reading — so a timeout on the ASK is a charge this app cannot see. It
    // printed "Nothing was asked and nothing was spent" over it.
    final client = _clientWith(_ReceiveTimeout());

    await expectLater(
      client.ask(const <CoachTurn>[CoachTurn(role: 'user', content: 'hi')]),
      throwsA(
        isA<CoachUnreachable>()
            .having((failure) => failure.charge, 'charge', CoachCharge.unknown)
            .having(
              (failure) => failure.message,
              'message',
              isNot(contains('nothing was spent')),
            )
            .having(
              (failure) => failure.message,
              'message',
              contains('may already have been asked'),
            ),
      ),
    );
  });

  test(
    'a dead socket may still say it flatly — it never reached the gate',
    () async {
      final client = _clientWith(_Offline());

      await expectLater(
        client.ask(const <CoachTurn>[CoachTurn(role: 'user', content: 'hi')]),
        throwsA(
          isA<CoachUnreachable>().having(
            (failure) => failure.charge,
            'charge',
            CoachCharge.notCharged,
          ),
        ),
      );
    },
  );

  test('a 401 is decided before the gate, so nothing was charged', () async {
    final client = _clientWith(_OneReply(401, const <String, Object?>{}));

    await expectLater(
      client.ask(const <CoachTurn>[CoachTurn(role: 'user', content: 'hi')]),
      throwsA(
        isA<CoachUnreachable>().having(
          (failure) => failure.charge,
          'charge',
          CoachCharge.notCharged,
        ),
      ),
    );
  });

  test('a 500 is NOT claimed as uncharged', () async {
    // The router refunds in its `except`, but this app did not watch it happen.
    final client = _clientWith(_OneReply(500, const <String, Object?>{}));

    await expectLater(
      client.ask(const <CoachTurn>[CoachTurn(role: 'user', content: 'hi')]),
      throwsA(
        isA<CoachUnreachable>().having(
          (failure) => failure.charge,
          'charge',
          CoachCharge.unknown,
        ),
      ),
    );
  });

  test('THE ASK IS GIVEN A TIMEOUT THAT MATCHES THE WORK', () async {
    // It was the only generating call left on the app's 10-second read default,
    // while one coach turn is budgeted at up to 22 model calls.
    final adapter = _Recording();
    final client = _clientWith(adapter);

    await client.ask(const <CoachTurn>[CoachTurn(role: 'user', content: 'hi')]);

    expect(adapter.seen!.receiveTimeout, Env.coachTimeout);
    expect(adapter.seen!.sendTimeout, Env.coachTimeout);
    expect(
      Env.coachTimeout,
      greaterThan(Env.requestTimeout),
      reason: 'the read budget is not a budget this endpoint can meet',
    );
  });

  test('THE BUDGET CLEARS THE SLOWEST COACH TURN ACTUALLY MEASURED', () {
    // Re-measured 2026-09-19 after the server routed its coach model to fast
    // providers, streamed every completion under a 120 s wall-clock deadline and
    // sent passages instead of whole notes: 90 questions, coach mean 27 s, p95 48 s,
    // worst 62 s; two live production questions took 53 s and 76.4 s. The previous
    // pin (304.1 s, six broad questions in August) described a server that no longer
    // exists, and a six-minute budget on a coach that answers in under a minute hid
    // a dead connection for five of them.
    //
    // Still pinned as a NUMBER, not as `Env.coachTimeout` against itself: a future
    // trim has to argue with a measurement, not a tautology. And still with headroom:
    // the budget is more than double the slowest live turn, because a turn that
    // finishes is a question the owner has already been charged for.
    const Duration slowestMeasured = Duration(milliseconds: 76400);

    expect(
      Env.coachTimeout,
      greaterThan(slowestMeasured * 2),
      reason:
          'a coach turn was measured at ${slowestMeasured.inSeconds}s; a budget under '
          'twice that discards answers the owner has already been charged for',
    );
  });

  test('the budget is generous against the streamed keepalive', () {
    // On the streamed endpoint this budget is the tolerated gap BETWEEN bytes, and
    // the server sends a keepalive comment at least every 10 s while it works. A
    // healthy stream therefore never approaches it; only a dead one does.
    expect(Env.coachTimeout, greaterThan(const Duration(seconds: 60)));
  });

  test('a topic rides with the question, and only when there is one', () async {
    final adapter = _Recording();
    final client = _clientWith(adapter);

    await client.ask(const <CoachTurn>[
      CoachTurn(role: 'user', content: 'hi'),
    ], topic: '  my VO2max trend  ');
    expect(adapter.body, contains('my VO2max trend'));
    expect(
      adapter.body,
      isNot(contains('  my VO2max trend')),
      reason: 'a topic is one trimmed line, not whatever the route carried',
    );

    await client.ask(const <CoachTurn>[CoachTurn(role: 'user', content: 'hi')]);
    expect(adapter.body, isNot(contains('topic')));

    await client.ask(const <CoachTurn>[
      CoachTurn(role: 'user', content: 'hi'),
    ], topic: '   ');
    expect(
      adapter.body,
      isNot(contains('topic')),
      reason: 'a blank topic is no topic, not an empty subject label',
    );
  });

  test('THE TOPIC RIDES EVERY TURN OF THE THREAD, NOT JUST THE FIRST', () async {
    // The thread is still the thread that was opened about that workout after
    // the owner edits the opening sentence away, so the server's grounding must
    // not stop knowing it on turn two.
    final adapter = _Recording();
    final client = _clientWith(adapter);

    await client.ask(const <CoachTurn>[
      CoachTurn(role: 'user', content: 'about that run?'),
      CoachTurn(role: 'assistant', content: 'It was steady.'),
      CoachTurn(role: 'user', content: 'and the week after?'),
    ], topic: 'my Running session on 31 Jul');

    expect(adapter.body, contains('my Running session on 31 Jul'));
  });
}
