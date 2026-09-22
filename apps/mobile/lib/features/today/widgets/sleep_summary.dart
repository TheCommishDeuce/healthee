import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/device/device_night.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/last_sleep.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';
import 'package:solar_icons/solar_icons.dart';

/// A dated night, with local measurements available when the server has no answer.
class SleepSummary extends StatelessWidget {
  const SleepSummary({
    required this.local,
    this.server,
    this.onOpen,
    super.key,
  });

  final Reading<DeviceNight> local;
  final Reading<LastSleep>? server;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    // A server refusal is an answer; do not bypass it with the local copy.
    if (server case final Reading<LastSleep> reading) {
      return ReadingView<LastSleep>(
        reading: reading,
        label: 'Sleep',
        caveatCarrier: CaveatCarrier.insideCard,
        withheldBuilder: (context, disclosure) =>
            WithheldPanel(label: 'Sleep', disclosure: disclosure),
        builder: (context, night) => _panel(
          minutes: night.durationMin,
          // Preserve the server's calendar day when the phone is in another zone.
          end: DateTime.tryParse(night.endIso?.split('T').first ?? ''),
          source: 'Stored on your server',
        ),
      );
    }
    return ReadingView<DeviceNight>(
      reading: local,
      label: 'Sleep',
      caveatCarrier: CaveatCarrier.insideCard,
      withheldBuilder: (context, disclosure) =>
          WithheldPanel(label: 'Sleep', disclosure: disclosure),
      builder: (context, night) => _panel(
        minutes: night.asleepMin,
        end: night.end,
        source: 'From this phone · not a server assessment',
      ),
    );
  }

  Widget _panel({
    required int minutes,
    required DateTime? end,
    required String source,
  }) => Panel(
    tone: Tone.sleep,
    label: 'Sleep',
    onOpen: onOpen,
    head: const PanelHead(
      title: 'Sleep',
      icon: SolarIconsOutline.moonSleep,
      infoKey: 'sleep',
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelValue(hoursMinutes(minutes)),
        PanelNote(
          end == null
              ? 'Sleep date unavailable'
              : 'Night ending ${prettyDate(end.toLocal().toIso8601String())} · ${end.toLocal().year}',
        ),
        PanelNote(source),
      ],
    ),
  );
}
