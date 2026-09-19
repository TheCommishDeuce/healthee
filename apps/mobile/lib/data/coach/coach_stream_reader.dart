/// Turns a `POST /api/coach/stream` byte stream — and a pre-stream failure
/// dio could not decode — into this app's own vocabulary.
///
/// Split out of `coach_client.dart` at the 400-line gate (Standards §1).
/// [CoachClient.askStream] is the only caller; this file owns the mechanics,
/// that one owns the wire call and the fallback to [CoachClient.ask].
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/coach/sse_parser.dart';

/// Said when the byte stream ends without an `answer` or an `error` — the
/// gate has already run by the time these bytes arrive (the server only
/// reaches `200` after charging the slot), so this reads like a receive
/// timeout on the non-streaming call, not like a request that never left.
const String _droppedMidwaySentence =
    'Your server stopped answering partway through. It may still be '
    'working on this, and the question may already have been asked.';

/// Turns the SSE byte stream into typed events, ending on the answer.
///
/// The gate has already run by the time these bytes arrive — the server only
/// reaches `200` after charging the slot — so every failure here is
/// [CoachCharge.unknown]: this app cannot say a charged question was not
/// spent just because the socket closed while reading the reply.
Stream<CoachStreamEvent> readCoachStream(Stream<List<int>> bytes) async* {
  try {
    await for (final event in parseSseStream(bytes)) {
      switch (event.event) {
        case 'stage':
          final stage = parseCoachStageEvent(event.data);
          if (stage != null) {
            yield stage;
          }
        case 'draft':
          final draft = parseCoachDraftEvent(event.data);
          if (draft != null) {
            yield draft;
          }
        case 'answer':
          final answer = parseCoachAnswerEvent(event.data);
          if (answer == null) {
            throw const CoachUnreachable(
              _droppedMidwaySentence,
              CoachCharge.unknown,
            );
          }
          yield CoachAnswerEvent(answer);
          return;
        case 'error':
          throw coachStreamException(parseCoachStreamFailure(event.data));
        default:
        // An event name this app does not know. Ignored, never a crash —
        // the wire contract may grow before this app is rebuilt.
      }
    }
  } on DioException catch (error, stackTrace) {
    AppLog.failure('coach', 'reading /api/coach/stream', error, stackTrace);
  }
  // Either the `DioException` above fell through, or the byte stream simply
  // closed — dropped mid-turn either way, with neither `answer` nor `error`
  // seen.
  throw const CoachUnreachable(_droppedMidwaySentence, CoachCharge.unknown);
}

/// A stream `error` event as this app's own exception — the same two types
/// [CoachClient.ask] throws, chosen the same way `_chargeFrom` does: 402 is
/// the metered refusal, 401/403 could not have been charged, anything else is
/// a charge this app cannot rule out.
Exception coachStreamException(CoachStreamFailure failure) {
  if (failure.status == 402) {
    return CoachRefusal(message: failure.message);
  }
  if (failure.status == 401 || failure.status == 403) {
    return CoachUnreachable(failure.message, CoachCharge.notCharged);
  }
  return CoachUnreachable(failure.message, CoachCharge.unknown);
}

/// Reads a pre-stream error body dio left as raw bytes — the request's
/// `responseType` is [ResponseType.stream] — and decodes it into the same map
/// shape [CoachClient.ask] gets for free, so [error] flows into
/// `CoachClient`'s own status-to-exception mapping unchanged.
Future<void> materializeStreamError(DioException error) async {
  final data = error.response?.data;
  if (data is! ResponseBody) {
    return;
  }
  final text = await utf8.decoder.bind(data.stream).join();
  if (text.isEmpty) {
    return;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error, stackTrace) {
    AppLog.failure('coach', 'decoding a stream error body', error, stackTrace);
    return;
  }
  if (decoded is Map<String, Object?>) {
    error.response!.data = decoded;
  }
}
