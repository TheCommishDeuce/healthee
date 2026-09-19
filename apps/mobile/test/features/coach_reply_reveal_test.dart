// A LIVE reply is revealed a piece at a time; one from history is shown whole.
// The sources dot arrives only with the last piece.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/features/coach/coach_conversation.dart';
import 'package:healthee/features/coach/widgets/coach_reveal.dart';
import 'package:healthee/features/coach/widgets/coach_thread.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';

const CoachAnswer _answer = CoachAnswer(
  reply: 'First point [sleep_need_debt]. Second point. Third point.',
  citations: <String>['sleep_need_debt'],
  gradeFloor: 'Probable',
  refused: false,
  validated: true,
);

Widget _app(CoachEntry entry, {VoidCallback? onGrow}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: ListView(
      children: <Widget>[CoachEntryView(entry: entry, onGrow: onGrow)],
    ),
  ),
);

String _visibleText(WidgetTester tester) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  return richTexts.map((r) => r.text.toPlainText()).join();
}

void main() {
  testWidgets('a live reply grows piece by piece and finishes complete', (
    tester,
  ) async {
    int grew = 0;
    await tester.pumpWidget(
      _app(const CoachReply(_answer, live: true), onGrow: () => grew++),
    );
    // Nothing yet: the first piece lands after the first interval.
    expect(_visibleText(tester), isNot(contains('Second point')));
    expect(find.byType(MetricInfoDot), findsNothing);

    final step = revealInterval(revealCuts(_answer.reply).length);
    await tester.pump(step);
    expect(_visibleText(tester), contains('First point'));
    expect(_visibleText(tester), isNot(contains('Second point')));
    expect(
      find.byType(MetricInfoDot),
      findsNothing,
      reason: 'not until complete',
    );

    await tester.pump(step);
    await tester.pump(step);
    expect(_visibleText(tester), contains('Third point.'));
    expect(find.byType(MetricInfoDot), findsOneWidget);
    expect(grew, 3, reason: 'one growth notice per revealed piece');
  });

  testWidgets('a reply from history is shown whole at once', (tester) async {
    await tester.pumpWidget(_app(const CoachReply(_answer)));
    expect(_visibleText(tester), contains('Third point.'));
    expect(find.byType(MetricInfoDot), findsOneWidget);
  });

  testWidgets('the fallback notice waits for the last piece too', (
    tester,
  ) async {
    const fallback = CoachAnswer(
      reply: 'One. Two.',
      citations: <String>[],
      gradeFloor: null,
      refused: false,
      validated: false,
    );
    await tester.pumpWidget(_app(const CoachReply(fallback, live: true)));
    await tester.pump(revealInterval(2));
    expect(find.textContaining('honest fallback'), findsNothing);
    await tester.pump(revealInterval(2));
    expect(find.textContaining('honest fallback'), findsOneWidget);
  });
}
