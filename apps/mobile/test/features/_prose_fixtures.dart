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
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/data/models/sleep_consistency.dart';

import '_citation_probe.dart';

/// A recommendation whose three model-written fields each cite something
/// different — so a surface that grounds only one of them fails here.
final Recommendation kRec = Recommendation.fromJson(const <String, Object?>{
  'id': 7,
  'action': 'Sleep earlier tonight [sleep_need_debt].',
  'expected_effect': 'About 30 minutes off your debt [sleep_regularity_index].',
  'rationale': 'Your debt is 120 minutes [recovery_readiness].',
  'category': 'sleep',
  'evidence_grade': 2,
  'research_note_ids': <String>['vo2max'],
  'signal_source': 'sleep_debt',
  'adopted': null,
});

/// A challenge whose title cites inline and whose payload cites structurally.
final Challenge kChallenge = Challenge.fromJson(const <String, Object?>{
  'id': 3,
  'title': 'Walk 9,000 steps [exercise_mortality].',
  'why': 'Because it is a manageable step up.',
  'status': 'active',
  'metric': 'steps_total',
  'target_value': 9000,
  'comparator': '>=',
  'cadence': 'daily',
  'window_days': 7,
  'difficulty': 'moderate',
  'kind': 'standard',
  'research_note_ids': <String>['cadence'],
});

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
