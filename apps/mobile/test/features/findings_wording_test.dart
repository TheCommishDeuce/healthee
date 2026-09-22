/// The insight rewrite, tested where the honesty actually lives: the wording.
///
/// The old surface printed the server's `description_raw` — a debug string built
/// by `analytics/correlations.py` as `Spearman(a, b) = +0.72 over 105 days
/// (p=0.000)` — as the headline of the owner's home screen. The rewrite composes
/// a sentence from the structured fields the server ships beside it and puts the
/// arithmetic behind a disclosure.
///
/// **Two things must be true at once**, and only one of them is about readability:
///
///   1. the surface is a sentence, and
///   2. **it never becomes causal.** A rewrite that traded "moved together" for
///      "improves" would read better and be a lie about an n-of-1 observational
///      correlation. That is the one failure that would make this change worse
///      than what it replaced, so the causal-verb list is asserted against every
///      string the surface can produce rather than against one example.
///
/// Pure functions, tested directly. Pumping a widget to read the wording back
/// would be testing the layout — and the layout is not what could be wrong here.
///
/// ## THERE ARE TWO COMPOSERS AND THIS FILE NAMES BOTH
///
/// It used to name one. `shared/findings_section.dart::findingHeadline` serves
/// Insights and Sleep; `features/today/widgets/insights_section.dart::describeFinding`
/// serves the **home screen**, which is the surface the original defect was on. Every
/// assertion below ran against the first while the second went on printing
/// `description_raw` as its headline — a test that goes green having exercised
/// something adjacent, which `docs/HOW_WE_VERIFY.md` section 2 calls the fictional
/// mutation's cousin.
///
/// So the wording rules are asserted over a LIST of composers rather than against one
/// name, and [_surfaces] is that list. A third composer is one line here on the day it
/// is written, which is the only version of this guard that cannot rot the same way.
///
/// The fixture matters as much as the target: the original test's finding was a
/// pairwise one with `metricB` set, so the fallback branch — the branch that printed
/// the raw string — was never entered by either function. [_event] and [_lonely] are
/// that branch.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/shared/findings_section.dart';
import 'package:healthee/shared/format/metric_names.dart';

/// The live production finding the owner saw as a log line.
const Finding _live = Finding(
  kind: 'pairwise_lag',
  metricA: 'hrv_sleep_avg',
  metricB: 'recovery_score',
  eventKind: null,
  description:
      'Spearman(hrv_sleep_avg, recovery_score) = +0.72 over 105 days (p=0.000)',
  effectSize: 0.72,
  effectMetric: 'rho',
  qValue: 0.0004,
  nSamples: 105,
  lagDays: 0,
  researchNoteIds: <String>['hrv_recovery_marker'],
);

/// The event finding the raw string reached the home screen on. `metric_b` is null
/// for every `event_effect` and `personal_cutoff` finding, which is the branch both
/// composers fall into and the one that used to print `description_raw` verbatim.
const Finding _event = Finding(
  kind: 'event_effect',
  metricA: 'sleep_health_score_4dim',
  metricB: null,
  eventKind: 'caffeine',
  description:
      'caffeine days vs others (same day, sleep_health_score_4dim): '
      'rank-biserial r=-0.42 (p=0.031, n_event=12, n_other=45)',
  effectSize: -0.42,
  effectMetric: 'rank_biserial',
  qValue: 0.031,
  nSamples: 57,
  lagDays: 0,
  researchNoteIds: <String>['caffeine_sleep'],
);

/// The same branch with no event kind either — nothing structured to say what the
/// comparison was. The headline must still not fall back to the raw string.
const Finding _lonely = Finding(
  kind: 'personal_cutoff',
  metricA: 'sleep_health_score_4dim',
  metricB: null,
  eventKind: null,
  description:
      'Spearman(caffeine, sleep_health_score_4dim) = -0.42 over 57 days (p=0.031)',
  effectSize: -0.42,
  effectMetric: 'rho',
  qValue: 0.031,
  nSamples: 57,
  lagDays: 0,
  researchNoteIds: <String>[],
);

/// **Every function that composes an owner-facing headline from a [Finding].**
///
/// The list IS the guard. Naming one of two is how the raw statistic reached the home
/// screen for a second time while a test called THE RAW SPEARMAN STRING NEVER REACHES
/// THE SURFACE went green.
final List<({String name, String Function(Finding) compose})> _surfaces =
    <({String name, String Function(Finding) compose})>[
      (
        name: 'shared/findings_section.dart::findingHeadline',
        compose: findingHeadline,
      ),
    ];

/// The finding shapes every composer is asserted over. The two one-metric shapes are
/// the branch the original fixture never entered.
final List<({String shape, Finding finding})> _shapes =
    <({String shape, Finding finding})>[
      (shape: 'a pairwise finding', finding: _live),
      (shape: 'an event finding', finding: _event),
      (shape: 'a one-metric finding with no event kind', finding: _lonely),
    ];

/// Fragments of the server's own debug strings. None may appear on any surface.
const List<String> _rawFragments = <String>[
  'Spearman',
  'rank-biserial',
  'p=',
  'n_event',
  'hrv_sleep_avg',
  'sleep_health_score_4dim',
];

/// Verbs and connectives that assert a cause. None may appear on the surface.
const List<String> _causal = <String>[
  'caused',
  'causes',
  'because',
  'improves',
  'improved',
  'helps',
  'hurts',
  'makes',
  'leads to',
  'thanks to',
  'due to',
  'drives',
];

void main() {
  group('EVERY composer, on every finding shape', () {
    // The matrix the single-target version of this file did not have: two composers by
    // three shapes, the two one-metric shapes being the branch that printed the raw
    // string.
    for (final surface in _surfaces) {
      for (final entry in _shapes) {
        test('${surface.name} · ${entry.shape} · NO RAW SERVER STRING', () {
          final headline = surface.compose(entry.finding);

          for (final fragment in _rawFragments) {
            expect(
              headline,
              isNot(contains(fragment)),
              reason:
                  '"$fragment" comes out of the server\'s own debug string — '
                  '${surface.name} is composing from description_raw',
            );
          }
          // Not merely "does not contain it": the whole headline must not BE it.
          expect(headline, isNot(equals(entry.finding.description)));
        });

        test('${surface.name} · ${entry.shape} · NOT CAUSAL', () {
          final headline = surface.compose(entry.finding).toLowerCase();
          for (final verb in _causal) {
            expect(
              headline,
              isNot(contains(verb)),
              reason:
                  '"$verb" asserts a cause; this is an observational n-of-1',
            );
          }
        });
      }
    }

    test('an event finding names the event, from the structured field', () {
      // `event_kind` was parsed by both models and used by one. This is the sentence
      // that exists precisely so the raw string is never needed.
      expect(
        findingHeadline(_event),
        'Your sleep health on caffeine days, against your other days',
      );
    });

  });

  group('the headline is a sentence in the owner\'s language', () {
    test('THE RAW SPEARMAN STRING NEVER REACHES THE SURFACE', () {
      final surface = '${findingHeadline(_live)} ${findingWindow(_live)}';
      expect(surface, isNot(contains('Spearman')));
      expect(surface, isNot(contains('hrv_sleep_avg')));
      expect(surface, isNot(contains('p=')));
      expect(surface, isNot(contains('rho')));
    });

    test('it names both metrics and the direction', () {
      expect(
        findingHeadline(_live),
        'Your overnight HRV moved with your recovery',
      );
    });

    test('a negative effect moves the other way, and still not causally', () {
      const negative = Finding(
        kind: 'pairwise_lag',
        metricA: 'caffeine',
        metricB: 'sleep_health_score_4dim',
        eventKind: null,
        description: 'Caffeine ↔ sleep',
        effectSize: -0.42,
        effectMetric: 'rho',
        qValue: 0.03,
        nSamples: 24,
        lagDays: 0,
        researchNoteIds: <String>['caffeine_sleep'],
      );
      expect(
        findingHeadline(negative),
        'Your caffeine moved opposite to your sleep health',
      );
    });

    test('the window line carries the strength, the days and the lag', () {
      expect(
        findingWindow(_live),
        'Closely, across 105 days of your own history.',
      );
      const lagged = Finding(
        kind: 'pairwise_lag',
        metricA: 'mvpa_min',
        metricB: 'hrv_sleep_avg',
        eventKind: null,
        description: 'x',
        effectSize: 0.45,
        effectMetric: 'rho',
        qValue: 0.02,
        nSamples: 61,
        lagDays: 1,
        researchNoteIds: <String>[],
      );
      expect(
        findingWindow(lagged),
        'Moderately, across 61 days of your own history, strongest 1 day apart.',
      );
    });

    test(
      'an unnamed metric keeps its id rather than being invented into prose',
      () {
        const unknown = Finding(
          kind: 'pairwise_lag',
          metricA: 'some_new_metric',
          metricB: 'rhr_daily',
          eventKind: null,
          description: 'x',
          effectSize: 0.5,
          effectMetric: 'rho',
          qValue: 0.01,
          nSamples: 40,
          lagDays: 0,
          researchNoteIds: <String>[],
        );
        expect(findingHeadline(unknown), contains('some_new_metric'));
        expect(hasMetricName('some_new_metric'), isFalse);
        expect(metricName('rhr_daily'), 'resting heart rate');
      },
    );
  });

  group('NO FINDING MAY ACQUIRE CAUSAL LANGUAGE', () {
    test('not the headline, not the window line, not the disclosure', () {
      final strings = <String>[
        findingHeadline(_live),
        findingWindow(_live),
        findingStatistics(_live),
      ];
      for (final surface in strings) {
        for (final verb in _causal) {
          // The disclosure's closing sentence is allowed to USE the word in a
          // denial — "not that either one caused the other" — and that is the
          // one exception, checked by its own assertion below.
          final withoutDenial = surface.replaceAll(
            'not that either one caused the other',
            '',
          );
          expect(
            withoutDenial.toLowerCase(),
            isNot(contains(verb)),
            reason: '"$verb" asserts a cause; this is an observational n-of-1',
          );
        }
      }
    });

    test('THE CAVEAT SURVIVES INTO THE DISCLOSURE, not just above it', () {
      // Losing the framing to gain readability is the failure that would make
      // this worse. A reader who opens the arithmetic gets it with the numbers.
      expect(
        findingStatistics(_live),
        contains('not that either one caused the other'),
      );
      expect(
        findingStatistics(_live),
        contains('One person, one stretch of time'),
      );
    });
  });

  group('the statistic is complete behind the disclosure', () {
    test('nothing the old surface said was dropped', () {
      final answer = findingStatistics(_live);
      expect(answer, contains('rho = 0.72'));
      expect(answer, contains('105 days'));
      expect(answer, contains('Same day'));
      expect(answer, contains('q = 0.000'));
      expect(
        answer,
        contains('correcting for the size of the search'),
        reason: 'the multiple-comparison correction is part of the claim',
      );
    });

    test('a lagged finding says which way the lag runs', () {
      const lagged = Finding(
        kind: 'pairwise_lag',
        metricA: 'steps_total',
        metricB: 'hrv_sleep_avg',
        eventKind: null,
        description: 'x',
        effectSize: 0.31,
        effectMetric: 'rho',
        qValue: 0.04,
        nSamples: 45,
        lagDays: 2,
        researchNoteIds: <String>[],
      );
      expect(
        findingStatistics(lagged),
        contains('the second value is taken 2 days after the first'),
      );
    });
  });
}
