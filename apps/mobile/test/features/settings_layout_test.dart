/// The supporting screens' **painted** geometry: their order, and their width.
///
/// ## Order, against the prototype rather than against the code
///
/// `design/mobile-preview/screens-settings.js` fixes what each screen shows and
/// in what sequence. A test that walked the widget tree would pass on any
/// arrangement the code happens to build; these read the painted `dy` of each
/// landmark and require it to increase, which is the question a reader of the
/// screen actually asks.
///
/// ## Width, at phone widths and never at 800
///
/// `flutter test` defaults to an 800 × 600 viewport, **wider than any phone this
/// app runs on**, and this project has already shipped a card that overflowed by
/// 110 px behind exactly that default — `ServerSessionCard`'s two buttons in a
/// `Row`, invisible to every suite because every suite pumped 800. So every
/// screen is pumped at 320 · 360 · 390 · 414 and two things are required:
///
///   * `tester.takeException()` is null — a `RenderFlex` overflow is reported
///     through `FlutterError` and lands there;
///   * no painted card is wider than the page, measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';

import '_settings_harness.dart';

/// 320 is the narrowest phone still in use; 414 is a large one. The 800 px
/// default is deliberately absent.
const List<double> kHandsetWidths = <double>[320, 360, 390, 414];

/// Requires the painted LEFT edges of [finders] to increase, in order.
///
/// For the landmarks the prototype lays out side by side — the three sync
/// stages — where a vertical assertion would be asking the wrong question.
void expectPaintedRow(WidgetTester tester, List<Finder> finders) {
  var previous = double.negativeInfinity;
  for (final Finder finder in finders) {
    expect(finder, findsWidgets, reason: 'missing landmark: $finder');
    final left = tester.getTopLeft(finder.first).dx;
    expect(
      left,
      greaterThan(previous),
      reason: '$finder is painted left of the landmark before it',
    );
    previous = left;
  }
}

/// Requires the painted top edges of [finders] to increase, in order.
void expectPaintedOrder(WidgetTester tester, List<Finder> finders) {
  var previous = double.negativeInfinity;
  for (final Finder finder in finders) {
    expect(finder, findsWidgets, reason: 'missing landmark: $finder');
    final top = tester.getTopLeft(finder.first).dy;
    expect(
      top,
      greaterThan(previous),
      reason: '$finder is painted above the landmark before it',
    );
    previous = top;
  }
}

/// Requires every painted card to sit inside the page's own column.
void expectNothingOverflows(WidgetTester tester, double width) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'something overflowed at ${width}px',
  );
  const inset = SettingsPage.horizontalPadding;
  for (final Finder cards in <Finder>[
    find.byType(PlainCard),
    find.byType(FlushCard),
  ]) {
    for (final Element element in cards.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget).first);
      expect(
        rect.width,
        lessThanOrEqualTo(width - inset * 2 + 0.5),
        reason: 'a card is wider than the page at ${width}px',
      );
      expect(rect.left, greaterThanOrEqualTo(inset - 0.5));
    }
  }
}

Future<void> _pumpAt(
  WidgetTester tester,
  double width,
  String location, {
  bool signedIn = false,
  bool paired = true,
}) async {
  tester.view
    ..physicalSize = Size(width, 3400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    settingsApp(
      location: location,
      strap: paired ? pairedStrap : null,
      day: dayWithSync(),
      signedIn: signedIn,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the section order is the prototype’s', () {
    testWidgets('Settings: profile, device, experience, account', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.settings);
      expectPaintedOrder(tester, <Finder>[
        // **The eyebrow is gone from every detail head.** It drew a small line
        // over a bigger title saying the same thing — `Profile & settings`
        // above `Make it yours.` — so the head is now the screen's own name,
        // once. `DetailHeader` keeps the parameter and ignores it.
        find.text('Settings'),
        // The profile row prints the owner's own figures — age, height, the
        // latest weigh-in — and falls back to naming the destination only when
        // none of them is known, which is this fixture.
        find.text('Your measurements and self-reports'),
        find.text('Your connected device'),
        find.text('Amazfit Helio Strap'),
        find.text('Your experience'),
        find.text('Appearance'),
        find.text('Your account'),
        find.text('Account & server'),
      ]);
    });

    testWidgets('Appearance: prompt, tiles, then the two sections', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.appearance);
      expectPaintedOrder(tester, <Finder>[
        find.text('Choose your light.'),
        find.text('The same familiar app, comfortable at any hour.'),
        find.text('Light'),
        find.text('Gentle by default'),
      ]);
    });

    testWidgets('Reminders: prose, the wind-down toggle, then its time', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.reminders);
      expectPaintedOrder(tester, <Finder>[
        find.textContaining('Your day doesn’t need more noise.'),
        find.text('Time to wind down'),
        find.text('Wind-down time'),
        find.text('Save reminders'),
      ]);
      // The daily-focus and challenge notices went with the Actions tab.
      expect(find.text('Your daily focus'), findsNothing);
      expect(find.text('Challenge reflections'), findsNothing);
      expect(find.text('Daily focus time'), findsNothing);
    });

    testWidgets('Background: prose, switches, intervals, then sync status', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.background);
      expectPaintedOrder(tester, <Finder>[
        find.textContaining('collect from the strap'),
        find.text('Background collection and upload'),
        find.text('Unmetered networks only'),
        find.text('Only while charging'),
        find.text('Collection interval'),
        find.text('Upload interval'),
        find.text('View sync status'),
      ]);
    });

    testWidgets('Device: figure, name, stats, sync, then the two rows', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.device);
      expectPaintedOrder(tester, <Finder>[
        find.text('Your Helio Strap'),
        find.text('Amazfit Helio Strap'),
        find.text('Last full sync'),
        find.text('Sync now'),
        find.text('Data & sync details'),
      ]);
    });

    testWidgets('Data freshness: stages, banner, list, sync, preferences', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.dataFreshness);
      // The three stages sit side by side — `.sync-stages` is a flex row — so
      // their order is horizontal and everything after them is vertical.
      expectPaintedRow(tester, <Finder>[
        find.text('Helio Strap'),
        find.text('On your phone'),
        find.text('Your server'),
      ]);
      expectPaintedOrder(tester, <Finder>[
        find.text('Helio Strap'),
        find.text('Data freshness'),
        find.text('Sync now'),
        find.text('Background preferences'),
      ]);
    });

    testWidgets('Account: the privacy card, the form, then the two rows', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.serverSignIn);
      expectPaintedOrder(tester, <Finder>[
        find.text('A private connection'),
        // The password form is what a build without defines shows now — the
        // server names its provider at sign-in time, so there is nothing to
        // decide at build time. `settings_screen_test.dart` argues it.
        find.text('Sign in to your server'),
        find.text('Server address'),
        find.text('Email'),
        find.text('Sign in'),
        find.text('How this app signs in'),
        find.text('Your data & privacy'),
      ]);
    });

    testWidgets('About: emblem, headline, the trust card, the licences', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.about);
      expectPaintedOrder(tester, <Finder>[
        find.text('About Healthee'),
        find.text('Built around your trust'),
        find.text('Data with a source.'),
        find.text('Useful when you’re offline.'),
        find.text('No diagnosis behind a score.'),
        find.text('Licences and notices'),
      ]);
    });

    testWidgets('Welcome: brand, intro, glimpse, buttons, strap row', (
      tester,
    ) async {
      await _pumpAt(tester, 390, Routes.welcome);
      expectPaintedOrder(tester, <Finder>[
        find.text('healthee'),
        find.text('A health companion that knows your rhythm.'),
        find.text('A glimpse of your day'),
        find.text('Connect your server'),
        find.text('Already have a Helio Strap?'),
      ]);
    });

    testWidgets('Pairing: figure, headline, timeline, then the step', (
      tester,
    ) async {
      // Nothing paired: a phone that already holds a strap is shown what it
      // holds instead of the flow, which is the point of `PairedSummary`.
      await _pumpAt(tester, 390, Routes.pairing, paired: false);
      expectPaintedOrder(tester, <Finder>[
        find.text('A quiet connection.'),
        find.text('Your health starts here.'),
        find.text('Find your strap'),
        find.text('Connect securely'),
        find.text('Bring your data together'),
      ]);
    });
  });

  group('no card overflows on a phone', () {
    for (final double width in kHandsetWidths) {
      testWidgets('every supporting screen fits at ${width}px', (tester) async {
        for (final String location in <String>[
          Routes.settings,
          Routes.appearance,
          Routes.reminders,
          Routes.background,
          Routes.device,
          Routes.dataFreshness,
          Routes.about,
          Routes.welcome,
          Routes.profile,
        ]) {
          await _pumpAt(tester, width, location);
          expectNothingOverflows(tester, width);
        }
      });

      testWidgets('the session card fits at ${width}px', (tester) async {
        // The exact card that overflowed by 110 px behind the 800 px default.
        await _pumpAt(tester, width, Routes.serverSignIn, signedIn: true);
        expectNothingOverflows(tester, width);
      });
    }
  });
}
