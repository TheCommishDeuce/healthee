/// The panels and entry cards Insights is built from.
///
/// `screens-overview.js::H.screens.insights`:
///
/// ```js
/// .relationship-grid          two cards: a personal pattern, and the age model
/// H.panel('Effort & stress, side by side','heart', dayTogether + note,'activity')
/// H.panel('A useful question comes next', …)   not built: the coach is removed
/// ```
///
/// ## The two entry cards carry no coefficient, and that is not an omission
///
/// The prototype prints `ρ −0.42` on its first card. This app moved exactly that
/// string off its surfaces on purpose: `findings_section.dart` records how
/// `Spearman(hrv_sleep_avg, recovery_score) = +0.72 over 105 days (p=0.000)`
/// reached the owner's home screen verbatim, and
/// `test/features/tab_screens_test.dart` now asserts that no rank coefficient is
/// on the surface at all. So the card names the two things and how much of the
/// owner's history is behind them; the arithmetic stays one tap behind the
/// finding's own disclosure, where it already lives.
///
/// ## Neither card's colour can depend on the sign
///
/// Both tones are **fixed** — sleep and fitness, the prototype's own — and are
/// not derived from the finding. A family chosen from the sign of a coefficient
/// would be a verdict painted on a correlation, which is the one thing this
/// screen exists not to do.
///
/// ## Both cards now have their action, because both destinations exist
///
/// The prototype's destinations are `#insight` and `#body`. Neither was built
/// when these cards were written, and `entry_card.dart`'s rule applied: *"An
/// entry point that leads nowhere is worse than an absent entry point: it spends
/// a tap to teach the reader that the screen lies about what it can do."* The
/// finding screen landed first and took its `Explore`; the age screen has landed
/// now and takes its `Understand`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/features/insights/v02/finding_detail_screen.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/entry_card.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's own line under the linked chart.
const String kLinkedNote =
    'Shared time axis. Independent scales. Check the context before '
    'interpreting a relationship.';

/// `H.bridge('stress', …)` — what a sensor cannot see.
const String kJournalBridge =
    'Sensors cannot tell what was happening around a busy hour.';

/// `Effort & stress, side by side` — two signals, one hour cursor, two scales.
class EffortStressPanel extends StatelessWidget {
  /// [heartRate] and [stress] are the payload's hourly series.
  const EffortStressPanel({
    required this.heartRate,
    required this.stress,
    required this.reveals,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Effort & stress, side by side';

  /// Today's heart rate, hour by hour.
  final List<HourPoint> heartRate;

  /// Today's stress, hour by hour.
  final List<HourPoint> stress;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Whether either signal has enough to draw.
  ///
  /// **Both or neither.** A "side by side" chart with one live pane is a
  /// different chart under a title promising a comparison the reader cannot
  /// make, and two hours is not a day.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RevealOnce(
            id: 'insights.effort-stress',
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
              // `shortClock`, and not the prototype's `06:00`: Today draws this
              // same chart from the same series, and one chart labelled two ways
              // on two screens is the drift `shared/format/` exists to stop.
              captions: hours < 2
                  ? const <String>[]
                  : <String>[
                      shortClock(heartRate.first.hour),
                      shortClock(heartRate[hours - 1].hour),
                    ],
              sampleLabels: <String>[
                for (var i = 0; i < hours; i++) shortClock(heartRate[i].hour),
              ],
              semanticLabel:
                  'Heart rate and stress through today, on a shared hour axis',
            ),
          ),
          const PanelNote(kLinkedNote),
        ],
      ),
    );
  }
}

/// The first relationship card: one pattern found in the owner's own history.
///
/// The wording is the same non-causal wording `findings_section.dart` uses — the
/// two metrics joined by a symmetric glyph, and the window under them. Nothing
/// here says "helps", "improves" or "because".
class FindingEntryCard extends StatelessWidget {
  /// Builds the card for [finding].
  const FindingEntryCard({required this.finding, super.key});

  /// The pattern this card names.
  final Finding finding;

  /// Whether [finding] has two named metrics to put on a card at all.
  static bool canDraw(Finding finding) =>
      finding.metricA != null && finding.metricB != null;

  @override
  Widget build(BuildContext context) {
    final samples = finding.nSamples;
    return EntryCard(
      // Fixed, and not derived from the coefficient. See the library docstring.
      tone: Tone.sleep,
      icon: SolarIconsOutline.chartSquare,
      title: _pair(finding),
      body: samples == null
          ? 'Found in your own history.'
          : 'Across $samples days of your own history',
      // `<span class="text-button">Explore ↗</span>` on the prototype's
      // relationship card. The card has carried this hook since it was built and
      // nothing passed it a destination, so the owner tapped it and nothing
      // happened. The finding travels in `extra` so the screen draws the same
      // numbers this card is showing, without a second fetch.
      actionLabel: 'Explore',
      onOpen: () => unawaited(
        context.push(
          '${Routes.insight}/${findingKey(finding)}',
          extra: finding,
        ),
      ),
    );
  }

  /// `Caffeine ↔ sleep` — the prototype's own separator, forced to render as
  /// text rather than as an emoji.
  ///
  /// U+2194 has **emoji presentation by default on Android**, so the bare
  /// character the prototype writes came out as a blue-boxed glyph in a line of
  /// prose. `\u{FE0E}` is VARIATION SELECTOR-15, which requests the text form;
  /// the character itself is unchanged, so this is the design's arrow rendered
  /// the way the design renders it, not a substitute for it.
  ///
  /// The arrow is also the right symbol on its merits: a correlation has no
  /// direction, and every single-headed alternative would claim one.
  static String _pair(Finding finding) {
    final a = metricName(finding.metricA!);
    final b = metricName(finding.metricB!);
    return '${a[0].toUpperCase()}${a.substring(1)} $kPairArrow $b';
  }
}

/// The second relationship card: the fitness term of the age model.
class AgeEntryCard extends StatelessWidget {
  /// Builds the card for [years], the fitness contribution in years.
  const AgeEntryCard({required this.years, super.key});

  /// The contribution, signed as the server sent it.
  final double years;

  @override
  Widget build(BuildContext context) => EntryCard(
    tone: Tone.fitness,
    icon: SolarIconsOutline.heartPulse,
    title: 'Fitness → age',
    body: '${_signed(years)} years\nModel contribution',
    // `<span class="text-button">Understand ↗</span>` on the prototype's second
    // relationship card, pointed at `#body`. It carried no action while that
    // screen did not exist; it does now.
    actionLabel: 'Understand',
    onOpen: () => unawaited(context.push(Routes.body)),
  );

  /// The fitness term of the age model, or null when the payload has none.
  static double? contribution(BiologicalAge? age) {
    for (final term in age?.contributions ?? const <AgeContribution>[]) {
      if (term.term == 'fitness' && term.deltaYears != null) {
        return term.deltaYears;
      }
    }
    return null;
  }

  static String _signed(double years) => years < 0
      ? '−${(-years).toStringAsFixed(1)}'
      : '+${years.toStringAsFixed(1)}';
}
