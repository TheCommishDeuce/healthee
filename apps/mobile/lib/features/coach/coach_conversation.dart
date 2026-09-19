/// What the coach thread holds — a sealed list, so no entry renders as nothing.
///
/// Three kinds of entry, and the third is the one that matters: a question that
/// did not produce an answer stays **in the thread**, with what went wrong and
/// whether it cost anything. A failure that removed the question, or left it
/// looking unanswered, is how "did that use one of my twenty?" becomes a question
/// the app cannot answer.
///
/// The union is sealed for the reason `data/honesty/reading.dart` gives about
/// `Reading`: a fourth kind added later is a compile error at every rendering
/// site rather than a row that silently draws blank.
library;

import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:meta/meta.dart';

/// One entry in the thread.
@immutable
sealed class CoachEntry {
  /// Base constructor. Use one of the cases.
  const CoachEntry();
}

/// Something the owner asked.
final class OwnerQuestion extends CoachEntry {
  /// [text] is exactly what was typed, trimmed.
  const OwnerQuestion(this.text);

  /// The question.
  final String text;
}

/// Something the coach answered, with everything that qualifies it.
final class CoachReply extends CoachEntry {
  /// [answer] carries the citations, the grade floor and the refund flags.
  const CoachReply(this.answer, {this.live = false});

  /// The answer as the server sent it.
  final CoachAnswer answer;

  /// True for an answer that arrived over the wire in THIS session, which the
  /// thread reveals a sentence at a time. One restored from history is shown
  /// whole: it was already read once.
  final bool live;
}

/// The question did not reach an answer.
final class CoachTrouble extends CoachEntry {
  /// [charge] is what this app may honestly say about the meter.
  const CoachTrouble({
    required this.message,
    required this.charge,
    this.resetsAt,
  });

  /// What went wrong, in the owner's terms.
  final String message;

  /// What is known about whether a question was consumed.
  ///
  /// This was a `bool spent`, and the boolean was the defect rather than a
  /// carrier of it. Its own docstring said *"only ever true when we cannot say
  /// it wasn't"* — a value `grep -rn "spent: true" lib/` never found anywhere,
  /// so the type could describe a state the code could not build, and every
  /// failure fell into the false branch and printed a denial. A two-value
  /// [CoachCharge] makes the honest answer sayable and the flattering one
  /// unrepresentable, which is the same move `Reading` makes for a number.
  final CoachCharge charge;

  /// When the window reopens, on a refusal that carried it.
  final DateTime? resetsAt;
}

/// The whole thread, plus whether a question is in flight.
@immutable
class CoachConversation {
  /// A thread. [asking] is true from the moment the request leaves.
  const CoachConversation({
    this.entries = const [],
    this.asking = false,
    this.progress,
  });

  /// Oldest first.
  final List<CoachEntry> entries;

  /// Whether a question is in flight. The input is disabled while it is: the
  /// server meters one question per request, and a second request sent from the
  /// same thread would spend a second slot on a conversation the owner has not
  /// seen the answer to yet.
  final bool asking;

  /// The most recent stage `POST /api/coach/stream` has reported for the
  /// in-flight question, or null before the first one arrives.
  ///
  /// Typed off the wire in `data/coach/coach_stream_event.dart` — this field
  /// is never a raw `stage` string, so `CoachWaiting` renders a stage it knows
  /// rather than guessing how to word one it does not (Standards §3).
  final CoachStageEvent? progress;

  /// Whether anything has been asked in this thread.
  bool get isEmpty => entries.isEmpty;

  /// The conversation as the router wants it.
  ///
  /// Trouble entries are **not** sent: they carry this app's own words about a
  /// transport failure, and putting them in the model's context would be feeding
  /// the coach a sentence nobody said to it.
  List<CoachTurn> toWire() {
    final wire = <CoachTurn>[];
    for (final entry in entries) {
      // Exhaustive over the sealed union, so a fourth kind is a compile error
      // here rather than a turn silently dropped from the model's context.
      switch (entry) {
        case OwnerQuestion(:final text):
          wire.add(CoachTurn(role: 'user', content: text));
        case CoachReply(:final answer):
          wire.add(CoachTurn(role: 'assistant', content: answer.reply));
        case CoachTrouble():
          break;
      }
    }
    return wire;
  }

  /// The same conversation with [entries], [asking] and/or [progress]
  /// replaced.
  ///
  /// [progress] follows the usual `?? this.progress` rule — pass a new value
  /// to replace it. [clearProgress] is the escape hatch a nullable field
  /// needs: there is no way to tell "replace with null" apart from "did not
  /// pass this one" through `??` alone, and a stage from the turn that just
  /// finished should not linger onto the next one.
  CoachConversation copyWith({
    List<CoachEntry>? entries,
    bool? asking,
    CoachStageEvent? progress,
    bool clearProgress = false,
  }) => CoachConversation(
    entries: entries ?? this.entries,
    asking: asking ?? this.asking,
    progress: clearProgress ? null : (progress ?? this.progress),
  );
}
