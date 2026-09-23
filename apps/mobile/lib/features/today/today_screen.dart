import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/push/push_stamp_provider.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/features/today/today_sections.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/instrument_screen.dart';

/// A short morning overview; the shared shell still owns collection and refresh.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({this.now, super.key});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final push = ref.watch(pushStampProvider).value;
    final signedIn = ref.watch(serverSessionProvider).value?.signedIn;
    final device = ref.watch(deviceDayProvider).value;
    final health = connectionHealth(
      link: ref.watch(syncControllerProvider),
      now: now ?? DateTime.now(),
      push: push,
      signedIn: signedIn,
      lastStrapSync: device?.sync.lastCompleteSync,
    );
    return InstrumentScreen(
      now: now,
      onRefreshed: () {
        ref.invalidate(pushStampProvider);
        ref.invalidate(sleepConsistencyProvider);
      },
      sections: (data) => todaySections(
        data,
        TodayExtras(
          push: push,
          signedIn: signedIn,
          health: health,
          batteryPercent: device?.batteryPercent,
          navigation: DateNavigation(
            earliest: earliestViewableDay(today),
            latest: today,
            onSelect: ref.read(viewDateProvider.notifier).select,
          ),
          onSignIn: () => unawaited(context.push(Routes.serverSignIn)),
          onOpenProfile: () => unawaited(context.push(Routes.settings)),
          onOpenRecovery: () => unawaited(context.push(Routes.recovery)),
          onOpenSleep: () => context.go(Routes.sleep),
          onOpenMetric: (metric) => openMetricHistory(context, metric),
        ),
      ),
    );
  }
}
