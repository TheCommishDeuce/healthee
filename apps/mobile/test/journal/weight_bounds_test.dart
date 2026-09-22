/// The phone's weigh-in bounds are the server's (`core/bounds.py`), read from
/// the server's own source so a change on either side fails here rather than as
/// an entry held offline for an upload the server will always refuse.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/journal/log_draft.dart';

/// A numeric constant from the Python source: `10.0`, `700.0` or `10**12`.
double _serverConstant(String source, String name) {
  final match = RegExp(
    '^$name = ([0-9.]+)(?:\\*\\*([0-9]+))?\$',
    multiLine: true,
  ).firstMatch(source);
  expect(match, isNotNull, reason: '$name moved or changed shape in bounds.py');
  final base = double.parse(match!.group(1)!);
  final power = match.group(2);
  return power == null ? base : math.pow(base, int.parse(power)).toDouble();
}

void main() {
  test('the weight bounds match apps/server core/bounds.py', () {
    final source = File(
      '../server/src/healthee/core/bounds.py',
    ).readAsStringSync();
    expect(kMinWeightKg, _serverConstant(source, 'MIN_WEIGHT_KG'));
    expect(kMaxWeightKg, _serverConstant(source, 'MAX_WEIGHT_KG'));
    expect(
      kEarliestEvent.millisecondsSinceEpoch,
      _serverConstant(source, '_MS_THRESHOLD').toInt(),
    );
  });
}
