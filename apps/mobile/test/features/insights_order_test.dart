/// Insights is the v02 prototype's screen, in the prototype's order — held here.
///
/// `design/mobile-preview/screens-overview.js::H.screens.insights` is one
/// template literal, and the only way a re-ordering, a dropped panel or a panel
/// that crept back in gets caught is by reading the section list and comparing
/// it to the prototype entry by entry. A rendered scroll cannot do it: most of
/// the screen is off the viewport and a lazy sliver list has not built it.
///
/// The order below was transcribed with the prototype open in a browser
/// (`python3 -m http.server --directory design/mobile-preview`), scrolled top to
/// bottom at 390 px. Every entry names the prototype construct it came from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/features/insights/insights_sections.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/features/insights/widgets/notable_events.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/shared/findings_section.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/age_entry_card.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/entry_card.dart';
import 'package:healthee/shared/v02/list_rows.dart';
import 'package:healthee/shared/v02/page_header.dart';
import 'package:healthee/shared/v02/section_head.dart';

import '../_today_stubs.dart';
import '_screen_data.dart';

/// The section list, built the way the screen builds it.
List<PageSection> sections({
  Map<String, Object?> Function(Map<String, Object?> json)? mutate,
}) => insightsSections(
  screenData(server: todayView(mutate: mutate)),
  const InsightsExtras(),
);

int _indexOf<T>(List<PageSection> list) =>
    list.indexWhere((section) => section.child is T);

void main() {
  group("the prototype's order, entry by entry", () {
    test('EVERY SECTION THE PROTOTYPE DRAWS IS DRAWN, AND IN ITS ORDER', () {
      final list = sections();
      final order = <int>[
        // `H.header('Insights', …)`.
        _indexOf<V02PageHeader>(list),
        // `.relationship-grid` — one pattern of the owner's own, and the age.
        _indexOf<EntryGrid>(list),
        // ⛔ No `Effort & stress` panel and no bridge under it (F4): that is
        // the current day's material, and Activity carries it.
        // `H.section('Your longer patterns', …, 'metrics','All metrics')`.
        _indexOf<SectionHead>(list),
        // The `.twin-panels` of `H.miniTrend(...)` under it.
        _indexOf<TrendsGrid>(list),
        // ⛔ No `What changed together?` findings list (F4, owner). The top
        // pattern stays reachable from the entry card above.
        // The notable days — this app's own server surface, kept.
        _indexOf<NotableEvents>(list),
        // The two `.list-row`s: Sleep history and Fitness estimates.
        _indexOf<FlushCard>(list),
        // `H.footer()`.
        _indexOf<DataFooter>(list),
      ];
      for (final index in order) {
        expect(index, isNonNegative, reason: 'a prototype section is missing');
      }
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i],
          greaterThan(order[i - 1]),
          reason: 'section $i is out of the prototype’s order',
        );
      }
    });

    test('the one section head is "Your longer patterns"', () {
      final list = sections();
      final heads = <String>[
        for (final section in list)
          if (section.child is SectionHead)
            (section.child as SectionHead).title,
      ];
      expect(heads, <String>['Your longer patterns']);
    });

    test('NOTHING OWNER-CUT IS DRAWN, EVEN WITH ITS DATA ON HAND (F4)', () {
      final list = sections();
      // The fixture has findings and a full hourly day, so these are absent
      // because they were cut, not because there was nothing to draw.
      expect(_indexOf<EntryGrid>(list), isNonNegative);
      for (final gone in <int>[
        _indexOf<FindingsSection>(list),
        _indexOf<ContextBridge>(list),
      ]) {
        expect(gone, -1);
      }
      expect(
        list.map((s) => s.child.runtimeType.toString()),
        isNot(contains('EffortStressPanel')),
      );
    });
  });

  group('the gaps are v02’s two rungs, not legacy’s four', () {
    test('THE SCREEN USES THOSE TWO AND NOT LEGACY’S LADDER', () {
      final gaps = <double>{
        for (final section in sections())
          if (section.gap > 0) section.gap,
      };
      expect(
        gaps.difference(<double>{PageSpacing.panel, PageSpacing.block}),
        isEmpty,
        reason:
            'a v02 screen uses one ladder or the other; a legacy rung here is '
            'the two systems drifting into one screen',
      );
    });
  });

  group('the conditional sections are the payload’s conditions', () {
    test('NO TRENDS MEANS NO HEADING — a heading over nothing is dead', () {
      final none = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'sparklines': const <String, Object?>{},
        },
      );
      expect(_indexOf<TrendsGrid>(none), -1);
      final heads = <String>[
        for (final section in none)
          if (section.child is SectionHead)
            (section.child as SectionHead).title,
      ];
      expect(heads, isNot(contains('Your longer patterns')));
      // And the block that follows is untouched: a silent section is not a
      // truncated screen.
      expect(_indexOf<NotableEvents>(none), isNonNegative);
    });

    test('no findings means no findings block, and no pattern card', () {
      final none = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'top_findings': const <Object?>[],
        },
      );
      expect(_indexOf<FindingEntryCard>(none), -1);
      expect(_indexOf<FlushCard>(none), isNonNegative);
    });

    test('ONE ENTRY CARD DRAWS ALONE RATHER THAN BESIDE A HOLE', () {
      final oneCard = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'top_findings': const <Object?>[],
        },
      );
      expect(_indexOf<EntryGrid>(oneCard), -1);
      expect(_indexOf<AgeEntryCard>(oneCard), isNonNegative);
    });

    test('neither card means no grid at all', () {
      final none = sections(
        mutate: (json) => <String, Object?>{
          ...json,
          'top_findings': const <Object?>[],
          'biological_age': <String, Object?>{
            ...json['biological_age']! as Map<String, Object?>,
            'contributions': const <Object?>[],
          },
        },
      );
      expect(_indexOf<EntryGrid>(none), -1);
      expect(_indexOf<AgeEntryCard>(none), -1);
      expect(_indexOf<FindingEntryCard>(none), -1);
    });
  });
}
