import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:solar_icons/solar_icons.dart';

/// The existing linked HR/stress chart, moved from Today to Activity.
/// The chart itself carries the warning that coincidence does not prove cause.
class HeartStressPanel extends StatelessWidget {
  const HeartStressPanel({
    required this.heartRate,
    required this.stress,
    required this.reveals,
    super.key,
  });

  static const String title = 'Heart rate & stress';
  final List<HourPoint> heartRate;
  final List<HourPoint> stress;
  final RevealRegistry reveals;

  /// Both panes need measurements before offering a comparison.
  static bool hasSomethingToDraw(
    List<HourPoint> heartRate,
    List<HourPoint> stress,
  ) => heartRate.length > 2 && stress.length > 2;

  @override
  Widget build(BuildContext context) {
    final hours = heartRate.length < stress.length
        ? heartRate.length
        : stress.length;
    return Panel(
      tone: Tone.heart,
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.heart,
        infoKey: 'stress',
      ),
      child: RevealOnce(
        id: 'activity.heart-stress',
        registry: reveals,
        builder: (context, t) => V02LinkedChart(
          <LinkedPane>[
            LinkedPane(
              tone: Tone.heart,
              label: 'Heart rate',
              unit: 'bpm',
              values: <double?>[
                for (var i = 0; i < hours; i++) heartRate[i].average,
              ],
            ),
            LinkedPane(
              tone: Tone.stress,
              label: 'Stress',
              values: <double?>[
                for (var i = 0; i < hours; i++) stress[i].average,
              ],
            ),
          ],
          progress: t,
          captions: hours < 2
              ? const <String>[]
              : <String>[
                  shortClock(heartRate.first.hour),
                  shortClock(heartRate[hours - 1].hour),
                ],
          sampleLabels: <String>[
            for (var i = 0; i < hours; i++) shortClock(heartRate[i].hour),
          ],
          semanticLabel: 'Heart rate and stress through the day, by hour',
        ),
      ),
    );
  }
}
