/// F2, from the owner's phone: every row of "Your body overnight" opened HRV.
///
/// The rows reported the SLEEP payload's own keys (`rhr`, `spo2_avg`,
/// `respiratory_rate`, `skin_temp_c`), the history screen knows canonical ids
/// only, and it falls back to its first metric — HRV — for anything else. So one
/// row in five went where it said and four went to HRV without a word.
///
/// Two claims: a row opens the history of the measurement it names, and a row
/// with no history of its own (skin temperature has none) is not a link at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/features/sleep/v02/vitals_panel.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/vitals_table.dart';
import 'package:solar_icons/solar_icons.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

void main() {
  testWidgets('EACH OVERNIGHT ROW OPENS THE METRIC IT NAMES', (tester) async {
    final windows = SleepWindows(sleepPageFixture(), kSleepNow);
    final opened = <String>[];
    await tester.pumpWidget(
      sleepPanelHost(
        OvernightPanel(
          night: windows.latest,
          recent: windows.recent,
          reveals: RevealRegistry(),
          onOpenMetric: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    const expected = <String, String?>{
      'Resting heart': 'rhr_daily',
      'HRV': 'hrv_sleep_avg',
      'Blood oxygen': 'spo2_overnight',
      'Breathing': 'respiratory_rate_sleep',
      // No history series exists for skin temperature, so no link.
      'Skin temperature': null,
    };
    for (final MapEntry(key: label, value: metric) in expected.entries) {
      opened.clear();
      await tester.tap(find.text(label));
      await tester.pump();
      expect(
        opened,
        metric == null ? isEmpty : <String>[metric],
        reason: label,
      );
    }
  });

  testWidgets('a row whose metric has no history is not a link', (
    tester,
  ) async {
    final opened = <String>[];
    Vital vital(String label, String metric) => Vital(
      label: label,
      tone: Tone.heart,
      icon: SolarIconsOutline.heart,
      unit: '',
      reading: const Present<double>(1),
      series: const <double?>[1, 2],
      metric: metric,
    );
    await tester.pumpWidget(
      sleepPanelHost(
        VitalsTable(
          vitals: <Vital>[
            vital('Known', HistoryMetric.restingHr.id),
            vital('Unknown', 'skin_temp_c'),
          ],
          reveals: RevealRegistry(),
          revealPrefix: 'test',
          onOpenMetric: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unknown'));
    await tester.tap(find.text('Known'));
    await tester.pump();
    expect(opened, <String>['rhr_daily']);
  });
}
