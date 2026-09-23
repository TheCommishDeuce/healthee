/// A refused biological age is still a HERO — and a held value is always dated.
///
/// Two owner reports, one card:
///
///   * *"today is there the bio age and all those are missing"* — the hero
///     collapsed to a small dashed box followed by the whole regularity
///     exclusion, inline, because the composite `withheld` shape (`consequence`
///     + `terms`, no top-level `reason`) fell through the envelope to
///     `Excluded`.
///   * *"it should show the old one instead of completely not showing"* — and
///     the old one has to be visibly, unmissably old, because a stale value read
///     as current is the failure this whole product refuses.
///
/// Everything asserted here is **painted**: the paragraph's own layout result,
/// the opacity actually applied to the figure, the rect of the date line, and
/// the absence of any painter that could place a marker. A presence check would
/// pass for a hero that drew the halo over an empty square and called it done.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/last_known.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/v02/today_hero.dart';
import 'package:healthee/features/today/v02/today_hero_withheld.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/bio_hero.dart';
import 'package:healthee/shared/v02/bio_hero_parts.dart';
import 'package:healthee/shared/v02/instruments/age_scale.dart';
import 'package:healthee/shared/v02/instruments/bio_halo.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_today_stubs.dart';
import '../shared/_v02_harness.dart';
import '_today_host.dart';

/// The consequence paragraph `analytics/biological_age.py` actually sends.
const String kConsequence =
    'Biological age is your chronological age plus each term’s year '
    'contribution, so a term with no current value is not left out — it would '
    'silently assert you sit exactly at the reference for that lever.';

/// The fitness term's own remedy, verbatim from `derive/vo2max.py`.
const String kTermRemedy =
    'This estimate runs on your BMI, and the weight behind it is more than 14 '
    'days old — old enough that we’d be guessing at your mass, so we won’t '
    'guess at your fitness either. Log a weight and it returns.';

/// The regularity exclusion — the ~400 words the owner saw where the hero
/// belonged. Shortened here only in that the test needs one recognisable run.
const String kExclusionEssay =
    'Sleep regularity is not one of the levers behind this number. Scored on '
    'the same 70,000 people, the two standard Sleep Regularity Index '
    'calculators put only two in five into the same fifth of the population.';

/// The payload the owner's phone actually receives: no number, a composite
/// withheld block, and the standing exclusion beside it.
Map<String, Object?> withheldAge(Map<String, Object?> json) =>
    <String, Object?>{
      ...json,
      'biological_age': <String, Object?>{
        'biological_age': null,
        'delta_years': null,
        'chronological_age': 36,
        'data_confidence': 'insufficient_data',
        'withheld': <String, Object?>{
          'consequence': kConsequence,
          'terms': <Object?>[
            <String, Object?>{
              'term': 'fitness',
              'reason': 'logged_weight_stale',
              'message': kTermRemedy,
            },
          ],
        },
        'excluded': <Object?>[
          <String, Object?>{
            'term': 'regularity',
            'reason': 'sri_hazard_not_transportable',
            'message': kExclusionEssay,
          },
        ],
        'contributions': <Object?>[],
        'research_notes': <Object?>['biological_age_estimate'],
      },
    };

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester, {LastKnown<double>? held}) async {
    phone(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(mutate: withheldAge),
        home: const BodyScreen(),
        lastKnownBioAge: held,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the hero keeps its shape when the number is refused', () {
    testWidgets('SAME GROUND, SAME RADIUS, SAME EYEBROW, SAME WIDTH', (
      tester,
    ) async {
      // The live hero first, so the comparison is against what this screen
      // actually draws rather than against numbers copied into the test.
      phone(tester);
      await tester.pumpWidget(todayHost(store, home: const BodyScreen()));
      await tester.pumpAndSettle();
      final live = tester.getRect(find.byType(BioHero));
      final liveGround = _ground(tester);
      final liveEyebrow = tester.getRect(find.text(TodayBioHero.eyebrow));

      // Torn down between the two, so the second pump is a real remount rather
      // than a rebuild of the first tree with new overrides.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pump(tester);

      expect(find.byType(TodayBioHeroWithheld), findsOneWidget);
      expect(
        find.byType(WithheldPanel),
        findsNothing,
        reason:
            'the refused hero must not collapse into a panel — that is the '
            'small dashed box the owner read as the card being missing',
      );
      final refused = tester.getRect(find.byType(BioHero));
      expect(refused.width, live.width);
      expect(refused.left, live.left);
      // The ground and the corner are the hero's identity in both themes.
      final ground = _ground(tester);
      expect(groundOf(ground), groundOf(liveGround));
      expect(radiusOf(ground), radiusOf(liveGround));
      // The eyebrow sits exactly where it sits on a hero with a number.
      expect(
        tester.getRect(find.text(TodayBioHero.eyebrow)).left,
        liveEyebrow.left,
      );
    });

    testWidgets('THE ESSAY IS NOT INLINE; A SHORT REASON IS', (tester) async {
      await pump(tester);

      // The defect, asserted as an absence.
      expect(find.descendant(of: find.byType(BioHero), matching: find.textContaining('70,000 people')), findsNothing);
      expect(find.textContaining('Left out: regularity'), findsNothing);
      expect(find.textContaining('silently assert you sit'), findsNothing);

      // The replacement: the absent term named, and the exclusion signposted.
      expect(
        find.textContaining('no current value for fitness'),
        findsOneWidget,
      );
      expect(find.textContaining(kWithheldPointer), findsOneWidget);
      expect(
        find.textContaining('Left out of this number: regularity'),
        findsOneWidget,
      );
      // The whole caption is a handful of short lines, not a page. Asserted on
      // the builder rather than on the render, so a future edit that inlines an
      // essay again fails here whatever the layout does with it.
      final caption = TodayBioHeroWithheld.caption(
        _withheldProbe,
        const <Disclosure>[],
      );
      expect(caption.split('\n').length, lessThanOrEqualTo(3));
      expect(caption.length, lessThan(160));
      expect(caption, isNot(contains(kConsequence)));
    });

    testWidgets('NO MARKER IS DRAWN FOR A VALUE THAT DOES NOT EXIST', (
      tester,
    ) async {
      await pump(
        tester,
        held: const LastKnown<double>(value: 34.3, day: '2026-07-20'),
      );

      // The ruler is the only thing on this card that can place a mark. It is
      // not drawn at all — not even with the chronological age alone, which
      // would leave a single dot a reader takes for the estimate.
      expect(find.byType(AgeScale), findsNothing);
      expect(find.byKey(AgeScale.plotKey), findsNothing);
      // And no contribution row, so the held figure cannot become a term.
      expect(find.textContaining('contribution'), findsNothing);
      expect(
        find.textContaining('your chronological age of'),
        findsNothing,
        reason: 'a delta against today from a value that is not today’s',
      );
    });

    testWidgets('THE HALO DOES NOT RUN OVER AN ABSENT NUMBER', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(mutate: withheldAge),
          home: const BodyScreen(),
          reducedMotion: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(BioHalo), findsNothing);
      // The observable behind the decision: with motion allowed, a screen
      // carrying a live halo never goes idle. This one does — so there is no
      // ambient field turning around a number that is not there.
      var settled = true;
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 33),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 1),
        );
      }
      // ignore: avoid_catching_errors
      on FlutterError {
        settled = false;
      }
      expect(settled, isTrue);
    });
  });

  group('a held value is shown, and shown to be old', () {
    const held = LastKnown<double>(value: 34.3, day: '2026-07-20');

    testWidgets('THE DATE IS ON SCREEN, WHOLE, AND NEVER TRUNCATED', (
      tester,
    ) async {
      await pump(tester, held: held);

      final date = tester.widget<Text>(find.byKey(BioWithheldFigure.dateKey));
      expect(date.data, contains('20 July 2026'));
      expect(
        date.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'the date is what makes drawing the figure legitimate',
      );
      expect(date.maxLines, isNull);
      // Painted, not merely built: the line has real height inside the hero.
      final rect = tester.getRect(find.byKey(BioWithheldFigure.dateKey));
      expect(rect.height, greaterThan(0));
      expect(
        tester.getRect(find.byType(BioHero)).contains(rect.center),
        isTrue,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(BioWithheldFigure.dateKey),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
    });

    testWidgets('THE FIGURE IS DRAWN DIFFERENTLY FROM A CURRENT ONE', (
      tester,
    ) async {
      await pump(tester, held: held);

      expect(find.byKey(BioWithheldFigure.staleFigureKey), findsOneWidget);
      final faded = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(BioWithheldFigure.staleFigureKey),
          matching: find.byType(Opacity),
        ),
      );
      expect(faded.opacity, BioWithheldFigure.staleOpacity);
      expect(
        faded.opacity,
        lessThan(1),
        reason:
            'the figure must READ as not-current before a word is read — a '
            'caption alone is the footnote a reader skips',
      );

      // And the broken rule under it: the same vocabulary `ValueHole` uses for
      // absence, painted rather than merely built.
      final rule = find.descendant(
        of: find.byType(BioWithheldFigure),
        matching: find.byType(CustomPaint),
      );
      expect(rule, findsWidgets);
      expect(
        tester.getRect(rule.first).width,
        greaterThan(BioWithheldFigure.dash),
      );

      // A live hero's figure carries no such treatment — the difference is in
      // what is painted, not only in the caption beside it.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(todayHost(store, home: const BodyScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(BioWithheldFigure), findsNothing);
      expect(
        find.ancestor(
          of: find.text('34.3'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Opacity &&
                widget.opacity == BioWithheldFigure.staleOpacity,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('WITH NOTHING HELD, THE HERO DRAWS ITS EMPTY STATE', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byKey(BioWithheldFigure.holeKey), findsOneWidget);
      expect(find.byKey(BioWithheldFigure.staleFigureKey), findsNothing);
      expect(find.byKey(BioWithheldFigure.dateKey), findsNothing);
      expect(
        find.byType(TodayBioHeroWithheld),
        findsOneWidget,
        reason: 'never invent a value, and never lose the hero either',
      );
    });
  });

  group('the full explanation is behind the ⓘ', () {
    testWidgets('THE CONSEQUENCE, THE REMEDY AND THE EXCLUSION ARE ALL THERE', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(BioHero),
          matching: find.byType(MetricInfoDot),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('silently assert you sit'), findsOneWidget);
      expect(
        find.textContaining('Log a weight and it returns.'),
        findsOneWidget,
      );
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('70,000 people')), findsOneWidget);
    });
  });
}

/// The card's ground and corner, as they were actually built.
Decoration _ground(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(BioHero), matching: find.byType(Container))
        .first,
  );
  return container.decoration!;
}

/// The composite block, as the envelope hands it to the hero.
const Disclosure _withheldProbe = Disclosure(
  reason: 'required_terms_absent',
  message: kConsequence,
  terms: <Disclosure>[
    Disclosure(
      reason: 'logged_weight_stale',
      message: kTermRemedy,
      term: 'fitness',
    ),
  ],
);
