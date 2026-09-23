/// Recovery, as an entry card on Activity (F3).
///
/// It replaces a bridge sentence ("Recent training effort also belongs in your
/// recovery picture. View recovery") that the owner called "stupid text between
/// the cards" while calling the recovery screen itself "very cool". A card makes
/// the destination visible instead of burying its link at the end of prose.
///
/// The score is the server's own overnight estimate, the same reading Today
/// draws — shown when it was sent, never computed here, and absent when it was
/// withheld (the card then just names the destination).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/v02/entry_card.dart';
import 'package:solar_icons/solar_icons.dart';

/// Opens the recovery screen.
class RecoveryEntryCard extends StatelessWidget {
  /// [score] is the overnight estimate out of 100, or null when not sent.
  const RecoveryEntryCard({this.score, this.onOpen, super.key});

  /// The server's overnight recovery estimate, 0–100.
  final int? score;

  /// Opens `/recovery`. Null draws the card without its chevron.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => EntryCard(
    tone: Tone.recovery,
    icon: SolarIconsOutline.batteryCharge,
    title: 'Recovery',
    body: score == null
        ? 'Overnight estimate\nand what drives it'
        : '$score/100\nOvernight estimate',
    actionLabel: 'View recovery',
    onOpen: onOpen,
  );
}
