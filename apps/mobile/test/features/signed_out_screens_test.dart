/// B2, carried to every server-backed screen: signed out, a screen asks the
/// owner to sign in. It never says it "couldn't reach your server" — no server
/// was contacted, and blaming one sends the owner looking for a fault that does
/// not exist.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/shared/screen_data.dart';

import '_settings_harness.dart' show tallViewport;
import '_today_host.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() => store.close());

  final screens = <String, Widget Function()>{
    'Recovery': () => const RecoveryScreen(),
    'Body': () => const BodyScreen(),
    'Fitness': () => const FitnessScreen(),
    'Sleep': () => const SleepScreen(),
    'Sleep history': () => const SleepHistoryScreen(),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name, signed out: "sign in", never "couldn\'t reach"', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          signedIn: false,
          signedOutServer: true,
          home: build(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsNothing);
      expect(find.text(kSignInNeeded), findsOneWidget);
      // Retrying cannot sign anyone in.
      expect(find.text('Try again'), findsNothing);
    });
  }
}
