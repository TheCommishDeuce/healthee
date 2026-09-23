/// What the Activity tab can DO — every destination and every read it needs.
///
/// Split out of `activity_sections.dart` when the VO₂max plan took that file
/// past the 400-line limit. The division is the honest one: this is the screen's
/// interface to the rest of the app, and the sections file is the layout. They
/// change for different reasons — a new destination touches this, a new panel
/// touches that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/device/device_workout.dart';
import 'package:healthee/data/models/fitness_plan.dart';

/// Everything Activity needs that is not on [ScreenData].
@immutable
class ActivityExtras {
  /// The five places this screen can go. Any of them null draws the control
  /// without its action rather than a control that leads nowhere.
  const ActivityExtras({
    this.onOpenProfile,
    this.plan,
    this.onOpenWorkouts,
    this.onOpenWorkout,
    this.onOpenMetric,
    this.onOpenRecovery,
    this.onOpenFitness,
  });

  /// Opens settings. The avatar's destination.
  final VoidCallback? onOpenProfile;

  /// `/api/activity.fitness_plan`, or null on a screen that has not read it.
  final AsyncValue<FitnessPlan?>? plan;

  /// Opens the recorded-workouts list.
  final VoidCallback? onOpenWorkouts;

  /// Opens one recorded session.
  final void Function(DeviceWorkout workout)? onOpenWorkout;

  /// Opens one metric's own history. The panels' `Details` action.
  final void Function(String metric)? onOpenMetric;

  /// Opens the recovery detail — the recovery entry card (F3).
  final VoidCallback? onOpenRecovery;

  /// Opens the fitness detail — the VO₂max panel's `Details`.
  final VoidCallback? onOpenFitness;
}
