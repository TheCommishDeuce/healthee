/// The fitness term of the age model, as an entry card into the age screen.
///
/// Moved out of `features/insights/v02/pattern_panels.dart` when Activity took
/// it too (F3): two features drawing one card is shared code, and features do
/// not import each other (`docs/ENGINEERING_STANDARDS.md`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/shared/v02/entry_card.dart';
import 'package:solar_icons/solar_icons.dart';

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
