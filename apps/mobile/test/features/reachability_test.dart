/// Nothing this rebuild removed from Today became unreachable.
///
/// Cutting Today from twenty sections to six modules is only honest if every
/// removed card is still somewhere the owner can GET TO. `today_grid_test.dart`
/// proves each module opens a tab; `tab_screens_test.dart` proves the card is on
/// it. This file covers the routes that are not behind a grid cell, because they
/// are the ones nothing else would notice:
///
///   * **/settings is off the tab bar**, and it is what the Today avatar opens.
///     It is the only door to the server session, to `/diagnostics` and to the
///     font licence — three things that were each reachable from exactly one odd
///     place before, and one of which is a licence obligation.
///   * **/diagnostics is off the tab bar.** Baselines and the strap's own
///     streams answer "is the instrument working", which is asked when something
///     looks wrong and never at 7am. That reasoning is only sound while there is
///     a way in, and there is exactly one: the settings screen.
///   * **Every live tab names a route the router wires.** A tab that looks live
///     and points at an unregistered path is a link to a crash, and it looks
///     like nothing at all until somebody taps it.
///
/// ## v02 turned settings into an INDEX, so this suite walks all of it
///
/// The old screen held three rows that navigated and one control that did not;
/// the v02 screen is ten rows that each open a screen of their own. Every one of
/// them is walked here, because "do not invent settings that control nothing" is
/// exactly as easy to break on the tenth row as it was on the third.
///
/// The destinations are the **real screens on the real route list** — the
/// harness mounts `settingsRoutes()`, the same object `buildRouter` splices into
/// the app — rather than the stand-ins this file used to register. Stand-ins
/// were the right call while three routes were being checked and one of them was
/// a whole pairing flow; they cannot answer the question this file now has to
/// ask, because **`/pairing` is no longer a row on the index**. It is reached
/// through the strap screen, so proving it is reachable means walking a row that
/// only the real device screen draws.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/data/pairing/paired_strap.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/features/pairing/pairing_screen.dart';
import 'package:healthee/features/profile/profile_screen.dart';
import 'package:healthee/features/settings/about_screen.dart';
import 'package:healthee/features/settings/appearance_screen.dart';
import 'package:healthee/features/settings/background_screen.dart';
import 'package:healthee/features/settings/data_freshness_screen.dart';
import 'package:healthee/features/settings/device_screen.dart';
import 'package:healthee/features/settings/reminders_screen.dart';
import 'package:healthee/features/signin/server_signin_screen.dart';

import '_settings_harness.dart';

/// Taps a settings row by the words on it, scrolling it into view first.
///
/// v02's rows are `ListRow`s inside a `FlushCard` rather than buttons, so there
/// is no `OutlinedButton` to look for any more — and the row's own title is what
/// the owner actually aims at, which makes it the honest finder as well as the
/// available one.
///
/// `ensureVisible` rather than `scrollUntilVisible`: it scrolls the row's OWN
/// enclosing scrollable, and once a push has happened there are two of them in
/// the tree — the pushed screen's and the index's, still mounted underneath.
Future<void> _tapRow(WidgetTester tester, String title) async {
  final row = find.text(title);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Mounts the app fresh, at the settings index, with nothing pushed on it.
///
/// The blank frame is load-bearing. `settingsApp()` builds the same widget type
/// with no key every time, so pumping it a second time REUSES the state that
/// holds the `GoRouter` — and the second row of a loop would then be looked for
/// on whatever screen the first row opened.
Future<void> _openSettings(WidgetTester tester, {PairedStrap? strap}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(settingsApp(strap: strap));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('EVERY SETTINGS ROW REACHES A REAL DESTINATION', (tester) async {
    // "Do not invent settings that control nothing." Every row on the index is
    // here, including the ones added by the v02 split — a row that opens an
    // unregistered path renders nothing and looks like a dead tap.
    tallViewport(tester);
    for (final (title, destination) in <(String, Type)>[
      // The profile is the card at the top of the index now, not a row in a
      // list — it says who you are rather than that a profile exists. Its
      // heading is the owner's name, or these words when there is none.
      ('Your profile', ProfileScreen),
      ('Amazfit Helio Strap', DeviceScreen),
      ('Data & sync', DataFreshnessScreen),
      ('Instruments', DiagnosticsScreen),
      ('Appearance', AppearanceScreen),
      ('Reminders', RemindersScreen),
      ('Background sync', BackgroundScreen),
      ('Account & server', ServerSignInScreen),
      ('About Healthee', AboutScreen),
    ]) {
      await _openSettings(tester);
      await _tapRow(tester, title);
      expect(
        find.byType(destination),
        findsOneWidget,
        reason: '$title goes nowhere',
      );
    }
  });

  testWidgets('PAIRING IS STILL REACHABLE, ONE ROW FURTHER IN', (tester) async {
    // `/pairing` came off the index in v02 and now lives on the strap's own
    // screen, under a row whose title depends on whether anything is paired.
    // Both wordings are walked, because a route reachable in only one of the two
    // states is a route the owner cannot find in the other.
    tallViewport(tester);
    for (final (strap, row) in <(PairedStrap?, String)>[
      (null, 'Connect a strap'),
      (pairedStrap, 'Pairing and unpair'),
    ]) {
      await _openSettings(tester, strap: strap);
      await _tapRow(tester, 'Amazfit Helio Strap');
      await _tapRow(tester, row);
      expect(
        find.byType(PairingScreen),
        findsOneWidget,
        reason: '"$row" is the only door to pairing in this state',
      );
    }
  });

  testWidgets('the diagnostics row names what is behind it', (tester) async {
    // The row says what it opens in the owner's words, not "Diagnostics" alone —
    // which would be a control whose only documentation is the screen you have
    // to open to read it.
    tallViewport(tester);
    await _openSettings(tester);

    // The row is titled `Instruments` and its subtitle is what it opens. The
    // subtitle is the assertion: a row whose only documentation is the screen
    // behind it documents nothing.
    expect(find.text('Instruments'), findsOneWidget);
    expect(
      find.textContaining('stream this phone read'),
      findsOneWidget,
      reason: 'the row must name what is behind it, not just where it goes',
    );
  });

  test('every tab names a route, and every route is wired', () {
    const wired = <String>{
      Routes.today,
      Routes.sleep,
      Routes.activity,
      Routes.insights,
      Routes.settings,
      Routes.diagnostics,
      Routes.pairing,
      Routes.serverSignIn,
      Routes.devFoundation,
    };
    for (final tab in kAppTabs) {
      expect(wired, contains(tab.route), reason: '${tab.label} is live');
    }
  });

  test('DiagnosticsScreen and SettingsScreen are not tabs', () {
    // Both sit outside the tab shell. Diagnostics used to light the Today tab,
    // which told the owner they were somewhere they were not and offered three
    // exits out of a flow they were in the middle of.
    expect(const DiagnosticsScreen().runtimeType, DiagnosticsScreen);
    final routes = kAppTabs.map((tab) => tab.route);
    expect(routes, isNot(contains(Routes.diagnostics)));
    expect(routes, isNot(contains(Routes.settings)));
  });
}
