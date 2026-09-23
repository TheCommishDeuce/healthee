/// Today is a morning overview: sleep, overnight recovery, then weight entry.
/// Connection failures and safety notices remain above the readings they qualify.
library;

import 'package:flutter/material.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/push/push_stamp.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/features/today/v02/recovery_panel.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/features/today/widgets/data_health_section.dart';
import 'package:healthee/features/today/widgets/illness_banner.dart';
import 'package:healthee/features/today/widgets/sleep_summary.dart';
import 'package:healthee/features/today/widgets/weight_entry.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

@immutable
class TodayExtras {
  const TodayExtras({
    this.push,
    this.signedIn,
    this.health,
    this.batteryPercent,
    this.navigation,
    this.onSignIn,
    this.onOpenProfile,
    this.onOpenRecovery,
    this.onOpenSleep,
  });

  final PushStamp? push;
  final bool? signedIn;
  final ConnectionHealth? health;
  final int? batteryPercent;
  final DateNavigation? navigation;
  final VoidCallback? onSignIn;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenRecovery;
  final VoidCallback? onOpenSleep;
}

List<PageSection> todaySections(ScreenData data, TodayExtras extras) {
  final snapshot = data.snapshot;
  final sections = SectionList();
  _head(sections, data, extras);
  sections.add(
    SleepSummary(
      server: snapshot?.lastSleep,
      local: data.day.lastNight,
      onOpen: extras.onOpenSleep,
    ),
  );
  sections.gap(PageSpacing.panel);
  if (snapshot != null) {
    sections.add(
      ReadingView<RecoveryScore>(
        reading: snapshot.recovery,
        label: 'Recovery',
        caveatCarrier: CaveatCarrier.insideCard,
        withheldBuilder: (context, disclosure) =>
            WithheldPanel(disclosure: disclosure, label: 'Recovery'),
        builder: (context, score) => RecoveryPanel.overview(
          score: score,
          date: snapshot.date,
          onDetails: extras.onOpenRecovery,
        ),
      ),
    );
    sections.gap(PageSpacing.panel);
  }
  sections.add(
    WeightEntry(signedIn: extras.signedIn, onSignIn: extras.onSignIn),
  );
  return sections.build();
}

void _head(SectionList sections, ScreenData data, TodayExtras extras) {
  final snapshot = data.snapshot;
  sections.add(
    TodayHeader(
      date: extras.navigation == null
          ? (snapshot?.date ?? data.day.date)
          : data.day.date,
      now: data.now ?? DateTime.now(),
      health: extras.health,
      navigation: extras.navigation,
      batteryPercent: extras.batteryPercent ?? data.day.batteryPercent,
      onOpenProfile: extras.onOpenProfile,
    ),
  );
  if (!data.view.isPast) sections.add(_dataHealth(data, extras));
  if (snapshot?.illnessFlag case final flag?) {
    sections.add(IllnessBanner(flag: flag, viewedDay: snapshot?.asOf?.day));
    sections.gap(PageSpacing.block);
  }
  if (data.day.hasNothing && snapshot == null) {
    sections.add(
      const EmptyState(
        message: 'Nothing from your strap yet',
        hint: 'Pull down with your strap nearby to collect its measurements.',
      ),
    );
  }
  if (data.serverFailure case final PageSection failure) {
    sections.addSection(failure);
    sections.gap(PageSpacing.panel);
  }
  if (data.serverPending case final PageSection pending) {
    sections.addSection(pending);
    sections.gap(PageSpacing.panel);
  }
}

Widget _dataHealth(ScreenData data, TodayExtras extras) {
  final view = data.server.value;
  return DataHealthSection(
    health: data.snapshot?.dataHealth,
    connection: extras.health,
    push: extras.push,
    cachedAt: view != null && view.fromCache ? view.fetchedAt : null,
    cachedDate: view != null && view.describesAnotherDay(data.day.date)
        ? data.snapshot?.date
        : null,
    lastStrapSync: data.day.sync.lastCompleteSync,
    now: data.now,
    signedIn: extras.signedIn,
    onSignIn: extras.onSignIn,
    bottomGap: 16,
  );
}
