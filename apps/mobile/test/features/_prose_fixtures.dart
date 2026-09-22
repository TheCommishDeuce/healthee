/// The payloads every prose-grounding suite drives, and the one assertion they
/// share.
///
/// Split out of `prose_grounding_test.dart` at 512 lines (Standards section 1).
/// The suites say what must be true of a surface; this file says what a surface
/// is handed, and the two change for different reasons — a new call site edits a
/// suite, a new shape of payload edits this.
///
/// Every fixture cites **more than one thing, in more than one way**: an inline
/// `[note_id]` in each model-written field, and a structured id beside them. A
/// surface that grounds only its headline, or only what the payload sent
/// separately, fails.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/data/models/sleep_consistency.dart';

import '_citation_probe.dart';

/// The sleep lever — one sentence, one inline marker.
final TonightLever kLever = TonightLever.maybe(const <String, Object?>{
  'title': 'Lights out earlier',
  'lever': 'bedtime',
  'target_clock': '23:15',
  'coach': 'Aim for 23:15 tonight [sleep_regularity_index].',
})!;

/// The ids the sheet behind [surface]'s ⓘ must be carrying: exactly what
/// [parseGrounded] reads out of [prose], plus anything the payload sent.
void expectGrounds(
  WidgetTester tester,
  Type surface,
  String prose, {
  List<String> alsoCites = const <String>[],
}) {
  final expected = groundingOf(prose, alsoCites: alsoCites);
  expect(
    expected.noteIds,
    isNotEmpty,
    reason: 'the fixture cites nothing, so this assertion proves nothing',
  );
  final detail = detailIn(tester, find.byType(surface));
  for (final id in expected.noteIds) {
    expect(
      detail.notes,
      contains(id),
      reason: '$surface draws prose citing "$id" and its ⓘ does not carry it',
    );
  }
}
