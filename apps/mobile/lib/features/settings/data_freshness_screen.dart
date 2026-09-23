/// Data freshness — `H.screens.sync`: strap → phone → server, and what is stale.
///
/// ```js
/// H.screens.sync = () => `${H.header('Your data, connected.','Strap → phone → insights',true)}
///   <div class="sync-stages">…</div>
///   ${H.notice(…)}
///   <div class="card"><div class="row between"><h3>Data freshness</h3>${badge}</div>
///     ${six observation rows}</div>
///   <div class="section">${H.button('Try a sample sync','sync','full','sync')}</div>
///   <div class="card flush section">${H.row('cloud','Background preferences',…)}</div>
///   ${H.footer()}`;
/// ```
///
/// ## The banner is the app's ONE connection classification, not a second one
///
/// `data/sync/connection_health.dart` is the only thing in this app that decides
/// whether the link is healthy. Today calls it once and gives the answer to
/// three readers — the ring, the device strip and the data-health card — because
/// *"none of them may decide quiet for itself"*. This screen is a fourth reader
/// of the same call, with the same inputs, and it renders the first alert the
/// classifier raised. It does not compare timestamps of its own.
///
/// No alerts is the only state that gets the untinted "everything is current"
/// banner, and it is `alerts.isEmpty` — the union of the link's faults and the
/// data's — exactly as `today_header.dart` reads it for its green dot.
///
/// ## Every row states its own instrument's age, or says there is none
///
/// The prototype prints `${item.age_h} hours since last sample` for six sample
/// rows. Here the rows are `DeviceDay.metrics`, the real streams, and each one
/// prints the age of its own `measuredAt`. **A stream with no reading prints its
/// withhold's reason**, not a zero and not a dash: `device_metric.dart` keeps
/// that reason precisely so a stream the sensor did not sample can say so.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/device/device_metric.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/push/push_stamp_provider.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/features/settings/widgets/history_mirror_card.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/emblems.dart';
import 'package:healthee/shared/v02/list_row.dart';
import 'package:healthee/shared/v02/notices.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// Which streams are current, from the strap to the server.
class DataFreshnessScreen extends ConsumerWidget {
  /// [now] is injected by tests so every age label is deterministic.
  const DataFreshnessScreen({this.now, super.key});

  /// The prototype's own h1.
  static const String title = 'Data & sync';

  /// Its eyebrow.
  static const String eyebrow = 'Strap → phone → insights';

  /// The heading over the stream list.
  static const String listTitle = 'Data freshness';

  /// The instant every age is measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final at = now ?? DateTime.now();
    final day = ref.watch(deviceDayProvider).value;
    final link = ref.watch(syncControllerProvider);
    final health = connectionHealth(
      link: link,
      now: at,
      push: ref.watch(pushStampProvider).value,
      // Null while the keystore read is in flight — "not yet known", which the
      // classifier stays silent about rather than guessing "signed out".
      signedIn: ref.watch(serverSessionProvider).value?.signedIn,
      lastStrapSync: day?.sync.lastCompleteSync,
    );
    final alert = health.alerts.isEmpty ? null : health.alerts.first;
    return SettingsPage(
      title: title,
      eyebrow: eyebrow,
      children: <Widget>[
        const SyncStages(<(IconData, String)>[
          (SolarIconsOutline.watchRound, 'Helio Strap'),
          (SolarIconsOutline.smartphone, 'On your phone'),
          (SolarIconsOutline.cloud, 'Your server'),
        ]),
        HNotice(
          title: alert?.headline ?? 'Everything here is current',
          body: alert?.detail ??
              'Your strap, this phone and your server all agree about what has '
                  'been read.',
          kind: alert == null ? NoticeKind.plain : NoticeKind.error,
        ),
        const SectionGap(),
        PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      listTitle,
                      style: FormType.heading3.copyWith(color: colors.ink),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  if (day?.date case final String date) HBadge(date),
                ],
              ),
              for (final DeviceMetric metric in day?.metrics ?? const [])
                _Observation(metric: metric, now: at),
            ],
          ),
        ),
        const SectionGap(),
        HButton(
          label: 'Sync now',
          icon: SolarIconsOutline.refresh,
          onPressed: link.isBusy
              ? null
              : () => unawaited(
                  ref.read(syncControllerProvider.notifier).syncNow(),
                ),
        ),
        const SectionGap(),
        HistoryMirrorCard(now: now),
        const SectionGap(),
        FlushCard(
          children: <Widget>[
            ListRow(
              icon: SolarIconsOutline.cloud,
              title: 'Background preferences',
              subtitle: 'How and when collection runs',
              onTap: () => unawaited(context.push(Routes.background)),
            ),
          ],
        ),
        const DataFooter(),
      ],
    );
  }
}

/// `.observation` — one stream, its age, and whether it has a reading.
///
/// ```css
/// .observation    { padding-block:20px; border-bottom:1px solid var(--line); }
/// .observation h3 { margin-block:10px 6px; font-size:17px; line-height:1.5; }
/// .observation p  { font-size:12px; line-height:1.9; }
/// ```
class _Observation extends StatelessWidget {
  const _Observation({required this.metric, required this.now});

  static const double padding = 20;
  static const double titleGap = 6;

  final DeviceMetric metric;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final measured = metric.measuredAt;
    // A withheld stream says WHY, in the reason the reading carries. A dash
    // here would be the app inventing an absence it was given an account of.
    final (String detail, HBadge stamp) = switch (metric.reading) {
      Present<double>() when measured != null => (
        'Last sample ${ageLabel(measured, now: now)} · '
            '${metric.sampleCount} today',
        const HBadge('Available', kind: BadgeKind.good),
      ),
      Present<double>() => (
        '${metric.sampleCount} samples today',
        const HBadge('Available', kind: BadgeKind.good),
      ),
      // `.message`, never `.reason`: `disclosure.dart` says plainly that the
      // reason is an operator's filter key and the message is what the owner
      // reads. Printing the key would be a stream explaining itself in ours.
      Withheld<double>(:final disclosure) => (
        disclosure.message,
        const HBadge('No reading', kind: BadgeKind.warm),
      ),
      _ => (
        'Nothing read from this stream today.',
        const HBadge('No reading', kind: BadgeKind.warm),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: padding),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.line, width: hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  metric.stream.label,
                  style: FormType.observationTitle.copyWith(color: colors.ink),
                ),
                const SizedBox(height: titleGap),
                Text(
                  detail,
                  style: FormType.observationBody.copyWith(color: colors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          stamp,
        ],
      ),
    );
  }
}
