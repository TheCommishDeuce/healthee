/// The sleep-history screen: a month of nights, and the way into one of them.
///
/// What this suite holds:
///
///   * **A night the strap did not record still gets a row.** The prototype
///     draws `— → —` and no duration, and that is the honest render: the list is
///     the calendar, and a missing night is a fact about the calendar rather
///     than a row to leave out.
///   * **The rows are buttons.** `docs/V02_CONNECTIVITY.md` section 0 records
///     that they set the viewed day and then go to Sleep, which is the whole
///     reason this screen is not just a chart.
///   * **The duration series carries its gaps.** A night with no total enters
///     the line as a hole, never as a zero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/sleep/v02/history_panels.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/reveal_once.dart';

import '../_sleep_stubs.dart';
import '_settings_harness.dart' show tallViewport;
import '_today_host.dart';

/// The fixture page with its newest night's session and total taken away.
SleepPage _pageWithUnmeasuredNight() {
  final json = loadJson(kSleepSnapshotPath);
  final nights = json['nights']! as List<Object?>;
  final latest = Map<String, Object?>.from(
    nights.first! as Map<String, Object?>,
  );
  for (final field in <String>[
    'session_source',
    'start_iso',
    'end_iso',
    'tst_min',
    'duration_min',
  ]) {
    latest[field] = null;
  }
  return SleepPage.fromJson(<String, Object?>{
    ...json,
    'nights': <Object?>[latest, ...nights.skip(1)],
  });
}

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  testWidgets('THE MONTH AND EVERY NIGHT AS A ROW — NO SECOND STAGE WEEK (R1)', (tester) async {
    tallViewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        sleep: sleepPageFixture(),
        home: const SleepHistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(kSleepHistoryTitle), findsOneWidget);
    expect(find.text(SleepDurationPanel.title), findsOneWidget);
    expect(find.byType(V02LineChart), findsOneWidget);
    // The 7-night stage chart lives on Sleep ("Your week, stage by stage");
    // drawing the identical chart here was the repeat the owner reported (R1).
    expect(find.byType(HStackedSleep), findsNothing);
    expect(find.text('Open a night'), findsOneWidget);
    // The fixture carries thirty nights and the window is thirty.
    expect(find.byType(NightRow), findsNWidgets(30));
  });

  testWidgets('AN UNRECORDED NIGHT STILL GETS ITS ROW, AND SAYS SO', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        sleep: _pageWithUnmeasuredNight(),
        home: const SleepHistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // One more absent row than the fixture already has: the strap did not
    // record every night in the window, and the screen says so for each of
    // them rather than shortening the list.
    final unrecorded = _pageWithUnmeasuredNight().nights
        .take(30)
        .where((night) => night.start == null)
        .length;
    expect(find.byType(NightRow), findsNWidgets(30));
    expect(find.text('— → —'), findsNWidgets(unrecorded));
    expect(
      unrecorded,
      sleepPageFixture().nights.take(30).where((n) => n.start == null).length +
          1,
    );
  });

  test('the row formats an absence rather than inventing one', () {
    final page = _pageWithUnmeasuredNight();
    final missing = page.nights.first;
    expect(NightRow.span(missing), '— → —');
    expect(NightRow.duration(missing), '—');

    final measured = sleepPageFixture().nights.first;
    expect(NightRow.span(measured), contains('→'));
    expect(NightRow.duration(measured), isNot('—'));
  });

  test('the duration series keeps a gap as a gap, never as a zero', () {
    final panel = SleepDurationPanel(
      nights: _pageWithUnmeasuredNight().nights.take(30).toList(),
      reveals: RevealRegistry(),
    );
    // Oldest first, so the blanked night is the LAST point.
    expect(panel.series.last, isNull);
    expect(panel.series.where((value) => value == 0), isEmpty);
    expect(panel.measured, 29);
    expect(panel.note, startsWith('29 dated samples through '));
  });

  testWidgets('DURATION READS IN HOURS AND MINUTES, NEVER RAW MINUTES (B4)', (
    tester,
  ) async {
    tallViewport(tester);
    final nights = sleepPageFixture().nights.take(30).toList();
    final latest = nights.first.tstMin.valueOrNull!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SleepDurationPanel(nights: nights, reveals: RevealRegistry()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(hoursMinutes(latest)), findsOneWidget);
    expect(find.text('min'), findsNothing);
    final chart = tester.widget<V02LineChart>(find.byType(V02LineChart));
    // The axis is in hours, so its ticks read 6 · 7 · 8 rather than 360 · 420.
    expect(chart.values.whereType<double>().first, lessThan(24));
    expect(chart.format!(6.5), '6h 30m');
  });

  testWidgets('A ROW IS A BUTTON: IT REPORTS THE NIGHT IT OPENS', (
    tester,
  ) async {
    tallViewport(tester);
    final opened = <String>[];
    await tester.pumpWidget(
      todayHost(
        store,
        sleep: sleepPageFixture(),
        home: Builder(
          builder: (context) => SleepHistoryDetail(
            page: sleepPageFixture(),
            reveals: RevealRegistry(),
            onOpenNight: (context, date) => opened.add(date),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = sleepPageFixture().nights.first.date;
    await tester.tap(find.byType(NightRow).first);
    await tester.pumpAndSettle();
    expect(opened, <String>[first]);
  });

  testWidgets('nothing recorded draws the empty state, not an empty card', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        sleep: SleepPage.fromJson(const <String, Object?>{
          'nights': <Object?>[],
        }),
        home: const SleepHistoryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No sleep recorded yet'), findsOneWidget);
    expect(find.byType(NightRow), findsNothing);
  });
}
