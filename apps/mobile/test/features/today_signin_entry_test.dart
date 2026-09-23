/// The way in, from Today — and the way it stays out of the way.
///
/// Two claims, and the second is the one that is easy to break later:
///
///  1. a phone with no server session **says so**, in the section that already
///     speaks about sync state, and offers the way in;
///  2. it is a **sentence and a link, not a wall** — every measurement the strap
///     produced is still on the screen, and a phone that IS signed in reads
///     exactly as it did before.
///
/// The second is what makes strap-only a supported mode rather than a degraded
/// one. `core/router.dart` deliberately does not redirect on a missing token,
/// and `today_screen_test.dart`'s "no network at all" cases are what would break
/// first if that ever changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/not_signed_in.dart';
import 'package:healthee/data/models/data_health.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/widgets/data_health_section.dart';
import 'package:healthee/shared/screen_data.dart';

import '_screen_data.dart';
import '_today_host.dart';

/// The section on its own, with nothing else to report.
Widget _sectionHost({bool? signedIn, VoidCallback? onSignIn}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: DataHealthSection(signedIn: signedIn, onSignIn: onSignIn, now: now),
    ),
  );
}

void main() {
  group('the data-health section, on its own', () {
    testWidgets('signed out: it says so, and offers the way in', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _sectionHost(signedIn: false, onSignIn: () => opened++),
      );

      expect(
        find.textContaining('not signed in to a Healthee server'),
        findsOneWidget,
      );
      // It names what is still working, so the sentence is not a scolding.
      expect(find.textContaining('still being recorded here'), findsOneWidget);

      await tester.tap(find.text('Sign in to your server'));
      expect(opened, 1);
    });

    testWidgets('signed in with nothing wrong: it renders nothing at all', (
      tester,
    ) async {
      await tester.pumpWidget(_sectionHost(signedIn: true, onSignIn: () {}));

      expect(find.text('Data health'), findsNothing);
      expect(find.text('Sign in to your server'), findsNothing);
    });

    testWidgets('NOT YET KNOWN is silence, not an invitation', (tester) async {
      // The keystore read is asynchronous. Announcing "not signed in" for the
      // frames it takes would flash the invitation at an owner who already is.
      await tester.pumpWidget(_sectionHost(onSignIn: () {}));

      expect(find.text('Data health'), findsNothing);
    });

    testWidgets('with no route to offer, the sentence still renders', (
      tester,
    ) async {
      await tester.pumpWidget(_sectionHost(signedIn: false));

      expect(
        find.textContaining('not signed in to a Healthee server'),
        findsOneWidget,
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('it composes with the other lines rather than replacing them', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DataHealthSection(
              signedIn: false,
              onSignIn: () {},
              health: const DataHealth(
                overall: 'stale',
                syncStatus: 'stale',
                syncedAgeHours: 91,
                items: [
                  FeedHealth(
                    metric: 'hr',
                    label: 'Heart rate',
                    status: 'stale',
                    ageHours: 91,
                    lastIso: null,
                  ),
                ],
              ),
              now: now,
            ),
          ),
        ),
      );

      expect(find.textContaining('not signed in'), findsOneWidget);
      expect(find.text('Heart rate'), findsOneWidget);
    });
  });

  group('on the Today screen itself', () {
    late LocalStore store;

    setUp(() async {
      store = LocalStore.memory();
      await seedDevice(store);
    });
    tearDown(() async => store.close());

    testWidgets('a signed-out phone is invited, and keeps every measurement', (
      tester,
    ) async {
      // Signed out AND unreachable, which is the real pair: a phone with no
      // session gets no payload. Legacy's Today is entirely server-backed, so
      // this is the state where the measured half has to carry the screen on
      // its own — see `_measuredOnly` in `today_sections.dart`.
      tester.view
        ..physicalSize = const Size(420, 3000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        todayHost(store, signedIn: false, serverUnreachable: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in to your server'), findsOneWidget);
      // Not a wall: the strap's own numbers are on the same screen. The daily
      // step counter is the phone's own reading and needs no server at all.
      expect(find.text('6h 20m'), findsOneWidget);
    });

    testWidgets('SIGNED OUT, THE SERVER IS NOT BLAMED (B2)', (tester) async {
      tester.view
        ..physicalSize = const Size(420, 3000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        todayHost(store, signedIn: false, serverUnreachable: true),
      );
      await tester.pumpAndSettle();

      // The data-health card already says "sign in" and offers the way in; a
      // second card saying the server could not be reached was false — no
      // server was ever contacted.
      expect(find.textContaining("Couldn't reach your server"), findsNothing);
      expect(find.text('Sign in to your server'), findsOneWidget);
    });

    testWidgets('a signed-in phone is not nagged', (tester) async {
      final pending = await store.pushReader.pending();
      await store.pushReader.markPushed(pending, now);

      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to your server'), findsNothing);
    });

    testWidgets('a fresh install with nothing at all still gets the way in', (
      tester,
    ) async {
      // The empty-day branch is a different list, and it is exactly where a new
      // owner lands — so the invitation has to be on that one too.
      final empty = LocalStore.memory();
      addTearDown(() async => empty.close());

      await tester.pumpWidget(
        todayHost(empty, signedIn: false, serverUnreachable: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing from your strap yet'), findsOneWidget);
      expect(find.text('Sign in to your server'), findsOneWidget);
    });
  });

  testWidgets('a typed sign-in refusal reads as "sign in", never as a fault', (
    tester,
  ) async {
    final data = screenData(
      serverState: const AsyncError<TodayView>(
        NotSignedIn(),
        StackTrace.empty,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: data.serverFailure!.child),
      ),
    );

    expect(find.textContaining("Couldn't reach"), findsNothing);
    expect(find.text(kSignInNeeded), findsOneWidget);
    // No retry: retrying cannot sign anyone in.
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
