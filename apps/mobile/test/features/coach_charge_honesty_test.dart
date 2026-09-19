/// A1 · what the thread says about the owner's money after a failure.
///
/// The server charges the slot **inside the gate, before the handler starts** —
/// deliberately, so it cannot be raced. It refunds on a refusal, an unvalidated
/// answer, a greeting and an exception. A *delivered* answer is none of those,
/// so a client that hangs up at ten seconds leaves the server producing an
/// answer, charging one of the owner's twenty, and returning it to a socket
/// nobody is reading.
///
/// The app then printed, above a meter it had just re-read and which correctly
/// showed one fewer: *"Nothing was counted for this."* Two false sentences on
/// one screen, contradicting the number between them.
///
/// The fix is a taxonomy the client can actually populate. `CoachTrouble.spent`
/// was a `bool` whose own docstring said it was "only ever true when we cannot
/// say it wasn't" — and `grep -rn "spent: true" lib/` found nothing, so that
/// case was a value the code could not build. These tests pin the two states
/// that exist, both directions, and that the flattering one is not reachable
/// from a failure the app did not see the end of.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/features/coach/coach_controller.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/widgets/coach_thread.dart';

import '../support/ask_as_stream.dart';

/// A client that always fails the ask with one scripted taxonomy value.
class _Failing with AskAsStream implements CoachClient {
  _Failing(this.failure);

  final CoachUnreachable failure;

  @override
  Future<Entitlement> entitlement() async =>
      Entitlement.fromJson(const <String, Object?>{
        'premium': true,
        'status': 'active',
        'locked': <String>[],
        'included': <Object?>[],
      });

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async =>
      throw failure;
}

Widget _thread(CoachTrouble trouble) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: CoachEntryView(entry: trouble)),
);

void main() {
  testWidgets('AN UNKNOWN CHARGE SAYS SO — it never denies one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _thread(
        const CoachTrouble(
          message: 'Your server did not finish answering in time.',
          charge: CoachCharge.unknown,
        ),
      ),
    );

    expect(
      find.textContaining('could not confirm whether this was counted'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nothing was counted'),
      findsNothing,
      reason: 'the app cannot see the gate, so it may not deny a charge',
    );
  });

  testWidgets('a charge the app CAN rule out is still stated flatly', (
    tester,
  ) async {
    // The other half. "A spend must never be silent" cuts both ways: a question
    // that was genuinely not charged has to say so, or the owner counts their
    // own.
    await tester.pumpWidget(
      _thread(
        const CoachTrouble(
          message: "Couldn't reach your server.",
          charge: CoachCharge.notCharged,
        ),
      ),
    );

    expect(find.textContaining('Nothing was counted for this'), findsOneWidget);
    expect(find.textContaining('could not confirm'), findsNothing);
  });

  test('THE CONTROLLER CARRIES THE CLIENT’S VERDICT, UNCHANGED', () async {
    // It used to flatten every transport failure to "not charged", which is how
    // a receive timeout on a delivered, charged answer printed a denial.
    final unknown = await _troubleFrom(
      const CoachUnreachable('took too long', CoachCharge.unknown),
    );
    expect(unknown.charge, CoachCharge.unknown);

    final flat = await _troubleFrom(
      const CoachUnreachable('never left', CoachCharge.notCharged),
    );
    expect(flat.charge, CoachCharge.notCharged);
  });

  testWidgets('the meter sentence is always present, whichever it is', (
    tester,
  ) async {
    for (final charge in CoachCharge.values) {
      await tester.pumpWidget(
        _thread(
          const CoachTrouble(
            message: 'x',
            charge: CoachCharge.unknown,
          ).copyForTest(charge),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('re-read just now'),
        findsOneWidget,
        reason: 'a failure that said nothing about the meter is a silent spend',
      );
    }
  });
}

/// The controller is the seam between the client's verdict and the thread's
/// sentence, and it is where the false denial was actually produced: it passed
/// `spent: false` on EVERY `CoachUnreachable`, whatever the client had worked
/// out. A widget test cannot see that — it is handed the entry already built.
Future<CoachTrouble> _troubleFrom(CoachUnreachable failure) async {
  final container = ProviderContainer(
    overrides: [coachClientProvider.overrideWithValue(_Failing(failure))],
  );
  addTearDown(container.dispose);
  await container.read(coachControllerProvider.notifier).ask('anything?');
  final entries = container.read(coachControllerProvider).entries;
  return entries.whereType<CoachTrouble>().single;
}

extension on CoachTrouble {
  /// The same entry with a different charge — a test helper, not app surface.
  CoachTrouble copyForTest(CoachCharge charge) =>
      CoachTrouble(message: message, charge: charge, resetsAt: resetsAt);
}
