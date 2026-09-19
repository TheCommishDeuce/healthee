/// A default `askStream` for coach-client test doubles that only script `ask`.
///
/// `CoachController` now drives the coach through `askStream` rather than
/// `ask`, so every `implements CoachClient` fake across the coach suites
/// needs one. Most of them only ever script `ask` and have no reason to name
/// stages, so this mixin supplies the obvious `askStream` — [ask]'s own
/// result (or its exception) as the stream's one event — once, rather than
/// the same seven lines repeated in six files.
///
/// `coach_client_stream_test.dart` exercises the REAL `askStream` (stages,
/// the SSE framing, the 404 fallback); this mixin is for fakes that were
/// never testing that surface in the first place.
library;

import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';

/// Mix into a `CoachClient` fake that implements [ask].
mixin AskAsStream {
  /// The fake's own scripted answer (or throw).
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic});

  /// [ask]'s result, as the one event `CoachClient.askStream` promises on
  /// success. An exception from [ask] surfaces as the stream's error, which
  /// is exactly how the real client's own 404-fallback path behaves.
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    yield CoachAnswerEvent(await ask(messages, topic: topic));
  }
}
