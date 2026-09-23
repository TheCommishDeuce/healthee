/// "Full history on this phone" — the mirror's status and its one control.
///
/// `docs/MIRROR.md`. Says how much of the owner's server history is held here
/// and when it was last brought up to date, and downloads what changed. The
/// first run can take a while on years of history; later runs fetch only the
/// months whose digest moved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/mirror/mirror_sync.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/server_action_button.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';

/// The mirror card on the data & sync screen.
class HistoryMirrorCard extends ConsumerWidget {
  /// [now] is injected by tests.
  const HistoryMirrorCard({this.now, super.key});

  /// The instant "x ago" is measured against.
  final DateTime? now;

  /// The card's title.
  static const String title = 'Full history on this phone';

  /// What the held history is described as, from [stats].
  static String summary(MirrorStats stats, DateTime now) {
    if (stats.months == 0) {
      return 'None yet. Your server holds your full history; this phone keeps '
          'the last 60 days of strap readings on its own.';
    }
    final size = (stats.bytes / (1024 * 1024)).toStringAsFixed(1);
    final synced = stats.lastSynced == null
        ? ''
        : ' Updated ${ageLabel(stats.lastSynced!, now: now)}.';
    return '${stats.rows} records across ${stats.months} months '
        '($size MB).$synced';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final stats = ref.watch(mirrorStatsProvider).value;
    return PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: FormType.heading3.copyWith(color: colors.ink)),
          const SizedBox(height: SectionGap.height),
          SmallProse(
            stats == null
                ? 'Reading what is held…'
                : summary(stats, now ?? DateTime.now()),
          ),
          const SizedBox(height: SectionGap.height),
          ServerActionButton(
            label: 'Download full history',
            busyNote: 'Downloading the months that changed',
            style: ActionButtonStyle.v02,
            full: true,
            action: () async {
              final run = await ref
                  .read(mirrorSyncProvider)
                  .run(await ref.read(accountApiProvider.future));
              return '${run.fetched} months downloaded, ${run.unchanged} '
                  'already current'
                  '${run.removed == 0 ? '' : ', ${run.removed} removed'}.';
            },
            onSaved: () => ref.invalidate(mirrorStatsProvider),
          ),
        ],
      ),
    );
  }
}
