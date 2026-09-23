/// A3 · the three honesty fields the recovery ladder used to drop at the boundary.
///
/// `recovery.signals[]` carries `n`, `direction_basis` and `population_floor_min`. Each
/// was added deliberately with the reason written beside it in
/// `read/recovery_signals.py`, each is tested on the server, and none of them was parsed
/// here — `grep direction_basis population_floor_min` over `apps/mobile/lib` returned
/// nothing. The server did the honest work and the client filed it under a key nothing
/// read.
///
/// **`direction_basis` is the sharpest, and it is sharpest for this owner.** The sleep
/// signal calls itself "vs personal usual" and then decides its direction from an
/// absolute floor as well as from the personal z, so the module says plainly: *"for a
/// chronic short sleeper the population floor decides every night and the personal number
/// beside it cannot change the verdict."* This app's owner is a chronic short sleeper.
/// Without the field the ladder draws a personal z beside a verdict that z did not
/// produce.
///
/// Tested as pure functions over a parsed payload rather than by pumping the panel: the
/// sentences ARE the disclosure, and reading them back off a widget tree would assert the
/// layout instead. The panel drawing them is covered by `recovery_screen_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/recovery_signals.dart';
import 'package:healthee/features/today/v02/recovery_detail_panels.dart';

Map<String, Object?> _signal({
  required String name,
  int? n,
  String? directionBasis,
  double? populationFloorMin,
  String direction = 'neutral',
  String unit = 'min',
}) => <String, Object?>{
  'name': name,
  'value': 280.0,
  'baseline': 380.0,
  'baseline_sd': 40.0,
  'n': ?n,
  'z': -2.5,
  'direction': direction,
  'direction_basis': ?directionBasis,
  'population_floor_min': ?populationFloorMin,
  'unit': unit,
  'research_note_id': 'sleep_duration_mortality',
};

RecoverySignals _ladder(List<Map<String, Object?>> signals) =>
    RecoverySignals.maybe(<String, Object?>{
      'summary': 'Recovery signals lean unfavorable',
      'favorable': 0,
      'unfavorable': 1,
      'neutral': 0,
      'total': signals.length,
      'signals': signals,
    })!;

void main() {
  group('the three fields reach the model', () {
    test('all three are parsed off the wire', () {
      final ladder = _ladder(<Map<String, Object?>>[
        _signal(
          name: 'Sleep duration',
          n: 7,
          direction: 'unfavorable',
          directionBasis: 'population',
          populationFloorMin: 300,
        ),
      ]);

      final signal = ladder.signals.single;
      expect(signal.n, 7);
      expect(signal.directionBasis, 'population');
      expect(signal.populationFloorMin, 300);
    });

    test('each is null when the server did not send it, never defaulted', () {
      // A count of zero would say "no days behind this baseline", which is a claim; a
      // basis of "personal" would be a guess about which limb spoke. Absent is absent.
      final signal = _ladder(<Map<String, Object?>>[
        _signal(name: 'Resting HR'),
      ]).signals.single;

      expect(signal.n, isNull);
      expect(signal.directionBasis, isNull);
      expect(signal.populationFloorMin, isNull);
    });
  });

  group('WHICH LIMB PRODUCED THE VERDICT', () {
    test('a population verdict says the personal number did not decide it', () {
      final note = directionBasisNote(
        _ladder(<Map<String, Object?>>[
          _signal(
            name: 'Sleep duration',
            n: 30,
            direction: 'unfavorable',
            directionBasis: 'population',
            populationFloorMin: 300,
          ),
        ]),
      );

      expect(
        note,
        'Sleep duration is called unfavourable by the population floor of 5h 00m, '
        'not by your own baseline beside it.',
      );
    });

    test('a personal verdict says the floor did not', () {
      final note = directionBasisNote(
        _ladder(<Map<String, Object?>>[
          _signal(
            name: 'Sleep duration',
            n: 30,
            direction: 'unfavorable',
            directionBasis: 'personal',
            populationFloorMin: 300,
          ),
        ]),
      );

      expect(
        note,
        'Sleep duration is called unfavourable by your own baseline, not by the '
        'population floor of 5h 00m.',
      );
    });

    test('both limbs agreeing says so rather than picking one', () {
      final note = directionBasisNote(
        _ladder(<Map<String, Object?>>[
          _signal(
            name: 'Sleep duration',
            n: 30,
            direction: 'unfavorable',
            directionBasis: 'both',
            populationFloorMin: 300,
          ),
        ]),
      );

      expect(note, contains('and by the population floor of 5h 00m alike'));
    });

    test('A MINUTE READING IS HOURS AND MINUTES, like everywhere else', () {
      // The baseline row read "416 min" beside Sleep's "6h 56m" for the same
      // night — the B4 defect on another screen.
      final signal = _ladder(<Map<String, Object?>>[
        _signal(name: 'Sleep duration'),
      ]).signals.single;
      expect(BaselinePanel.reading(signal), '4h 40m');
    });

    test('THE FLOOR IS NAMED, never left as a bare word', () {
      // "The population floor decided this" is a claim a reader can only weigh if the
      // floor is a number. `population_floor_min` ships for exactly that, and dropping
      // it at the client left the sentence unweighable.
      final note = directionBasisNote(
        _ladder(<Map<String, Object?>>[
          _signal(
            name: 'Sleep duration',
            n: 30,
            direction: 'unfavorable',
            directionBasis: 'population',
            populationFloorMin: 300,
          ),
        ]),
      );

      expect(note, contains('5h 00m'));
    });

    test('an older server that sends no floor still says which limb spoke', () {
      // The two fields travel together but the sentence degrades rather than vanishing:
      // "which limb" is the disclosure, "how far" is the detail.
      final note = directionBasisNote(
        _ladder(<Map<String, Object?>>[
          _signal(
            name: 'Sleep duration',
            direction: 'unfavorable',
            directionBasis: 'population',
          ),
        ]),
      );

      expect(note, contains('by the population floor,'));
      expect(note, isNot(contains('null')));
    });

    test('nothing unfavourable means nothing to disambiguate', () {
      // Only the unfavourable branch has two independent limbs. A note on a favourable
      // ladder would be a sentence about a decision that was not made.
      expect(
        directionBasisNote(
          _ladder(<Map<String, Object?>>[
            _signal(name: 'Sleep duration', n: 30),
          ]),
        ),
        isNull,
      );
    });
  });

  group('HOW MANY DAYS EACH BASELINE RESTS ON', () {
    test('the counts are per signal, not a range', () {
      // A range cannot say which verdict to discount, and that is the whole use of the
      // number: the RHR and HRV signals once published a direction from two mornings.
      final note = baselineDepthNote(
        _ladder(<Map<String, Object?>>[
          _signal(name: 'Resting HR', n: 30, unit: 'bpm'),
          _signal(name: 'Sleep duration', n: 7),
          _signal(name: 'Overnight HRV', n: 30, unit: 'ms'),
        ]),
      );

      expect(
        note,
        'Days of your own history behind each baseline: Resting HR 30, '
        'Sleep duration 7, Overnight HRV 30.',
      );
    });

    test('a signal with no count is left out rather than shown as zero', () {
      final note = baselineDepthNote(
        _ladder(<Map<String, Object?>>[
          _signal(name: 'Resting HR', n: 30, unit: 'bpm'),
          _signal(name: 'Sleep duration'),
        ]),
      );

      expect(
        note,
        'Days of your own history behind each baseline: Resting HR 30.',
      );
    });

    test('an older server sending no counts at all draws no line', () {
      expect(
        baselineDepthNote(
          _ladder(<Map<String, Object?>>[_signal(name: 'Resting HR')]),
        ),
        isNull,
      );
    });
  });
}
