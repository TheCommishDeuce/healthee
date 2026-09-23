import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/instrument/h_icon_badge.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:solar_icons/solar_icons.dart';

import '_v02_harness.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('HTap with no action is a pass-through', (tester) async {
    await tester.pumpWidget(_host(const HTap(child: Text('quiet'))));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(HTap),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('HTap scales under the finger and restores after release', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(HTap(onTap: () => taps++, child: const Text('press'))),
    );
    await tester.pumpAndSettle();
    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale(), 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('press')),
    );
    await tester.pump();
    expect(scale(), 0.975);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scale(), 1);
    expect(taps, 1);
  });

  testWidgets('the badge retains its size and semantic family colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        HIconBadge(
          SolarIconsOutline.moonSleep,
          color: const InstrumentHues.light().sleep,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(HIconBadge)), const Size(40, 40));
    final box = tester.widget<Container>(find.byType(Container));
    expect(groundOf(box.decoration!)!.a, closeTo(0.18, 0.005));
    expect(tester.widget<Icon>(find.byType(Icon)).size, 20);
  });

  testWidgets('the avatar keeps readable contrast and geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const HAvatar('A')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(HAvatar)), const Size(38, 38));
    final style = tester.widget<Text>(find.text('A')).style!;
    expect(style.fontSize, closeTo(38 * 0.42, 1e-9));
    expect(style.color, const HealtheeColors.light().onAccent);
  });
}
