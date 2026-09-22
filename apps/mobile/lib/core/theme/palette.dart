/// One of the **two** files in this app allowed to contain a colour literal. The
/// other is `sleep_stage_palette.dart`. `test/core/colour_literal_gate_test.dart`
/// reads `lib/` and fails on a third.
///
/// ## Which design this is — v02, from 2026-09-06
///
/// **The owner's HTML prototype in `design/mobile-preview/` is now the
/// specification**, superseding the legacy-verbatim port. Every value below is
/// the sRGB form of an OKLCH token in `tokens.css` + `richer.css`, with
/// `richer.css` winning where both define a name (it is loaded last).
///
/// The v02 system has two halves and this file keeps them apart:
///
///   * **Scaffolding and judgement** — [LightPalette] / [DarkPalette]: page,
///     surface, ink, hairline, the one accent, and the three verdict pairs.
///   * **Category families** — [LightFamilies] / [DarkFamilies]: the six hues
///     v02 assigns meaning to, each with its soft fill. A card declares one as
///     its *tone* and everything inside resolves it (`tone.dart`).
///
/// ## What was DELETED, so nobody reinstates it
///
/// `LegacyLightHues` / `LegacyDarkHues` — legacy's ten per-metric hues. v02 has
/// six families, so the ten collapse: `hrv` and `readiness` became [fitness],
/// `steps` and `calories` became [movement], `respiratory` and `spo2` became
/// [oxygen], `rem` became [sleep]. `metric_hue.dart` records which metric lands
/// where. The collapse is v02's, not an accident of porting: the prototype's
/// `CHART_COVERAGE.md` names exactly six categories.
///
/// **Legacy's deliberate identity/verdict collision is gone with them.** Legacy
/// made green both "HRV" and "improving", and red-orange both "heart" and
/// "degrading". v02 separates them: [LightPalette.fav] is `--positive` and is
/// **not** [LightFamilies.fitness], and [LightPalette.alert] is `--danger` and is
/// not [LightFamilies.heart]. That separation is asserted in
/// `test/theme/v02_tokens_test.dart` so it cannot quietly collapse back.
///
/// ## Where v02 has one token and the app had two
///
/// v02 draws every hairline — card edge, list rule, table row — with one
/// `--line`, and keeps `--rule` for the louder marks (a sheet handle, a
/// separator). So [LightPalette.line2] resolves to the same value as
/// [LightPalette.line] **by transcription, not by oversight**, and [rule] is a
/// new role. `grid` and `reference` stay derived exactly as before —
/// `test/theme/chart_ink_test.dart` requires the grid to be `line` quieted and
/// the reference to be `ink3` quieted, and that relation is what makes a chart's
/// structure recede rather than a value someone picked.
library;

import 'package:flutter/material.dart';

/// **v02's six category families, light.** `richer.css` `:root`.
///
/// The semantics are the prototype's `CHART_COVERAGE.md`: green is
/// recovery/fitness, violet is sleep, coral is heart/load, amber is
/// movement/energy, blue is breathing/oxygen, warm is stress. `tone.dart` is the
/// only thing that should read these by name.
abstract final class LightFamilies {
  /// `--fitness` — recovery, HRV, VO₂max, readiness. Also the app's accent.
  static const Color fitness = Color(0xFF00612F);

  /// `--fitness-soft` — the fill behind fitness content.
  static const Color fitnessSoft = Color(0xFFD9F3DF);

  /// `--sleep` — sleep, sleep debt, every stage plot's frame.
  static const Color sleep = Color(0xFF6B35B5);

  /// `--sleep-soft`.
  static const Color sleepSoft = Color(0xFFF0EBFE);

  /// `--heart` — heart rate, resting HR, cardio load.
  static const Color heart = Color(0xFFA51D2B);

  /// `--heart-soft`.
  static const Color heartSoft = Color(0xFFFFE7E5);

  /// `--movement` — steps, distance, calories, energy.
  static const Color movement = Color(0xFF774000);

  /// `--movement-soft`.
  static const Color movementSoft = Color(0xFFFFEAD3);

  /// `--oxygen` — respiratory rate, SpO₂.
  static const Color oxygen = Color(0xFF005A8D);

  /// `--oxygen-soft`.
  static const Color oxygenSoft = Color(0xFFDFF2FD);

  /// `--stress` — stress, skin temperature.
  static const Color stress = Color(0xFF874400);

  /// `--stress-soft`.
  static const Color stressSoft = Color(0xFFFFE9D6);
}

/// **v02's six category families, dark.** `richer.css` `[data-theme='dark']`.
/// Authored by the prototype, not derived from light. See [LightFamilies].
abstract final class DarkFamilies {
  /// `--fitness`.
  static const Color fitness = Color(0xFF6ADD92);

  /// `--fitness-soft`.
  static const Color fitnessSoft = Color(0xFF172F1F);

  /// `--sleep`.
  static const Color sleep = Color(0xFFC5A8FF);

  /// `--sleep-soft`.
  static const Color sleepSoft = Color(0xFF2B2539);

  /// `--heart`.
  static const Color heart = Color(0xFFFF9390);

  /// `--heart-soft`.
  static const Color heartSoft = Color(0xFF3A2120);

  /// `--movement`.
  static const Color movement = Color(0xFFFABA59);

  /// `--movement-soft`.
  static const Color movementSoft = Color(0xFF372813);

  /// `--oxygen`.
  static const Color oxygen = Color(0xFF6EC6F7);

  /// `--oxygen-soft`.
  static const Color oxygenSoft = Color(0xFF172C38);

  /// `--stress`.
  static const Color stress = Color(0xFFFCAD6A);

  /// `--stress-soft`.
  static const Color stressSoft = Color(0xFF362416);
}

/// The v02 scaffolding, light.
abstract final class LightPalette {
  /// `--canvas` — the ground the app shell sits on, behind [bg].
  static const Color canvas = Color(0xFFE7EDE9);

  /// `--background` — the page, behind every surface.
  static const Color bg = Color(0xFFF3F6F4);

  /// `--surface` — panels, cards and sheets.
  static const Color surface = Color(0xFFFFFFFF);

  /// `--surface-soft` — a recessed block inside a card, a track, a skeleton.
  static const Color surface2 = Color(0xFFF0F1F7);

  /// App frame — top bar and tab bar. v02 draws the bottom nav on `--surface`.
  static const Color chrome = surface;

  /// `--ink` — primary text and hero figures.
  static const Color ink = Color(0xFF171C19);

  /// `--muted` — secondary text, the sentence under a number.
  static const Color ink2 = Color(0xFF4C554F);

  /// `--subtle` — labels, units, captions.
  static const Color ink3 = Color(0xFF5E6560);

  /// `--line` — every hairline v02 draws: card edge, list rule, table row.
  static const Color line = Color(0xFFD6DDD8);

  /// v02 has ONE hairline; see the library docstring. Same value as [line].
  static const Color line2 = line;

  /// `--rule` — the louder mark: a sheet handle, a separator, a secondary
  /// button's edge. New in v02.
  static const Color rule = Color(0xFFB0BAB3);

  /// A rule drawn INSIDE a plot. [line]'s RGB at half alpha, never derived at a
  /// call site — the three painters that each derived their own got it wrong.
  static const Color grid = Color.fromRGBO(214, 221, 216, 0.5);

  /// The horizontal line a series is READ AGAINST. [ink3] at 55%.
  static const Color reference = Color.fromRGBO(94, 101, 96, 0.55);

  /// `--accent`, which v02 defines as `var(--fitness)`.
  static const Color accent = LightFamilies.fitness;

  /// `--accent-hover` — the accent under pressure.
  static const Color accent2 = Color(0xFF004F23);

  /// `--accent-soft`, which v02 defines as `var(--fitness-soft)`.
  static const Color accentSoft = LightFamilies.fitnessSoft;

  /// `--on-accent` — text and icons sitting ON [accent]. 7.5:1 here.
  static const Color onAccent = Color(0xFFFBFBFE);

  /// **Judgement — favourable.** `--positive`. Distinct from [accent] in v02.
  static const Color fav = Color(0xFF065F3D);

  /// `--positive-soft`.
  static const Color favSoft = Color(0xFFDDF1E5);

  /// **Judgement — the middle band.** `--caution`.
  static const Color unf = Color(0xFF6F4A12);

  /// `--caution-soft`.
  static const Color unfSoft = Color(0xFFFFF0D8);

  /// **The illness flag, and nothing else.** `--danger`. Distinct from
  /// [LightFamilies.heart], which legacy shared it with.
  static const Color alert = Color(0xFFA52A24);

  /// `--danger-soft`.
  static const Color alertSoft = Color(0xFFFEE9E6);

  /// The number-shaped absence — [ink] at 4.5%. A refusal spends no hue, so v02
  /// has no token for it and the honesty layer keeps its own derivation.
  static const Color hole = Color.fromRGBO(23, 28, 25, 0.045);

  /// `--overlay` — the scrim behind a modal sheet.
  static const Color overlay = Color(0x5911131F);

  /// `--shadow-color` — the one shadow v02 casts, under a pressed segment.
  static const Color shadow = Color(0x121E1F34);

  /// `--bio-background` — the biological-age hero's own surface.
  static const Color bioBackground = Color(0xFFD5ECD9);

  /// `--bio-ink` — everything written on [bioBackground].
  static const Color bioInk = Color(0xFF0E2516);

  /// `--bio-glow` — the hero's halo.
  static const Color bioGlow = Color(0xFF5AC480);

  /// `--bio-line` — the hero's contour art and its divider.
  static const Color bioLine = Color(0xFF328B54);

  /// `--halo-warm` — the amber one particle in eleven is drawn in.
  ///
  /// `motion.css`: `oklch(88% .13 86)`. **The same value in both themes**,
  /// because the prototype declares it once, outside either theme block, on a
  /// halo surface that is dark in both. See [DarkPalette.haloWarm].
  static const Color haloWarm = Color(0xFFFED16B);

}

/// The v02 scaffolding, dark — **the default appearance for this direction**.
/// Authored by the prototype; never derived by inverting light.
abstract final class DarkPalette {
  /// `--canvas`.
  static const Color canvas = Color(0xFF050806);

  /// `--background`.
  static const Color bg = Color(0xFF0D100E);

  /// `--surface`.
  static const Color surface = Color(0xFF181C19);

  /// `--surface-soft`.
  static const Color surface2 = Color(0xFF212522);

  /// App frame. See [LightPalette.chrome].
  static const Color chrome = surface;

  /// `--ink`.
  static const Color ink = Color(0xFFF0F3F0);

  /// `--muted`.
  static const Color ink2 = Color(0xFFB2BAB4);

  /// `--subtle`.
  static const Color ink3 = Color(0xFF98A19B);

  /// `--line`.
  static const Color line = Color(0xFF2C322E);

  /// v02 has ONE hairline. Same value as [line].
  static const Color line2 = line;

  /// `--rule`.
  static const Color rule = Color(0xFF505752);

  /// [line]'s RGB at half alpha. See [LightPalette.grid].
  static const Color grid = Color.fromRGBO(44, 50, 46, 0.5);

  /// [ink3] at 55%. See [LightPalette.reference].
  static const Color reference = Color.fromRGBO(152, 161, 155, 0.55);

  /// `--accent` = `var(--fitness)`.
  static const Color accent = DarkFamilies.fitness;

  /// `--accent-hover`.
  static const Color accent2 = Color(0xFF9AEAB2);

  /// `--accent-soft` = `var(--fitness-soft)`.
  static const Color accentSoft = DarkFamilies.fitnessSoft;

  /// `--on-accent`. 12:1 on the dark green.
  static const Color onAccent = Color(0xFF08120C);

  /// `--positive`.
  static const Color fav = Color(0xFF78C89E);

  /// `--positive-soft`.
  static const Color favSoft = Color(0xFF13271C);

  /// `--caution`.
  static const Color unf = Color(0xFFE8BC78);

  /// `--caution-soft`.
  static const Color unfSoft = Color(0xFF2D220F);

  /// `--danger`.
  static const Color alert = Color(0xFFF69C90);

  /// `--danger-soft`.
  static const Color alertSoft = Color(0xFF351C19);

  /// The number-shaped absence — white at 5%.
  static const Color hole = Color.fromRGBO(255, 255, 255, 0.05);

  /// `--overlay`.
  static const Color overlay = Color(0xA6020208);

  /// `--shadow-color`.
  static const Color shadow = Color(0x33000001);

  /// `--bio-background`.
  static const Color bioBackground = Color(0xFF132419);

  /// `--bio-ink`.
  static const Color bioInk = Color(0xFFEEF8F0);

  /// `--bio-glow`.
  static const Color bioGlow = Color(0xFF2D8C53);

  /// `--bio-line`.
  static const Color bioLine = Color(0xFF57AE74);

  /// `--halo-warm` — **the same amber as [LightPalette.haloWarm]**, and that is
  /// the port rather than an oversight.
  ///
  /// The rest of this palette is authored per theme because it sits on a page
  /// whose ground flips. The halo does not: `motion.css` forces its own dark
  /// surface in both themes and declares `--halo-warm` once, beside
  /// `--halo-core` and `--halo-mist`. A second value here would be inventing a
  /// theme the prototype does not have.
  ///
  /// It is deliberately **not** [DarkFamilies.movement], the product's other
  /// amber: the halo glint is the prototype's decoration, and borrowing an
  /// identity hue would put "steps" inside the biological-age card.
  static const Color haloWarm = Color(0xFFFED16B);

}
