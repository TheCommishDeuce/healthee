/// Typed events out of `POST /api/coach/stream` — converted at the data
/// boundary so no feature code ever reads a raw `stage` string off the wire
/// (Standards §3: typed models at the data boundary).
///
/// The stream carries live progress before answering, because the product
/// rule that shapes it never shows a raw model token: an answer is validated
/// — citations, evidence grades, safety guardrails — before it ships, and is
/// sometimes rejected and rewritten. `checking` and `revising` name that.
///
/// This file owns only the WIRE shape. Turning a stream `error` event or a
/// pre-stream HTTP failure into this app's own [CoachRefusal]/[CoachUnreachable]
/// stays in `coach_client.dart`, because those exception types — and the
/// mapping from a status to them — already live there.
library;

import 'dart:convert';

import 'package:healthee/data/coach/coach_answer.dart';
import 'package:meta/meta.dart';

/// One phase of server-side work, named by the wire's own vocabulary.
enum CoachStage {
  /// Reading the owner's own data, before anything is asked of a model.
  context,

  /// The model reasoning, between tool calls.
  thinking,

  /// A tool call in flight. [CoachStageEvent.detail] names it.
  tool,

  /// The blocking validator checking citations, grades and guardrails.
  checking,

  /// The validator rejected a draft; the model is rewriting it.
  revising;

  /// Parses the wire's `stage` field. Null for a value this app does not
  /// know — the contract requires an unknown stage to be ignored, never a
  /// crash, because the wire may grow before this app is rebuilt.
  static CoachStage? fromWire(String value) => switch (value) {
    'context' => CoachStage.context,
    'thinking' => CoachStage.thinking,
    'tool' => CoachStage.tool,
    'checking' => CoachStage.checking,
    'revising' => CoachStage.revising,
    _ => null,
  };
}

/// One event out of `CoachClient.askStream`.
@immutable
sealed class CoachStreamEvent {
  /// Base constructor. Use one of the cases.
  const CoachStreamEvent();
}

/// Live progress, before the answer is ready.
final class CoachStageEvent extends CoachStreamEvent {
  /// [round] and [detail] are exactly the wire's own fields.
  const CoachStageEvent({
    required this.stage,
    required this.round,
    this.detail,
  });

  /// What phase the server is in right now.
  final CoachStage stage;

  /// Which gathering round this is.
  final int round;

  /// The tool name, when [stage] is [CoachStage.tool]. Null otherwise.
  final String? detail;
}

/// The validated answer — exactly what `POST /api/coach` returns.
final class CoachAnswerEvent extends CoachStreamEvent {
  /// [answer] parses with the one [CoachAnswer.fromJson] this app has.
  const CoachAnswerEvent(this.answer);

  /// The turn's answer.
  final CoachAnswer answer;
}

/// A stream `error` event, before it becomes this app's own exception.
@immutable
class CoachStreamFailure {
  /// Built by [parseCoachStreamFailure].
  const CoachStreamFailure({required this.status, required this.message});

  /// The HTTP status the failure corresponds to. `0` when the payload did
  /// not carry one this app could read.
  final int status;

  /// What to tell the owner, already in this app's own words.
  final String message;
}

/// Parses one SSE `stage` event's `data`. Null for anything malformed or
/// naming a stage this app does not know — never a crash on a bad frame.
CoachStageEvent? parseCoachStageEvent(String data) {
  final Map<String, Object?>? json = _decodeObject(data);
  final Object? stageValue = json?['stage'];
  if (stageValue is! String) {
    return null;
  }
  final CoachStage? stage = CoachStage.fromWire(stageValue);
  if (stage == null) {
    return null;
  }
  final Object? round = json?['round'];
  final Object? detail = json?['detail'];
  return CoachStageEvent(
    stage: stage,
    round: round is num ? round.toInt() : 0,
    detail: detail is String ? detail : null,
  );
}

/// Parses one SSE `answer` event's `data` with the one [CoachAnswer] parser
/// this app has. Null when the payload is not even a JSON object.
CoachAnswer? parseCoachAnswerEvent(String data) {
  final Map<String, Object?>? json = _decodeObject(data);
  return json == null ? null : CoachAnswer.fromJson(json);
}

/// Parses one SSE `error` event's `data`. Never throws: a payload this app
/// cannot read falls back to status `0`, a message that names nothing more
/// than "something went wrong", and `CoachClient` maps both the same way it
/// maps any status that is not 401/402/403.
CoachStreamFailure parseCoachStreamFailure(String data) {
  final Map<String, Object?>? json = _decodeObject(data);
  final Object? status = json?['status'];
  final Object? message = json?['message'];
  return CoachStreamFailure(
    status: status is num ? status.toInt() : 0,
    message: message is String
        ? message
        : 'Your server stopped answering partway through.',
  );
}

Map<String, Object?>? _decodeObject(String data) {
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    return null;
  }
  return decoded is Map<String, Object?> ? decoded : null;
}
