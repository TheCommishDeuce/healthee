import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/shared/sheets/app_sheet.dart';
import 'package:healthee/shared/sheets/weight_log_sheet.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';

/// Weight entry without a general journal dashboard. Loading begins only on tap.
class WeightEntry extends StatelessWidget {
  const WeightEntry({this.signedIn, this.onSignIn, super.key});

  final bool? signedIn;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => Panel(
    head: const PanelHead(title: 'Weight', icon: Icons.monitor_weight_outlined),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionButton(
          full: true,
          label: 'Log weight',
          onPressed: signedIn == false
              ? onSignIn
              : () => unawaited(
                  showAppSheet<void>(
                    context: context,
                    builder: (context) => const _WeightSheet(),
                  ),
                ),
        ),
        PanelNote(
          signedIn == false
              ? 'Sign in to your server to log weight.'
              : 'Saved to your server. A connection is required.',
        ),
      ],
    ),
  );
}

/// Watch for the sheet's lifetime: a one-off read can dispose during a retry.
/// ProviderLogger reports initialization failures through the app's logging path.
class _WeightSheet extends ConsumerWidget {
  const _WeightSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncView<JournalRepository>(
        value: currentAccountValue(ref.watch(journalRepositoryProvider)),
        loadingLabel: 'Opening weight entry',
        errorMessage: 'Could not open weight entry',
        onRetry: () => ref.invalidate(journalRepositoryProvider),
        builder: (context, repository) => WeightLogSheet(
          key: ObjectKey(repository),
          repository: repository,
        ),
      );
}
