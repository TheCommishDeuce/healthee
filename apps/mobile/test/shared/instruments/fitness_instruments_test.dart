/// **The VO₂max rail, measured.**
///
/// One claim here is an honesty claim rather than a layout one, and it is
/// mutation-tested: the shaded extent is **the supplied error magnitude, not a
/// confidence interval**, and the widget renders that sentence itself so no card
/// can show the band without it.
///
/// The rest is geometry: the extent is centred on the estimate, and the
/// reference line sits at the reference value.
///
/// > This file also covered `shared/v02/instruments/route_plot.dart` until that
/// > instrument was deleted. It was never reachable from `main.dart`, and the
/// > ground it drew — parks, a river and two roads at fixed fractions of the box
/// > — was fabricated geography. GPS/maps have since been removed entirely.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/shared/v02/instruments/vo2max_rail.dart';

import '../_chart_probe.dart';
import '_instrument_probe.dart';

Finder get _rail => find.byKey(Vo2maxRail.plotKey);

void main() {
  group('the VO₂max rail', () {
    testWidgets('the extent is centred on the estimate and says what it is', (
      tester,
    ) async {
      await tester.pumpWidget(
        instrumentHost(
          const Vo2maxRail(
            estimate: 43,
            medianForAge: 39.7,
            errorMagnitude: 2.95,
          ),
        ),
      );
      final painted = paintedAt(tester, _rail);
      final extents = rectsOf(painted);
      final dot = circlesOf(painted).single;

      expect(extents.length, 1);
      expect(extents.single.center.dx, closeTo(dot.at.dx, 0.5));
      // x = 5% + (v - 30) / 25 * 90% of 328: 45.95 - 40.05 spans 69.7 px.
      expect(extents.single.width, closeTo(69.7, 1));
      expect(dot.radius, 6);
      expect(dot.at.dx, closeTo(169.9, 1));

      final reference = linesOf(
        painted,
      ).where((line) => line.from.dx == line.to.dx).toList();
      expect(reference, isNotEmpty, reason: 'the median is drawn');
      for (final dash in reference) {
        expect(dash.from.dx, closeTo(130.9, 1));
      }
    });

    testWidgets('IT IS LABELLED AN ERROR MAGNITUDE, NOT A CONFIDENCE INTERVAL', (
      tester,
    ) async {
      await tester.pumpWidget(
        instrumentHost(
          const Vo2maxRail(
            estimate: 43,
            medianForAge: 39.7,
            errorMagnitude: 2.95,
          ),
        ),
      );
      expect(find.textContaining('error magnitude'), findsOneWidget);
      expect(find.textContaining('not a confidence interval'), findsOneWidget);
      expect(find.textContaining('±2.95'), findsOneWidget);

      final note = tester.getRect(find.textContaining('error magnitude'));
      expect(note.height, greaterThan(0), reason: 'and it is on screen');
      expect(
        note.top,
        greaterThanOrEqualTo(tester.getRect(_rail).bottom),
        reason: 'the sentence sits under the extent it qualifies',
      );
    });

    testWidgets('NO ERROR MAGNITUDE DRAWS NO EXTENT, and keeps the height', (
      tester,
    ) async {
      await tester.pumpWidget(
        instrumentHost(
          const Vo2maxRail(
            estimate: 43,
            medianForAge: 39.7,
            errorMagnitude: null,
          ),
        ),
      );
      expect(rectsOf(paintedAt(tester, _rail)), isEmpty);
      expect(circlesOf(paintedAt(tester, _rail)).length, 1);
      expect(tester.getSize(_rail).height, Vo2maxRail.railHeight);
      expect(find.textContaining('No error magnitude supplied'), findsOneWidget);
    });

    testWidgets('the window widens rather than clipping a high estimate', (
      tester,
    ) async {
      const rail = Vo2maxRail(
        estimate: 62,
        medianForAge: 39.7,
        errorMagnitude: 2.95,
      );
      expect(rail.window.high, greaterThanOrEqualTo(65));
      await tester.pumpWidget(instrumentHost(rail));
      final dot = circlesOf(paintedAt(tester, _rail)).single;
      expect(dot.at.dx, lessThan(tester.getSize(_rail).width));
      expect(dot.at.dx, greaterThan(0));
    });
  });
}
