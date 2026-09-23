/// The host both pairing suites pump, and the two gestures they share.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
///
/// `pairing_screen_test.dart` owns the flow — the async states, the account
/// route, the manual fallback and an already-paired phone — and
/// `pairing_failures_test.dart` owns the named failures. They stand the same
/// screen up over the same fakes, so the host lives here rather than twice:
/// two copies of an override list is two chances to forget one, and a forgotten
/// override surfaces as "pumpAndSettle timed out", which says nothing about
/// either suite.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/sync/sync_outcome.dart';
import 'package:healthee/features/pairing/pairing_screen.dart';

import '../pairing/_pairing_fakes.dart';
import '../pairing/_zepp_stub.dart';

/// The strap both suites pair to.
const String kPairingMac = 'DB:98:1F:80:4C:3D';

/// Its key. Never rendered — several assertions turn on that.
const String kPairingAuthKey = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// The pairing screen over a keystore, a Zepp account and a radio, all faked.
Widget pairingHost(
  FakeSecretStore store, {
  StubAdapter? adapter,
  FakeStrapScanner? scanner,
}) {
  return ProviderScope(
    overrides: [
      credentialsProvider.overrideWithValue(Credentials(store)),
      pairingRepositoryProvider.overrideWithValue(
        PairingRepository(
          credentials: Credentials(store),
          zepp: clientWith(adapter ?? happyPathAdapter()),
          scanner: scanner ?? FakeStrapScanner(),
        ),
      ),
      // Pairing now runs a sync (B1). The real controller reaches the store and
      // the radio; `pairing_resyncs_test.dart` owns that behaviour.
      syncControllerProvider.overrideWith(_NoSync.new),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const PairingScreen(),
    ),
  );
}

/// Pumps [app] into a viewport tall enough to hit-test the whole flow.
///
/// v02 draws the flow inside one scrolling page, under a device figure, a
/// headline, an opening paragraph and a three-step timeline — so the buttons
/// that used to sit inside the default 800x600 window are now below its fold,
/// and a tap on a widget that is built but off-screen misses SILENTLY. What
/// these suites assert is what each state does, never what fits above the fold.
Future<void> pumpPairing(WidgetTester tester, Widget app) async {
  tester.view
    ..physicalSize = const Size(420, 2400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

/// Fills the sign-in form and submits it.
Future<void> signInToZepp(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'owner@example.com');
  await tester.enterText(find.byType(TextField).last, 'hunter2');
  await tester.tap(find.text('Find my straps'));
  await tester.pumpAndSettle();
}

/// A sync controller that never touches the store or the radio.
class _NoSync extends SyncController {
  @override
  StrapConnection build() => const Disconnected();

  @override
  Future<SyncOutcome?> syncNow() async => null;
}
