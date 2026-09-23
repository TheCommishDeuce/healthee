import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/ble/models/workout.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/workouts/workout_history_screen.dart';

import '../store/strap_store_test.dart' show resultWith;
import '_today_host.dart';
import '_workouts_host.dart';

Future<void> _seedWorkout(LocalStore store) => store.strapWriter.saveSync(
  resultWith(
    workouts: [
      Workout(
        start: DateTime(2026, 8, 4, 7),
        sportType: 1,
        durationSec: 1800,
        calories: 250,
        avgHr: 135,
        maxHr: 168,
        minHr: 90,
      ),
    ],
  ),
);

Set<String> _routePaths(List<RouteBase> routes) => {
  for (final route in routes) ...{
    if (route is GoRoute) route.path,
    ..._routePaths(route.routes),
  },
};

void main() {
  testWidgets('Activity retains workouts without GPS entry points', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 6000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = LocalStore.memory();
    addTearDown(store.close);
    await seedDevice(store);
    await _seedWorkout(store);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tapTab(tester, 'Activity');

    expect(find.text('The sessions behind it'), findsOneWidget);
    expect(find.text('Outdoor run'), findsWidgets);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Saved routes'), findsNothing);
    expect(find.text('Record an outdoor workout'), findsNothing);

    final router = GoRouter.of(tester.element(find.byType(ActivityScreen)));
    final paths = _routePaths(router.configuration.routes);
    expect(paths, containsAll(<String>['/workouts', '/workout']));
    for (final path in <String>['/gps', '/routes', '/route/:id']) {
      expect(paths, isNot(contains(path)));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('workout history remains readable without the GPS recorder', (
    tester,
  ) async {
    await tester.pumpWidget(workoutsHost(const WorkoutHistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Outdoor run'), findsOneWidget);
    expect(find.text('Record a workout'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('location permissions are limited to legacy Android BLE discovery', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final permission in <String>[
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
    ]) {
      final declaration = RegExp(
        '<uses-permission[^>]*android.permission.$permission"[^>]*/>',
      ).firstMatch(manifest)?.group(0);
      expect(declaration, isNotNull);
      expect(declaration, contains('android:maxSdkVersion="30"'));
    }
    expect(
      manifest,
      isNot(contains('android.permission.FOREGROUND_SERVICE_LOCATION')),
    );
    expect(manifest, contains('android.permission.BLUETOOTH_SCAN'));
    expect(
      manifest,
      contains('android:usesPermissionFlags="neverForLocation"'),
    );
    expect(manifest, contains('android.permission.BLUETOOTH_CONNECT'));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('geolocator:')),
    );
  });
}
