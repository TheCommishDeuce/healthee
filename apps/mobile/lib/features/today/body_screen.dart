/// `Biological age` — the prototype's `#body`, opened from Today's hero.
///
/// `design/mobile-preview/screens-fitness.js::H.screens.body`, read top to
/// bottom:
///
/// ```text
///   header                        Biological age
///   the hero                      the halo, the figure, the ruler, two terms
///   context bridge                two included contributors, and Explore fitness
///   From your age to this estimate the ladder, and the arithmetic in words
///   Fitness contribution          the years, the rail, the model's reference
///   Sleep contribution            the years, and the two hours behind them
///   Excluded, not counted as zero the lever nobody can price
///   How much confidence …         the model's limits, and its research
///   footer
/// ```
///
/// ## The hero is Today's hero, not a copy of it
///
/// `TodayBioHero` is the same widget the tab draws, given the same payload. A
/// detail screen that re-composed the figure it exists to explain would be free
/// to format it differently from the card that opened it — and this screen's
/// whole claim is that the calculation reconciles.
///
/// ## An estimate that was refused still has a screen
///
/// `excluded` rides on a `Withheld` reading (`reading.dart` argues why), so a
/// refused estimate still draws the refusal, the exclusion panel and the
/// caveats. What it does not draw is a ladder, two term panels and an equation
/// — those need numbers, and there are none.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/api/not_signed_in.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/today/v02/body_limits_panels.dart';
import 'package:healthee/features/today/v02/body_panels.dart';
import 'package:healthee/features/today/v02/today_hero.dart';
import 'package:healthee/features/today/v02/today_hero_withheld.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/screen_data.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_history.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/view_day.dart';

/// The prototype's own title for this screen.
const String kBodyTitle = 'Biological age';

/// `screens.body`'s past-day heading, with the app's own reason under it.
const String kBodyPastTitle = 'Estimated biological age';

/// `H.bridge('fitness', …)` — what the estimate includes, and what it leaves out.
const String kContributorsBridge =
    'This number has two included contributors. The calculation is visible, and '
    'unpriced factors stay outside it.';

/// The biological-age detail screen.
class BodyScreen extends ConsumerStatefulWidget {
  /// Builds the screen.
  const BodyScreen({super.key});

  @override
  ConsumerState<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends ConsumerState<BodyScreen> {
  /// Outlives every panel, which is the whole reveal-once mechanism.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final ViewDay day = watchViewDay(ref);
    // One age-model result exists and it is dated today. `/api/today` takes no
    // day, so an older date gets the refusal rather than this morning's figure
    // under it — see `shared/v02/past_day.dart`.
    //
    // `screens.body`'s own words for what sits under that refusal: *"historical
    // fitness and sleep inputs remain visible below"*. They are the model's
    // measured inputs, dated; the estimate they feed is not.
    if (day.isPast) {
      return _Frame(
        date: day.day,
        status: day.status,
        children: pastDayDetail(
          refusalTitle: kBodyPastTitle,
          history: ref.watch(datedHistoryProvider),
          // `panels(['vo2','sleep','regularity'])`, less the one this server
          // keeps no dated series for.
          metrics: const <HistoryMetric>[
            HistoryMetric.fitness,
            HistoryMetric.sleepRegularity,
          ],
          unserved: const <String>[kUnservedSleepDuration],
          day: day.day,
          reveals: _reveals,
          onRetry: () => ref.invalidate(datedHistoryProvider),
          onOpenMetric: (metric) => openMetricHistory(context, metric),
        ),
      );
    }
    final view = currentAccountValue(ref.watch(todaySnapshotProvider));
    return view.when(
      skipLoadingOnRefresh: true,
      loading: () => const _Frame(
        children: <Widget>[LoadingState(label: 'Reading your estimate')],
      ),
      error: (error, stackTrace) => _Frame(
        children: <Widget>[
          if (isNotSignedIn(error))
            signInNeededCard()
          else
            ErrorState(
              message: "Couldn't reach your server for your estimate",
              detail: 'This is a connection problem, not a gap in your data.',
              onRetry: () => ref.invalidate(todaySnapshotProvider),
            ),
        ],
      ),
      data: (value) => BodyDetail(snapshot: value.snapshot, reveals: _reveals),
    );
  }
}

/// The screen's body. Public so the screen tests can host it directly.
class BodyDetail extends StatelessWidget {
  /// Builds the detail for one render of `/api/today`.
  const BodyDetail({
    required this.snapshot,
    required this.reveals,
    super.key,
  });

  /// `.panel { margin-top: 12px }`.
  static const double panelGap = 12;

  /// `.section { margin-top: 24px }`.
  static const double blockGap = 24;

  /// The payload every figure on this screen comes off.
  final TodaySnapshot snapshot;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The levers this estimate permanently does not price, refused or not.
  ///
  /// A valued payload carries them on the parsed estimate, because the envelope
  /// folds exclusions in with the caveats and this screen has to tell the two
  /// apart (`biological_age.dart` records why). A refused one carries them on
  /// the reading, which is the case `Withheld.exclusions` exists for.
  List<Disclosure> get exclusions => switch (snapshot.biologicalAge) {
    Withheld<BiologicalAge>(:final exclusions) => exclusions,
    Excluded<BiologicalAge>(:final exclusions) => exclusions,
    Present<BiologicalAge>(:final value) => value.exclusions,
    Caveated<BiologicalAge>(:final value) => value.exclusions,
  };

  /// What tilts the estimate — the caveats, with the exclusions taken back out.
  ///
  /// They arrive merged and they are two different claims: one says which way
  /// the number leans, the other says a lever is not in it at all. The panel
  /// above already draws the second, and drawing it twice would read as two
  /// exclusions.
  List<Disclosure> get caveats => <Disclosure>[
    for (final caveat in snapshot.biologicalAge.caveatsOrEmpty)
      if (!exclusions.contains(caveat)) caveat,
  ];

  @override
  Widget build(BuildContext context) {
    final age = snapshot.biologicalAge.valueOrNull;
    return _Frame(
      date: snapshot.date,
      children: <Widget>[
        switch (snapshot.biologicalAge) {
          Withheld<BiologicalAge>(:final disclosure, :final exclusions) =>
            TodayBioHeroWithheld(withheld: disclosure, exclusions: exclusions),
          _ when age != null => TodayBioHero(age: age, reveals: reveals),
          _ => const SizedBox.shrink(),
        },
        ContextBridge.text(kContributorsBridge),
        if (age != null) ..._calculation(context, age),
        if (exclusions.isNotEmpty) ...<Widget>[
          const SizedBox(height: panelGap),
          ExcludedTermsPanel(
            exclusions: exclusions,
            onOpenSleep: () => unawaited(context.push(Routes.sleep)),
          ),
        ],
        const SizedBox(height: panelGap),
        AgeConfidencePanel(
          caveats: caveats,
          researchNotes: age?.researchNotes ?? const <String>[],
        ),
        const SizedBox(height: blockGap),
        const DataFooter(),
      ],
    );
  }

  /// The ladder and the two term panels — everything that needs numbers.
  List<Widget> _calculation(BuildContext context, BiologicalAge age) {
    final chronological = age.chronologicalAge;
    return <Widget>[
      if (chronological != null) ...<Widget>[
        const SizedBox(height: panelGap),
        AgeLadderPanel(
          age: age,
          chronologicalAge: chronological,
          reveals: reveals,
        ),
      ],
      for (final term in age.contributions) ...<Widget>[
        const SizedBox(height: panelGap),
        if (ageTermTone(term.term) == Tone.sleep)
          SleepTermPanel(
            term: term,
            onOpenSleep: () => unawaited(context.push(Routes.sleep)),
          )
        else
          FitnessTermPanel(
            term: term,
            vo2max: snapshot.vo2max.valueOrNull,
            reveals: reveals,
            onOpenFitness: () => unawaited(context.push(Routes.fitness)),
          ),
      ],
    ];
  }
}

/// The page every state of this screen is drawn in, so the head and the gutter
/// cannot differ between them.
class _Frame extends StatelessWidget {
  const _Frame({required this.children, this.date, this.status = kLatestSample});

  final List<Widget> children;
  final String? date;

  /// `Latest sample` unless the caller says otherwise: the body below is
  /// `/api/today`'s, which is the current day by construction.
  final String? status;

  @override
  Widget build(BuildContext context) => DetailPage(
    title: kBodyTitle,
    eyebrow: dayEyebrow(date, status),
    children: children,
  );
}
