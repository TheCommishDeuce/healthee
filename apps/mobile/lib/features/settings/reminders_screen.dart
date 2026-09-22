/// Reminders — `H.screens.reminders`, on the real preference record.
///
/// ```js
/// H.screens.reminders = () => `${H.header('A nudge, when it helps.','Reminders',true)}
///   <p class="small">Choose what is useful. Your day doesn’t need more noise.</p>
///   <div class="card flush section">${three toggles}</div>
///   <div class="card section">${two time fields}<p class="small">…</p></div>
///   <p class="form-note">…</p>
///   ${H.footer()}`;
/// ```
///
/// ## The prototype's toggles are instant; ours are saved
///
/// `H.actions.toggle` flips an in-page object and shows a toast. A real reminder
/// is a row on the server plus a scheduled local notification, and
/// `notification_providers.dart` writes both in one call — so a tap that fired
/// a write per switch would be four writes for one decision, each able to fail
/// on its own. The switches move local state; the button commits it, and says
/// plainly when the server refused. That is the same contract every other write
/// in this app has (`shared/server_action_button.dart`).
///
/// The prototype's daily-focus and challenge-reflection toggles are gone with
/// the Actions tab (DESIGN_DECISIONS P5); wind-down maps onto `bedtime`.
///
/// The preferences are **scoped to the signed-in account**. A record whose scope
/// is not this session's is not this owner's, and is replaced by the empty
/// default rather than shown — the same guard the screen this replaces had.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/notifications/notification_providers.dart';
import 'package:healthee/data/notifications/reminder_preferences.dart';
import 'package:healthee/features/settings/widgets/time_field.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/server_action_button.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:healthee/shared/v02/toggle_row.dart';

/// The optional wind-down nudge and the time it arrives at.
class RemindersScreen extends ConsumerWidget {
  /// The reminders screen.
  const RemindersScreen({super.key});

  /// The prototype's own h1.
  static const String title = 'Reminders';

  /// Its eyebrow.
  static const String eyebrow = 'Reminders';

  /// The line under the header.
  static const String opening =
      'Choose what is useful. Your day doesn’t need more noise.';

  /// What this app can and cannot promise about delivery.
  static const String note =
      'Times use your device’s local timezone, and your phone decides exactly '
      'when a reminder arrives. Wind-down also adds one 45 minutes beforehand.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsPage(
      title: title,
      eyebrow: eyebrow,
      children: <Widget>[
        const SmallProse(opening),
        const SectionGap(),
        AccountAsyncView<AccountApi>(
          value: ref.watch(accountApiProvider),
          onRetry: () => ref.invalidate(accountApiProvider),
          builder: (context, api) => AccountAsyncView<ReminderPreferences>(
            value: ref.watch(reminderPreferencesProvider),
            onRetry: () => ref.invalidate(reminderPreferencesProvider),
            builder: (context, stored) => _Editor(
              key: ValueKey<String>('${api.sessionScope}:${stored.encode()}'),
              // A record belonging to a different session is not this owner's.
              value: stored.scope == api.sessionScope
                  ? stored
                  : const ReminderPreferences(),
              save: (next) async {
                await ref
                    .read(notificationServiceProvider)
                    .save(
                      ReminderPreferences(
                        scope: api.sessionScope,
                        bedtime: next.bedtime,
                        bedtimeMinute: next.bedtimeMinute,
                      ),
                      api,
                    );
                ref.invalidate(reminderPreferencesProvider);
              },
            ),
          ),
        ),
        const DataFooter(),
      ],
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.value, required this.save, super.key});

  final ReminderPreferences value;
  final Future<void> Function(ReminderPreferences) save;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late bool _bedtime = widget.value.bedtime;
  late int _bedtimeMinute = widget.value.bedtimeMinute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FlushCard(
          children: <Widget>[
            ToggleRow(
              title: 'Time to wind down',
              body: 'A little space between the day and sleep.',
              value: _bedtime,
              onChanged: (value) => setState(() => _bedtime = value),
            ),
          ],
        ),
        const SectionGap(),
        PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TimeField(
                label: 'Wind-down time',
                minuteOfDay: _bedtimeMinute,
                onChanged: (value) => setState(() => _bedtimeMinute = value),
              ),
              const SmallProse(RemindersScreen.note),
            ],
          ),
        ),
        const FormNote(
          'Nothing is scheduled until you save, and your phone asks for '
          'notification permission the first time one is.',
        ),
        ServerActionButton(
          label: 'Save reminders',
          style: ActionButtonStyle.v02,
          action: () async {
            await widget.save(
              ReminderPreferences(
                bedtime: _bedtime,
                bedtimeMinute: _bedtimeMinute,
              ),
            );
            return null;
          },
          onSaved: () {},
        ),
      ],
    );
  }
}
