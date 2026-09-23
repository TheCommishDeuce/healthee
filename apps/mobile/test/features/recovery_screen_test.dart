/// The recovery screen: the model opened up, and each signal against its own
/// baseline.
///
/// What this suite holds:
///
///   * **The ladder positions a signal from its own standard score**, and a
///     signal with no baseline gets no marker at all. Drawing it at the centre
///     line would assert it is exactly normal, which is the claim
///     `recovery_signals.dart` says we must not make.
///   * **The bridge names a share only when the model sent one.** The prototype
///     writes "Sleep contributes 40%" into the copy; here it comes off
///     `factors[].weight` or it is not said.
///   * **A refused recovery draws the refusal**, and the rest of the screen —
///     the overnight measurements, which are not the model — still draws.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/features/today/v02/recovery_detail_panels.dart';
import 'package:healthee/features/today/v02/recovery_panel.dart';
import 'package:healthee/shared/v02/signal_chart.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_today_stubs.dart';
import '_settings_harness.dart' show tallViewport;
import '_today_host.dart';

/// A score whose sleep factor carries no weight.
const RecoveryScore _scoreWithoutSleepWeight = RecoveryScore(
  recovery: 72,
  readiness: 36,
  band: null,
  guidance: null,
  factors: <RecoveryFactor>[
    RecoveryFactor(
      name: 'sleep',
      subScore: 60,
      weight: null,
      value: null,
      baseline: null,
      tstMin: null,
      needMin: null,
    ),
  ],
  noteId: null,
  date: null,
);

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  group('the ladder', () {
    test('POSITIONS A SIGNAL FROM ITS OWN STANDARD SCORE', () {
      // The centre is the owner's baseline, and the band edges are ±1σ on a
      // ±3σ axis — 1/6 and 5/6, which is the 32%/68% the CSS draws.
      expect(SignalChart.position(0), 0.5);
      expect(SignalChart.position(-1), closeTo(1 / 3, 0.001));
      expect(SignalChart.position(1), closeTo(2 / 3, 0.001));
      // Off the end of the axis is still on the track, never outside it.
      expect(SignalChart.position(9), 1.0);
      expect(SignalChart.position(-9), 0.0);
    });

    test('a signal with no baseline has NO position', () {
      expect(SignalChart.position(null), isNull);
      expect(SignalChart.position(double.nan), isNull);
    });

    testWidgets('draws one row per signal, with the payload’s readings', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(
        todayHost(store, server: todayView(), home: const RecoveryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text(BaselinePanel.title), findsOneWidget);
      expect(find.byType(SignalChart), findsOneWidget);
      expect(find.text(kBaselineNote), findsOneWidget);
      for (final caption in SignalChart.captions) {
        expect(find.text(caption), findsOneWidget);
      }
    });
  });

  group('the sleep bridge', () {
    test('NAMES A SHARE ONLY WHEN THE MODEL SENT ONE', () {
      expect(sleepShareBridge(0.4), startsWith('Sleep contributes 40% '));
      expect(sleepShareBridge(null), kNightBridge);
      expect(sleepWeight(_scoreWithoutSleepWeight), isNull);
    });

    testWidgets('is drawn with the payload’s own weight', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(
        todayHost(store, server: todayView(), home: const RecoveryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sleep contributes'), findsOneWidget);
      expect(find.text('Explore your sleep'), findsOneWidget);
    });
  });

  group('what a refusal leaves standing', () {
    testWidgets('the model is refused; the measurements still draw', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'recovery_score': <String, Object?>{
                ...json['recovery_score']! as Map<String, Object?>,
                'recovery': null,
                'withheld': <String, Object?>{
                  'reason': 'insufficient_nights',
                  'message': 'A few more nights of wear and this comes back.',
                },
              },
            },
          ),
          home: const RecoveryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WithheldPanel), findsWidgets);
      expect(find.textContaining('A few more nights'), findsWidgets);
      expect(find.text(RecoveryPanel.title), findsNothing);
      // The signals against their baselines are not the model, so they
      // survive it.
      expect(find.text(BaselinePanel.title), findsOneWidget);
      // The capacity panel needs the score, so it is gone with it.
      expect(find.text(CapacityPanel.title), findsNothing);
    });

    testWidgets('the whole screen draws on the real payload', (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(
        todayHost(store, server: todayView(), home: const RecoveryScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text(kRecoveryTitle), findsOneWidget);
      expect(find.text(RecoveryPanel.title), findsOneWidget);
      // The five overnight vitals live on Sleep, one link away (R2): the same
      // table here was the repeat the owner reported.
      expect(find.text('Your body overnight'), findsNothing);
      expect(find.text('Explore your sleep'), findsOneWidget);
      expect(find.text(CapacityPanel.title), findsOneWidget);
      expect(find.text(kCapacityNote), findsOneWidget);
    });
  });
}
