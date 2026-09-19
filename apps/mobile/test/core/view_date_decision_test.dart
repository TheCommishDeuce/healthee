// The date control could leave the newest day exactly once and then never move
// again — not to another day, not back to today. These tests replay that, pass
// by pass, against the pure decision the router's redirect runs.
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/view_date_route.dart';

const String latest = '2026-09-19';

/// One routing pass, feeding the previous pass's memory back in.
ViewDateDecision pass(
  String location, {
  required String selected,
  required String? honoured,
  String? requested,
}) => decideViewDate(
  location: location,
  requested: requested,
  selected: selected,
  latest: latest,
  honoured: honoured,
);

void main() {
  test('the first pick rewrites the URL to the picked day', () {
    final d = pass('/today', selected: '2026-09-15', honoured: null);
    expect(d.redirectTo, '/today?date=2026-09-15');
    expect(d.adopt, isNull);
    expect(d.honoured, '2026-09-15');
  });

  test('a SECOND pick wins over the day still sitting in the URL', () {
    // The bug: requested (09-15, stale URL) != selected (09-12) used to be read
    // as a link and re-selected 09-15, so the control never moved again.
    final d = pass(
      '/today?date=2026-09-15',
      requested: '2026-09-15',
      selected: '2026-09-12',
      honoured: '2026-09-15',
    );
    expect(d.adopt, isNull);
    expect(d.redirectTo, '/today?date=2026-09-12');
    expect(d.honoured, '2026-09-12');
  });

  test('going back to today removes the parameter instead of being undone', () {
    final d = pass(
      '/today?date=2026-09-15',
      requested: '2026-09-15',
      selected: latest,
      honoured: '2026-09-15',
    );
    expect(d.adopt, isNull);
    expect(d.redirectTo, '/today');
    expect(d.honoured, isNull);
  });

  test('a genuinely new link still wins once', () {
    final d = pass(
      '/sleep?date=2026-09-10',
      requested: '2026-09-10',
      selected: '2026-09-15',
      honoured: '2026-09-15',
    );
    expect(d.adopt, '2026-09-10');
    expect(d.redirectTo, isNull);
    expect(d.honoured, '2026-09-10');
  });

  test('a link from the newest day wins when nothing was honoured yet', () {
    final d = pass(
      '/today?date=2026-09-10',
      requested: '2026-09-10',
      selected: latest,
      honoured: null,
    );
    expect(d.adopt, '2026-09-10');
  });

  test('a link outside the retention window is rewritten, never adopted', () {
    final d = pass(
      '/today?date=2020-01-01',
      requested: '2020-01-01',
      selected: '2026-09-15',
      honoured: null,
    );
    expect(d.adopt, isNull);
    expect(d.redirectTo, '/today?date=2026-09-15');
  });

  test('a tab switch with no day carries the selection along', () {
    final d = pass('/sleep', selected: '2026-09-15', honoured: '2026-09-15');
    expect(d.redirectTo, '/sleep?date=2026-09-15');
  });

  test('an agreeing URL settles: no redirect, no adoption', () {
    final d = pass(
      '/today?date=2026-09-15',
      requested: '2026-09-15',
      selected: '2026-09-15',
      honoured: '2026-09-15',
    );
    expect(d.redirectTo, isNull);
    expect(d.adopt, isNull);
    expect(d.honoured, '2026-09-15');
  });

  test('pick, pick, back to today — replayed as the router would run it', () {
    String? honoured;
    var d = pass('/today', selected: '2026-09-15', honoured: honoured);
    honoured = d.honoured;
    d = pass(
      d.redirectTo!,
      requested: '2026-09-15',
      selected: '2026-09-12',
      honoured: honoured,
    );
    expect(d.adopt, isNull, reason: 'the second pick must not be undone');
    honoured = d.honoured;
    d = pass(
      d.redirectTo!,
      requested: '2026-09-12',
      selected: latest,
      honoured: honoured,
    );
    expect(d.adopt, isNull, reason: 'returning to today must not be undone');
    expect(d.redirectTo, '/today');
  });
}
