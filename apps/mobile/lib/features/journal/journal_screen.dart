/// The journal — `screens-actions.js::H.screens.journal`, in Flutter.
///
/// ```text
///   header (detail)  "Journal"
///   small            a few moments of context make the measurements personal
///   journal-grid     ten kinds
///   section          Your moments → card flush of rows
///   footer
/// ```
///
/// ## The prototype's closing notice is NOT here
///
/// It reads *"Entries stay in this page's memory and disappear on reload"* —
/// true of a design preview and false of this app, where an entry is a write to
/// the owner's own server. Copying it would be the one kind of inaccuracy this
/// product cannot ship. Nothing replaces it: the honest version of that sentence
/// is that there is nothing to warn about.
///
/// ## Signed out is a different screen, not a disabled one
///
/// A journal is a write surface. With no session there is nothing to write to,
/// so the grid is not drawn dimmed — it is not drawn, and the screen offers the
/// one action that changes that.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/features/journal/v02/journal_grid.dart';
import 'package:healthee/features/journal/widgets/journal_recent.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/sheets/log_sheet.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/view_day.dart';

/// The prototype's own h1.
const String kJournalTitle = 'The rest of your day.';

/// Its eyebrow.
const String kJournalEyebrow = 'Your health journal';

/// The sentence under the head, verbatim.
const String kJournalIntro =
    'A few moments of context help make your measurements more personal.';

/// The section heading over the entries.
const String kMomentsHeading = 'Your recent moments';

/// The journal screen.
class JournalScreen extends ConsumerWidget {
  /// [now] is injected by tests so the relative times are deterministic.
  const JournalScreen({this.now, super.key});

  /// The instant "3 h ago" is measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<ServerSessionStatus>(
      value: currentAccountValue(ref.watch(serverSessionProvider)),
      onRetry: () => ref.invalidate(serverSessionProvider),
      builder: (context, status) => status.signedIn
          ? _SignedIn(now: now)
          : DetailPage(
              eyebrow: kJournalEyebrow,
              title: kJournalTitle,
              children: <Widget>[
                Text(
                  'A journal entry is a write to your own server. There is no '
                  'session to write to yet.',
                  style: TypeScale.small.copyWith(color: context.colors.ink2),
                ),
                const SizedBox(height: Insets.lg),
                ActionButton(
                  label: 'Sign in to save your journal',
                  full: true,
                  onPressed: () => unawaited(context.push(Routes.serverSignIn)),
                ),
                const DataFooter(),
              ],
            ),
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return AsyncView<JournalRepository>(
      value: currentAccountValue(ref.watch(journalRepositoryProvider)),
      onRetry: () => ref.invalidate(journalRepositoryProvider),
      builder: (context, repository) {
        // Read, never inferred: the tile says "End fast" only because the feed
        // said a fast is open.
        final fastOpen =
            currentAccountValue(
              ref.watch(journalFeedProvider),
            ).value?.data.fastOpen ??
            false;
        final ViewDay day = watchViewDay(ref);
        return DetailPage(
          key: ObjectKey(repository),
          // The journal is date-aware in the prototype's own route table, so
          // its head says which day these moments are from.
          eyebrow: day.line,
          title: kJournalTitle,
          children: <Widget>[
            Text(
              kJournalIntro,
              style: TypeScale.small.copyWith(color: colors.ink2),
            ),
            const SizedBox(height: Insets.lg),
            JournalGrid(
              fastOpen: fastOpen,
              onPick: (tile) => tile.kind == null
                  ? showFastSheet(
                      context,
                      repository: repository,
                      open: fastOpen,
                    )
                  : showLogSheet(
                      context,
                      repository: repository,
                      kind: tile.kind!,
                    ),
            ),
            const SizedBox(height: SectionHead.sectionGap),
            const SectionHead(title: kMomentsHeading),
            // The grid above still writes to NOW — a log is a write, and a
            // write dated to a day the owner is only reading would be a
            // measurement invented on the wrong day. Only the list follows.
            JournalRecent(now: now, day: day.isPast ? day.day : null),
            const DataFooter(),
          ],
        );
      },
    );
  }
}
