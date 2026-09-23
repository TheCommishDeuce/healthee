/// A look-at-it harness: renders the product screens to PNG, both themes.
///
/// **Not a test.** It asserts nothing and it is deliberately named without the
/// `_test` suffix so `flutter test` never picks it up. It is run by hand:
///
/// ```bash
/// flutter test test/render/render_screens.dart
/// ls build/renders/
/// ```
///
/// ## Why it exists
///
/// `feedback_look_at_the_design` in the owner's notes is blunt about it: grep
/// output is not a design, and an agent's *report* of visual work is not the
/// work. A screen has to be rendered and looked at, before and after, or a
/// layout that overflows on a phone ships green.
///
/// ## What is real in the output and what is not
///
/// The **fonts are the app's own** — [_loadBundledFonts] reads the TTFs out of
/// `assets/fonts/` and registers them with the test engine, so glyph widths,
/// overflow and the tabular-figure alignment are all genuine. Without that step
/// Flutter's test host substitutes a blocky fallback and every width measurement
/// is a lie. Colour, spacing and chart geometry are real either way.
///
/// The viewport is deliberately **taller than a phone** ([_renderSize]) so a
/// `ListView.builder` lays its whole list out in one pass and the PNG is the
/// entire scroll rather than the first screenful. The width is a real phone's.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/features/insights/insights_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';

import '../_sleep_stubs.dart';
import '../features/_today_host.dart';

/// A phone's width, and enough height that nothing is left unbuilt.
const Size _renderSize = Size(390, 3400);

/// Where the PNGs land. Ignored by git — this is a look, not an artefact.
const String _outputDirectory = 'build/renders';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadBundledFonts);

  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });

  tearDown(() => store.close());

  for (final theme in <String, ThemeData>{
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    testWidgets('render today — ${theme.key}', (tester) async {
      await _shoot(
        tester,
        'today-${theme.key}',
        todayHost(store, themeOverride: theme.value),
      );
    });

    testWidgets('render sleep — ${theme.key}', (tester) async {
      await _shoot(
        tester,
        'sleep-${theme.key}',
        todayHost(
          store,
          themeOverride: theme.value,
          // Pinned, so the night labels and the whole page eyebrow are the same
          // in every render rather than drifting with the wall clock.
          home: SleepScreen(now: kSleepNow),
        ),
      );
    });

    testWidgets('render activity — ${theme.key}', (tester) async {
      await _shoot(
        tester,
        'activity-${theme.key}',
        todayHost(store, themeOverride: theme.value, home: const ActivityScreen()),
      );
    });

    testWidgets('render insights — ${theme.key}', (tester) async {
      await _shoot(
        tester,
        'insights-${theme.key}',
        todayHost(store, themeOverride: theme.value, home: const InsightsScreen()),
      );
    });

    testWidgets('render diagnostics — ${theme.key}', (tester) async {
      await _shoot(
        tester,
        'diagnostics-${theme.key}',
        todayHost(store, themeOverride: theme.value, home: DiagnosticsScreen(now: now)),
      );
    });
  }
}

/// Pumps [app] at [_renderSize] and writes `<name>.png`.
Future<void> _shoot(WidgetTester tester, String name, Widget app) async {
  tester.view
    ..physicalSize = _renderSize
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RepaintBoundary(key: _boundary, child: app));
  // Charts animate on a real ticker, so settle rather than pump once — the
  // point of the render is what the owner ends up looking at.
  await tester.pumpAndSettle(const Duration(milliseconds: 50));

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  final ui.Image image = await boundary.toImage();
  final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) {
    fail('the render produced no bytes for $name');
  }
  final Directory directory = Directory(_outputDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('$_outputDirectory/$name.png').writeAsBytesSync(
    png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
  );
}

const Key _boundary = Key('render-boundary');

/// Registers `assets/fonts/` with the test engine so widths are the real ones.
Future<void> _loadBundledFonts() async {
  final Directory fonts = Directory('assets/fonts');
  final List<File> faces = fonts
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.ttf'))
      .toList();
  if (faces.isEmpty) {
    fail('no TTF in assets/fonts — the render would measure a fallback face');
  }
  // One family, every weight: the app declares a single family and selects a
  // weight, and `FontLoader` is the same shape.
  final String family = _familyOf(faces.first.uri.pathSegments.last);
  final FontLoader loader = FontLoader(family);
  for (final File face in faces) {
    loader.addFont(Future<ByteData>.value(face.readAsBytesSync().buffer.asByteData()));
  }
  await loader.load();
}

/// `Inter-SemiBold.ttf` → `Inter`. The family is the part before the dash.
String _familyOf(String fileName) => fileName.split('-').first;
