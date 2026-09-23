// Geometry checks for the retained Panel and PanelHead primitives.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';

import '_v02_harness.dart';

void main() {
  group('Panel', () {
    testWidgets('content is inset by padding plus the border', (tester) async {
      const bodyKey = Key('body');
      await pumpV02(
        tester,
        const Panel(child: SizedBox(key: bodyKey, height: 40)),
      );
      final panel = tester.getRect(find.byType(Panel));
      final body = tester.getRect(find.byKey(bodyKey));
      expect(panel.width, kContentWidth);
      expect(body.left - panel.left, 19);
      expect(panel.right - body.right, 19);
      expect(body.top - panel.top, 19);
      expect(panel.bottom - body.bottom, 19);
      expect(panel.height, 78);
    });

    testWidgets('surface, hairline and corner match the tokens', (
      tester,
    ) async {
      await pumpV02(tester, const Panel(child: SizedBox(height: 10)));
      final decoration = decorationOf(
        tester,
        find.descendant(
          of: find.byType(Panel),
          matching: find.byType(Container),
        ),
      );
      expect(groundOf(decoration), kColors.surface);
      expect(radiusOf(decoration), 22);
      expect(edgeOf(decoration)!.color, kColors.line);
      expect(edgeOf(decoration)!.width, 1);
    });

    testWidgets('head sits 12 pixels above the body', (tester) async {
      const headKey = Key('head');
      const bodyKey = Key('body');
      await pumpV02(
        tester,
        const Panel(
          head: SizedBox(key: headKey, height: 20),
          child: SizedBox(key: bodyKey, height: 30),
        ),
      );
      expect(
        tester.getRect(find.byKey(bodyKey)).top -
            tester.getRect(find.byKey(headKey)).bottom,
        12,
      );
    });

    testWidgets('tone reaches the head icon and action', (tester) async {
      await pumpV02(
        tester,
        const Panel(
          tone: Tone.sleep,
          head: PanelHead(
            title: 'Sleep',
            icon: Icons.bedtime,
            actionLabel: 'Details',
          ),
          child: SizedBox(height: 10),
        ),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.bedtime)).color,
        kHues.sleep,
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(
        button.style!.foregroundColor!.resolve(<WidgetState>{}),
        kHues.sleep,
      );
      expect(find.text('Details'), findsOneWidget);
    });
  });

  group('PanelHead', () {
    testWidgets('icon size and title gap are preserved', (tester) async {
      await pumpV02(
        tester,
        const PanelHead(title: 'Resting heart rate', icon: Icons.favorite),
      );
      final icon = tester.getRect(find.byIcon(Icons.favorite));
      final title = tester.getRect(find.text('Resting heart rate'));
      expect(icon.width, 17);
      expect(icon.height, 17);
      expect(title.left - icon.right, 8);
    });

    testWidgets('title is 13 pixels at weight 700', (tester) async {
      await pumpV02(tester, const PanelHead(title: 'Resting heart rate'));
      final style = tester.widget<Text>(find.text('Resting heart rate')).style!;
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, kColors.ink);
    });

    testWidgets('action has readable text and a minimum tap height', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const PanelHead(title: 'Steps', actionLabel: 'History'),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.style!.textStyle!.resolve(<WidgetState>{})!.fontSize, 11);
      expect(
        tester.getRect(find.byType(TextButton)).height,
        greaterThanOrEqualTo(28),
      );
    });
  });
}
