// `revealCuts` decides where a validated answer may be cut on its way to the
// screen. The invariant that matters: every prefix is the answer's OWN text, and
// the last one is the whole answer — nothing is re-joined or re-spaced.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/features/coach/widgets/coach_reveal.dart';

void main() {
  test('the last cut is the whole answer and cuts only ever move forward', () {
    const text = 'One thing. Another thing! A third? Done.';
    final cuts = revealCuts(text);
    expect(cuts.last, text.length);
    for (int i = 1; i < cuts.length; i++) {
      expect(cuts[i], greaterThan(cuts[i - 1]));
    }
  });

  test('a sentence ends where the next one starts, not at every full stop', () {
    const text = 'You slept 6.5 hours. That is 1.5 short. Tonight, earlier.';
    final cuts = revealCuts(text);
    final pieces = <String>[
      for (int i = 0; i < cuts.length; i++)
        text.substring(i == 0 ? 0 : cuts[i - 1], cuts[i]),
    ];
    expect(pieces, <String>[
      'You slept 6.5 hours.',
      ' That is 1.5 short.',
      ' Tonight, earlier.',
    ]);
    expect(pieces.join(), text);
  });

  test('a citation before the full stop stays with its sentence', () {
    const text = 'Debt accumulates [sleep_need_debt]. Timing is fine.';
    final cuts = revealCuts(text);
    expect(
      text.substring(0, cuts.first),
      'Debt accumulates [sleep_need_debt].',
    );
  });

  test('a line break is a cut on its own, so paragraphs arrive whole', () {
    const text = 'First paragraph ends here\n\nSecond starts lowercase here.';
    final cuts = revealCuts(text);
    expect(text.substring(0, cuts.first), 'First paragraph ends here\n\n');
    expect(cuts.last, text.length);
  });

  test('a one-sentence answer is one step, and a blank one is none', () {
    expect(revealCuts('Just this.'), <int>['Just this.'.length]);
    expect(revealCuts('   '), isEmpty);
  });

  test('the interval keeps a whole answer near two seconds, within bounds', () {
    expect(revealInterval(1), Duration.zero);
    expect(revealInterval(10).inMilliseconds, 220);
    expect(revealInterval(100).inMilliseconds, 70); // floor
    expect(revealInterval(3).inMilliseconds, 300); // ceiling
  });
}
