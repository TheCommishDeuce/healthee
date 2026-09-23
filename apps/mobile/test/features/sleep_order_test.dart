/// Sleep is the v02 prototype's screen, in the prototype's order — held here.
///
/// `design/mobile-preview/sleep-history-view.js::H.screens.sleep` is one
/// template literal, and the only way a re-ordering, a dropped panel or a panel
/// that crept back in gets caught is by reading the section list and comparing
/// it to the prototype entry by entry. A rendered scroll cannot do it: most of
/// this screen is off the viewport and a lazy list has not built it.
///
/// The order below was transcribed with the prototype open in a browser
/// (`python3 -m http.server --directory design/mobile-preview`), scrolled top to
/// bottom at 390 px. Every entry names the prototype construct it came from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/v02/checks_panel.dart';
import 'package:healthee/features/sleep/v02/naps_panel.dart';
import 'package:healthee/features/sleep/v02/need_panel.dart';
import 'package:healthee/features/sleep/v02/night_panels.dart';
import 'package:healthee/features/sleep/v02/sleep_reading.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/features/sleep/v02/vitals_panel.dart';
import 'package:healthee/features/sleep/v02/week_panel.dart';
import 'package:healthee/features/sleep/v02/withheld_night.dart';
import 'package:healthee/shared/findings_section.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/page_header.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

void main() {
  group("the prototype's order, entry by entry", () {
    test('EVERY SECTION THE PROTOTYPE DRAWS IS DRAWN, AND IN ITS ORDER', () {
      final list = sleepList();
      final order = <int>[
        // `H.header('Sleep','')` — the date, the h1, the avatar.
        indexOfSection<V02PageHeader>(list),
        // **This app's own, and FIRST.** The prototype has no box for the
        // night's written reading, and the owner asked for it above the
        // charts: it is the answer, and the panels under it are the working.
        indexOfSection<SleepAnalysisPanel>(list),
        // `.sleep-reading` and the `.colour-key` under it.
        indexOfSection<SleepReading>(list),
        // `H.panel('How your night unfolded', …, 'sleep-history','moon')`.
        indexOfSection<NightTimelinePanel>(list),
        // `H.panel('Every stage, accounted for', …)`.
        indexOfSection<StageTablePanel>(list),
        // `H.panel('Your body overnight','oxygen', …, 'metrics','heart')`.
        indexOfSection<OvernightPanel>(list),
        // `H.panel('Your four sleep checks', …)`.
        indexOfSection<SleepChecksPanel>(list),
        // `H.panel('Sleep need & debt', …)`.
        indexOfSection<SleepNeedPanel>(list),
        // `H.panel('Your week, stage by stage', …)`.
        indexOfSection<StageWeekPanel>(list),
        // `H.panel('Sleep timing', …, '', 'clock')`.
        indexOfSection<SleepTimingPanel>(list),
        // ⛔ **No `Beyond a single night`** and nothing the prototype put under
        // it (F2): the owner found it all redundant with the panels above and
        // with Sleep history. Only the day's naps survive — below.
        // `H.panel('Naps & your day', …)` — the fixture's night has a nap.
        indexOfSection<NapsPanel>(list),
        // `H.footer()`.
        indexOfSection<DataFooter>(list),
      ];
      for (final index in order) {
        expect(index, isNonNegative, reason: 'a prototype section is missing');
      }
      // Strictly increasing: every section sits after the one the prototype
      // puts before it. This is the assertion a re-order fails.
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i],
          greaterThan(order[i - 1]),
          reason: 'section $i is out of the prototype’s order',
        );
      }
    });

    test('NOTHING FROM "BEYOND A SINGLE NIGHT" DOWN IS DRAWN (F2)', () {
      // With a tonight lever AND findings on hand, so this is not passing
      // because there was nothing to draw.
      final withLever = SleepConsistency.fromJson(<String, Object?>{
        ...loadJson(kConsistencySnapshotPath),
        'tonight': const <String, Object?>{
          'title': 'Lights out by 23:00',
          'lever': 'bedtime',
          'target_clock': '23:00',
          'action': 'Start winding down at 22:15.',
        },
      });
      expect(sleepPageFixture().findings, isNotEmpty);
      final types = sectionTypes(sleepList(consistency: withLever));
      for (final gone in <Type>[
        ChapterHeading,
        FindingsSection,
      ]) {
        expect(types, isNot(contains(gone)), reason: '$gone');
      }
    });

    test('NAPS ARE THE DAY’S OWN, AND ABSENT ON A DAY WITHOUT ONE', () {
      // The fixture's one nap is on its newest night; a second, on the night
      // before, proves each day draws its own and only its own.
      final json = loadJson(kSleepSnapshotPath);
      final nights = json['nights']! as List<Object?>;
      final latest = (nights[0]! as Map<String, Object?>)['date']! as String;
      final before = (nights[1]! as Map<String, Object?>)['date']! as String;
      final quiet = (nights[2]! as Map<String, Object?>)['date']! as String;
      final nap = (json['naps']! as List<Object?>).single! as Map<String, Object?>;
      final page = SleepPage.fromJson(<String, Object?>{
        ...json,
        'naps': <Object?>[
          nap,
          <String, Object?>{...nap, 'date': before},
        ],
      });
      List<String?>? napDatesOn(String day) {
        for (final section in sleepList(page: page, day: day)) {
          if (section.child case final NapsPanel panel) {
            return <String?>[for (final n in panel.naps) n.date];
          }
        }
        return null;
      }

      expect(napDatesOn(latest), <String>[latest]);
      // A past day's nap is dated data like its night, so it is drawn there.
      expect(napDatesOn(before), <String>[before]);
      // No nap that day: no panel, rather than a panel saying so.
      expect(napDatesOn(quiet), isNull);
    });

    test('the analysis is the stated exception to the prototype order', () {
      final list = sleepList();
      // **`SleepAnalysisPanel` is the stated exception**, the second after the
      // stale banner: the owner asked for the night's written reading above the
      // charts rather than under them. An exception that is written down and
      // asserted is a decision; one that is merely true is a drift.
      expect(
        indexOfSection<SleepAnalysisPanel>(list),
        lessThan(indexOfSection<SleepReading>(list)),
      );
    });

    test('THE STALE BANNER IS THE ONE EXCEPTION, AND IT IS NEAR THE TOP', () {
      // A sentence saying "everything below is from an older night" is worth
      // nothing underneath the thing it qualifies.
      final list = sleepList(now: kSleepNow.add(const Duration(days: 7)));
      final banner = indexOfSection<StaleNightNotice>(list);
      expect(banner, isNonNegative);
      expect(banner, lessThan(indexOfSection<SleepReading>(list)));
      // And it is absent on a fresh night, so it is a state rather than furniture.
      expect(indexOfSection<StaleNightNotice>(sleepList()), -1);
    });
  });

  group('the gaps are v02’s two rungs, not legacy’s four', () {
    test('THE SCREEN USES THOSE TWO AND NOTHING ELSE', () {
      final gaps = <double>{
        for (final section in sleepList())
          if (section.gap > 0) section.gap,
      };
      expect(gaps, isNotEmpty);
      expect(
        gaps.difference(<double>{PageSpacing.panel, PageSpacing.block}),
        isEmpty,
        reason:
            'a literal at a call site is how a ladder stops being one — see '
            'page_section.dart',
      );
    });
  });

  group('nothing on this screen combines the four dimensions', () {
    test('NO SECTION IS A SLEEP SCORE', () {
      // `/api/sleep` sends `score` — how many of the four passed — and no
      // surface may draw it. `feedback_no_composite_score`: three out of four
      // is a tally of unlike things and a reader will take it for a mark.
      final names = <String>[
        for (final section in sleepList())
          section.child.runtimeType.toString().toLowerCase(),
      ];
      for (final name in names) {
        expect(name, isNot(contains('score')));
      }
    });

    test('the payload really does carry the count this screen refuses', () {
      // Proves the test above is refusing something rather than passing because
      // there was never anything to refuse.
      expect(sleepPageFixture().nights.first.healthScore.hasValue, isTrue);
    });
  });
}
