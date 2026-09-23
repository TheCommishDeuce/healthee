/// What reaches the Sleep screen's surface, and what must never reach it.
///
///   * **no raw `snake_case` id and no `[` marker on any surface** — the whole
///     screen is scrolled and every string on it is read;
///   * `naps[].stages` carries the strap's per-stage MINUTES, as a night's does,
///     and the panel no longer blames the server for a breakdown it now sends;
///   * `findings` draws nothing when it is empty, and something when it is not;
///   * and the screen lays out at four phone widths, none of them 800.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/sleep/v02/naps_panel.dart';
import 'package:healthee/features/sleep/v02/stage_shares.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';
import '_today_host.dart';

/// A `snake_case` word of the kind a research-note id or a metric key is.
final RegExp _rawId = RegExp(r'\b[a-z][a-z0-9]*(_[a-z0-9]+){2,}\b');

/// Every string the widget tree is currently rendering.
List<String> _renderedText(WidgetTester tester) => <String>[
  for (final widget in tester.allWidgets)
    if (widget is Text)
      widget.data ?? widget.textSpan?.toPlainText() ?? ''
    else if (widget is RichText)
      widget.text.toPlainText(),
];

void main() {
  late LocalStore store;

  setUpAll(loadSleepFont);
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  group('nothing raw reaches a surface', () {
    testWidgets('NO snake_case ID AND NO [ MARKER, ANYWHERE ON THE SCREEN', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        todayHost(store, home: SleepScreen(now: kSleepNow)),
      );
      await tester.pumpAndSettle();

      // Scrolled to the bottom, because a lazy list has not built what is off
      // screen and an id could be hiding in any of it.
      for (var pass = 0; pass < 12; pass++) {
        for (final text in _renderedText(tester)) {
          expect(
            _rawId.hasMatch(text),
            isFalse,
            reason: 'a raw id reached the screen: "$text"',
          );
          expect(
            text,
            isNot(contains('[')),
            reason: 'an unresolved citation marker reached the screen: "$text"',
          );
        }
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
    });
  });

  group('naps', () {
    test('THE SNAPSHOT CARRIES PER-STAGE MINUTES, NOT THE RAW HYPNOGRAM', () {
      // This asserted the opposite, with a note reading "if this passes maps
      // now, the server was fixed — drop this". It was: `read/sleep_page.py`
      // shipped the `[[startMs, endMs, typeCode]]` array under the key a NIGHT
      // uses for totals, so a nap's breakdown was structurally empty for every
      // owner (`docs/BACKEND_GAPS_FROM_UI.md` A1).
      //
      // Asserted on the committed contract snapshot, so the check is against the
      // wire rather than against a fixture this repo also writes.
      final raw = loadJson(kSleepSnapshotPath);
      final naps = raw['naps']! as List<Object?>;
      expect(naps, isNotEmpty);
      for (final nap in naps.cast<Map<String, Object?>>()) {
        expect(nap['stages'], isA<Map<String, Object?>>());
        expect(nap['stage_timeline'], isA<List<Object?>>());
      }
      // And the minutes survive the parse. `isNotEmpty` on a list would have
      // passed on a dict of zeroes; the total is what makes this a measurement.
      for (final nap in sleepPageFixture().naps) {
        // Non-null too: `stages` is nullable now precisely so an unstaged session
        // can say so, and the fixture's naps ARE staged.
        expect(nap.stages, isNotNull);
        expect(nap.stages!.total, greaterThan(0));
        expect(nap.stages!.isEmpty, isFalse);
      }
    });

    testWidgets('THE PANEL NO LONGER BLAMES THE SERVER FOR THE BREAKDOWN', (
      tester,
    ) async {
      // The sentence it used to print — "your server sends … not its stages" —
      // had become false, which is worse than the gap it described.
      await tester.pumpWidget(
        sleepPanelHost(NapsPanel(naps: sleepPageFixture().naps)),
      );
      await tester.pumpAndSettle();

      expect(find.text(kNapsUnstagedNote), findsNothing);
      // Still no stage bar, and that is the PROTOTYPE's call rather than the
      // payload's: `sleep-history-view.js` draws nap rows as text and has no
      // stage element on this panel. The old comment's "the bar can come back"
      // was reading the pre-v02 card as the specification.
      expect(
        find.descendant(
          of: find.byType(NapsPanel),
          matching: find.byType(StageShares),
        ),
        findsNothing,
      );
    });

    testWidgets('AN UNSTAGED NAP SAYS THE STRAP DID NOT STAGE IT', (
      tester,
    ) async {
      // The honest half of the sentence that went: a fact about the recording,
      // not a complaint about the wire. Only when NO nap on the panel carries a
      // breakdown — one that fired beside a fully staged nap would describe the
      // panel wrongly.
      await tester.pumpWidget(
        sleepPanelHost(NapsPanel(naps: <SleepNap>[unstagedNap()])),
      );
      await tester.pumpAndSettle();
      expect(find.text(kNapsUnstagedNote), findsOneWidget);
    });

    testWidgets('a day with no nap says so rather than drawing an empty list', (
      tester,
    ) async {
      await tester.pumpWidget(
        sleepPanelHost(const NapsPanel(naps: <SleepNap>[])),
      );
      await tester.pumpAndSettle();
      expect(find.text(kNoNapsNote), findsOneWidget);
    });
  });

  group('the screen lays out on a phone, and never at 800', () {
    for (final width in kSleepWidths) {
      testWidgets('no overflow at $width', (tester) async {
        tester.view
          ..physicalSize = Size(width, 2400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          todayHost(store, home: SleepScreen(now: kSleepNow)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (var pass = 0; pass < 10; pass++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'overflow at $width');
        }
      });
    }
  });
}
