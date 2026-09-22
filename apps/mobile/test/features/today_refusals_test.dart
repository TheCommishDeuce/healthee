/// What the app does when there is NO number: refusals, a dead server, a new
/// phone.
///
/// Split out of `today_screen_test.dart` at the 400-line gate. The seam is the
/// one that matters: that file proves the screen draws the data it has, and this
/// one proves it never draws data it does not.
///
/// **The refusals moved with their cards** — VO₂max to Activity, the metric strip
/// and the strap streams to Diagnostics — and the assertions moved with them
/// unchanged. That is deliberate: these are the mutations that must still fail,
/// and rewriting them to suit the new layout is how a guard quietly stops
/// guarding. The pumped screen is the only thing that differs from the version
/// that ran on Today.
///
/// The test that matters most, mutation-checked:
///
///   * **A WITHHELD VALUE IS NEVER A BARE NUMBER.** A screen that renders a
///     number where the payload sent a refusal is the one bug this whole
///     architecture exists to make impossible, and it is the last hop — the
///     compiler can force the switch, but only a test can prove the branch draws
///     the hole.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/ble/models/strap_sample.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/states/value_hole.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_today_stubs.dart';
import '../store/strap_store_test.dart' show resultWith;
import '_today_host.dart';

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.memory());
  tearDown(() async => store.close());

  group('refusals', () {
    testWidgets('A WITHHELD VALUE IS NEVER A BARE NUMBER', (tester) async {
      // Nothing but heart rate, so the strap's own steps have no counter behind
      // them; and VO₂max withheld the way production withholds it.
      await store.strapWriter.saveSync(
        resultWith(samples: [StrapSample(DateTime(2026, 8, 4, 9), 'hr', 68)]),
      );
      await tester.pumpWidget(
        todayHost(
          store,
          home: const ActivityScreen(),
          server: todayView(
            mutate: (json) => {
              ...json,
              'vo2max': <String, Object?>{
                ...json['vo2max']! as Map<String, Object?>,
                'estimate': null,
                'method': null,
                'method_caveat': null,
                'data_confidence': 'insufficient_data',
                'withheld': <String, Object?>{
                  'reason': 'logged_weight_stale',
                  'message':
                      'The last weight you logged is more than two weeks old, '
                      "so we can't call it your weight today — log a new one "
                      'and this comes straight back.',
                  'last_as_of_date': '2026-06-04',
                  'age_days': 57,
                  // The server puts the stale value INSIDE the block, "where
                  // nothing can mistake it for today's". This is the number a
                  // careless parser would promote back to the headline, so the
                  // fixture carries it on purpose.
                  'last_estimate': 43.0,
                },
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Scroll to the REMEDY rather than to the word: several blocks can be
      // withheld at once, and "the first WITHHELD on screen" is not this one.
      final remedy = find.textContaining('log a new one');
      await reveal(tester, remedy);

      // Activity is v02 now, so the carrier is `WithheldPanel` — the metric's
      // name, a DASHED hole and the server's reason, in the slot the panel
      // would have taken. The claim under it is the one that was always here.
      final card = find.ancestor(
        of: remedy,
        matching: find.byType(WithheldPanel),
      );
      expect(card, findsOneWidget);
      // It keeps its name, so a refusal is self-describing in a list.
      expect(
        find.descendant(of: card, matching: find.text('VO₂max · estimate')),
        findsOneWidget,
      );
      // A number-shaped hole where the figure would have been.
      expect(find.descendant(of: card, matching: find.text('—')), findsWidgets);
      expect(
        find.text('43.0'),
        findsNothing,
        reason: 'the withheld estimate must not appear anywhere as a number',
      );
      // A withhold is an answer, so it never offers a retry.
      expect(
        find.descendant(of: card, matching: find.text('Try again')),
        findsNothing,
      );
    });

    testWidgets('A WITHHELD METRIC ROW SHOWS A HOLE, NOT ITS BASELINE', (
      tester,
    ) async {
      // The last-hop bug this architecture exists to prevent, in its most
      // tempting form: the row HAS a 30-day median sitting right there, and
      // drawing it where today's value goes would look completely normal and be
      // a number the owner never recorded.
      await tester.pumpWidget(
        todayHost(
          store,
          home: DiagnosticsScreen(now: now),
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'metrics': [
                for (final card in json['metrics']! as List)
                  if ((card as Map<String, Object?>)['metric'] == 'rhr_daily')
                    <String, Object?>{
                      ...card,
                      'value': null,
                      'z': null,
                      'data_confidence': 'insufficient_data',
                      'withheld': <String, Object?>{
                        'reason': 'insufficient_nights',
                        'message':
                            'Fewer than 3 nights of resting heart rate in the '
                            'last week — wear the strap overnight for a few '
                            'more nights and this comes back.',
                      },
                    }
                  else
                    card,
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Against your own baseline'));

      final strip = find.ancestor(
        of: find.text('Against your own baseline'),
        matching: find.byType(StateCard),
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.textContaining('wear the strap overnight'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: strip, matching: find.byType(ValueHole)),
        findsWidgets,
      );
      expect(
        find.descendant(of: strip, matching: find.text('55')),
        findsNothing,
        reason:
            'the 30-day median is not a stand-in for a value we do not have',
      );
    });

    testWidgets('the strap and the server refuse in their own words', (
      tester,
    ) async {
      await store.strapWriter.saveSync(
        resultWith(samples: [StrapSample(DateTime(2026, 8, 4, 9), 'hr', 68)]),
      );
      await tester.pumpWidget(
        todayHost(store, home: DiagnosticsScreen(now: now)),
      );
      await tester.pumpAndSettle();
      // The section heading and each metric strip both say 'From the strap'
      // now that headings render in sentence case, so the scroll target names
      // the widget as well as the words — v02's `SectionHead`, which is what
      // this screen's headings are drawn with now.
      await reveal(tester, find.widgetWithText(SectionHead, 'From the strap'));

      // A stream the sensor did not write says "wear it". Collapsing that into
      // a server withhold would send the owner to the wrong place.
      expect(find.textContaining('The strap recorded no'), findsWidgets);
    });
  });

  group('the server is unreachable', () {
    testWidgets('the measurements still render, and the failure is ONE card', (
      tester,
    ) async {
      await seedDevice(store);
      // Tall enough that the fallback row below the failure card is built.
      tester.view
        ..physicalSize = const Size(420, 3000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(todayHost(store, serverUnreachable: true));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't reach your server"),
        findsOneWidget,
        reason: 'twenty error cards is the same news said twenty times',
      );
      expect(
        find.text('Try again'),
        findsOneWidget,
        reason:
            'and exactly one: the connection strip\'s own action says "Sync '
            'now", because re-fetching the server and re-reading the strap are '
            'different repairs',
      );
      expect(
        find.text('6h 20m'),
        findsOneWidget,
        reason: 'brief §7.4 — the app must be readable with no network',
      );
    });

    testWidgets('a cached payload says it is cached, and dates itself', (
      tester,
    ) async {
      await seedDevice(store);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            fromCache: true,
            fetchedAt: now.subtract(const Duration(days: 3)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Data health'), findsOneWidget);
      expect(
        find.textContaining('it describes 2026-07-31, 3 d ago'),
        findsOneWidget,
        reason: 'a fallback that hides itself is stale-as-current',
      );
    });

    testWidgets('a push backlog is said out loud, not hidden', (tester) async {
      await seedDevice(store);
      await store.pushReader.stampAttempt(
        at: now.subtract(const Duration(hours: 2)),
        outcomeId: 'failed',
        complete: false,
        failureReason: 'it could not be reached',
      );
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('measurements are still on this phone'),
        findsOneWidget,
      );
      expect(find.textContaining('it could not be reached'), findsOneWidget);
      expect(
        find.textContaining('they go out on the next sync'),
        findsNothing,
        reason:
            'a STUCK backlog is not a waiting one — the next sync fails the '
            'same way, so promising it would be flattery about our own state',
      );
    });
  });

  group('a phone that has never synced and has never reached the server', () {
    testWidgets('says so once, rather than twenty times', (tester) async {
      await tester.pumpWidget(todayHost(store, serverUnreachable: true));
      await tester.pumpAndSettle();

      expect(find.text('Nothing from your strap yet'), findsOneWidget);
      expect(find.byType(WithheldPanel), findsOneWidget,
          reason: 'missing local sleep stays a refusal, not a zero duration');
      expect(find.text('0h 0m'), findsNothing);
    });
  });
}
