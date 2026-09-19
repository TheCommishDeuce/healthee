/// Where a validated answer may be cut so it can appear piece by piece.
///
/// The answer arrives whole — the server checks every claim before it ships,
/// so nothing is streamed word by word from the model — and the thread reveals
/// it a sentence at a time so the reply reads as being written rather than
/// dropped in. The cuts are indices into the ORIGINAL string, so every prefix
/// is the answer's own text up to that point: nothing is re-spaced, re-joined
/// or paraphrased on the way to the screen, and the last prefix is the answer
/// exactly.
///
/// A cut falls after a sentence terminator (with any closing quote or bracket)
/// that is followed by whitespace and the start of something new, or at a line
/// break. A citation written as `[note_id]` before the full stop stays with
/// its sentence; one written after it opens the next piece, which is still the
/// answer's own text.
library;

final RegExp _boundary = RegExp(
  r'''[.!?…][\)\]"'”’]*(?=\s+[A-Z0-9\[\(\-•*"“])|\n+''',
);

/// Monotonic end indices of each reveal step; the last one is `text.length`.
/// A blank answer yields no steps at all.
List<int> revealCuts(String text) {
  if (text.trim().isEmpty) {
    return const <int>[];
  }
  final cuts = <int>[];
  for (final match in _boundary.allMatches(text)) {
    final int end = match.end;
    if (end > 0 && end < text.length && (cuts.isEmpty || end > cuts.last)) {
      cuts.add(end);
    }
  }
  if (cuts.isEmpty || cuts.last != text.length) {
    cuts.add(text.length);
  }
  return cuts;
}

/// How long to hold between steps: a whole answer takes about two seconds
/// however long it is, bounded so a one-line reply is not instantaneous and a
/// very long one does not crawl.
Duration revealInterval(int steps) {
  if (steps <= 1) {
    return Duration.zero;
  }
  final int ms = (2200 / steps).round().clamp(70, 300);
  return Duration(milliseconds: ms);
}
