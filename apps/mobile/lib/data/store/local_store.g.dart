// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_store.dart';

// ignore_for_file: type=lint
class $CachedPayloadsTable extends CachedPayloads
    with TableInfo<$CachedPayloadsTable, CachedPayload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPayloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 10,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricMeta = const VerificationMeta('metric');
  @override
  late final GeneratedColumn<String> metric = GeneratedColumn<String>(
    'metric',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    day,
    metric,
    payload,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_payloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPayload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('metric')) {
      context.handle(
        _metricMeta,
        metric.isAcceptableOrUnknown(data['metric']!, _metricMeta),
      );
    } else if (isInserting) {
      context.missing(_metricMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, day, metric};
  @override
  CachedPayload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPayload(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      metric: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CachedPayloadsTable createAlias(String alias) {
    return $CachedPayloadsTable(attachedDatabase, alias);
  }
}

class CachedPayload extends DataClass implements Insertable<CachedPayload> {
  /// Opaque sign-in namespace. No token or personal identifier is stored here.
  final String scope;

  /// The owner-local calendar date this payload describes, as `YYYY-MM-DD`.
  final String day;

  /// Which payload it is — `today`, `sleep`, `activity`, … (the endpoint's name).
  final String metric;

  /// The response body, verbatim, as JSON text.
  final String payload;

  /// When we received it. A genuine instant, so a DateTime is the right type
  /// here — and `storeDateTimeAsText` below keeps it in UTC across the round
  /// trip. It drives staleness display, never correctness.
  final DateTime fetchedAt;
  const CachedPayload({
    required this.scope,
    required this.day,
    required this.metric,
    required this.payload,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['day'] = Variable<String>(day);
    map['metric'] = Variable<String>(metric);
    map['payload'] = Variable<String>(payload);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CachedPayloadsCompanion toCompanion(bool nullToAbsent) {
    return CachedPayloadsCompanion(
      scope: Value(scope),
      day: Value(day),
      metric: Value(metric),
      payload: Value(payload),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CachedPayload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPayload(
      scope: serializer.fromJson<String>(json['scope']),
      day: serializer.fromJson<String>(json['day']),
      metric: serializer.fromJson<String>(json['metric']),
      payload: serializer.fromJson<String>(json['payload']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'day': serializer.toJson<String>(day),
      'metric': serializer.toJson<String>(metric),
      'payload': serializer.toJson<String>(payload),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CachedPayload copyWith({
    String? scope,
    String? day,
    String? metric,
    String? payload,
    DateTime? fetchedAt,
  }) => CachedPayload(
    scope: scope ?? this.scope,
    day: day ?? this.day,
    metric: metric ?? this.metric,
    payload: payload ?? this.payload,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CachedPayload copyWithCompanion(CachedPayloadsCompanion data) {
    return CachedPayload(
      scope: data.scope.present ? data.scope.value : this.scope,
      day: data.day.present ? data.day.value : this.day,
      metric: data.metric.present ? data.metric.value : this.metric,
      payload: data.payload.present ? data.payload.value : this.payload,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPayload(')
          ..write('scope: $scope, ')
          ..write('day: $day, ')
          ..write('metric: $metric, ')
          ..write('payload: $payload, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, day, metric, payload, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPayload &&
          other.scope == this.scope &&
          other.day == this.day &&
          other.metric == this.metric &&
          other.payload == this.payload &&
          other.fetchedAt == this.fetchedAt);
}

class CachedPayloadsCompanion extends UpdateCompanion<CachedPayload> {
  final Value<String> scope;
  final Value<String> day;
  final Value<String> metric;
  final Value<String> payload;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CachedPayloadsCompanion({
    this.scope = const Value.absent(),
    this.day = const Value.absent(),
    this.metric = const Value.absent(),
    this.payload = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPayloadsCompanion.insert({
    this.scope = const Value.absent(),
    required String day,
    required String metric,
    required String payload,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : day = Value(day),
       metric = Value(metric),
       payload = Value(payload),
       fetchedAt = Value(fetchedAt);
  static Insertable<CachedPayload> custom({
    Expression<String>? scope,
    Expression<String>? day,
    Expression<String>? metric,
    Expression<String>? payload,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (day != null) 'day': day,
      if (metric != null) 'metric': metric,
      if (payload != null) 'payload': payload,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPayloadsCompanion copyWith({
    Value<String>? scope,
    Value<String>? day,
    Value<String>? metric,
    Value<String>? payload,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CachedPayloadsCompanion(
      scope: scope ?? this.scope,
      day: day ?? this.day,
      metric: metric ?? this.metric,
      payload: payload ?? this.payload,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (metric.present) {
      map['metric'] = Variable<String>(metric.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPayloadsCompanion(')
          ..write('scope: $scope, ')
          ..write('day: $day, ')
          ..write('metric: $metric, ')
          ..write('payload: $payload, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StrapSamplesTable extends StrapSamples
    with TableInfo<$StrapSamplesTable, StoredSample> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StrapSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _metricMeta = const VerificationMeta('metric');
  @override
  late final GeneratedColumn<String> metric = GeneratedColumn<String>(
    'metric',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 32,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tsMsMeta = const VerificationMeta('tsMs');
  @override
  late final GeneratedColumn<int> tsMs = GeneratedColumn<int>(
    'ts_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 10,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pushedAtMsMeta = const VerificationMeta(
    'pushedAtMs',
  );
  @override
  late final GeneratedColumn<int> pushedAtMs = GeneratedColumn<int>(
    'pushed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [metric, tsMs, day, value, pushedAtMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'strap_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredSample> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('metric')) {
      context.handle(
        _metricMeta,
        metric.isAcceptableOrUnknown(data['metric']!, _metricMeta),
      );
    } else if (isInserting) {
      context.missing(_metricMeta);
    }
    if (data.containsKey('ts_ms')) {
      context.handle(
        _tsMsMeta,
        tsMs.isAcceptableOrUnknown(data['ts_ms']!, _tsMsMeta),
      );
    } else if (isInserting) {
      context.missing(_tsMsMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('pushed_at_ms')) {
      context.handle(
        _pushedAtMsMeta,
        pushedAtMs.isAcceptableOrUnknown(
          data['pushed_at_ms']!,
          _pushedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {metric, tsMs};
  @override
  StoredSample map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSample(
      metric: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric'],
      )!,
      tsMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ts_ms'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
      pushedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pushed_at_ms'],
      ),
    );
  }

  @override
  $StrapSamplesTable createAlias(String alias) {
    return $StrapSamplesTable(attachedDatabase, alias);
  }
}

class StoredSample extends DataClass implements Insertable<StoredSample> {
  /// The metric's wire name — `hr`, `hrv`, `spo2`, `stress`, `resting_hr`, …
  ///
  /// The same names `StrapSample.metric` uses, unmapped. The legacy push mapped
  /// them to the server's canonical vocabulary on the way out; there is no push
  /// in this package, so there is no mapping and no second name for anything.
  final String metric;

  /// When the strap recorded it, epoch milliseconds.
  final int tsMs;

  /// The owner-local calendar date [tsMs] falls on, `YYYY-MM-DD`. Denormalised
  /// from the instant so the horizon prune is one indexed string comparison
  /// rather than 60 days of arithmetic per row.
  final String day;

  /// The decoded value, in the metric's own unit. Untouched.
  final double value;

  /// When `POST /ingest/helio` accepted this row, epoch ms — null while it is
  /// still waiting to be sent. See [pushedAtMs] on [DeviceTotals] for why the
  /// marker lives on the row rather than in a high-water cursor.
  ///
  /// A re-pulled sample keeps its marker: `(metric, ts)` is the measurement's
  /// identity and its value does not change, so re-sending 60 days of samples
  /// every sync would buy nothing.
  final int? pushedAtMs;
  const StoredSample({
    required this.metric,
    required this.tsMs,
    required this.day,
    required this.value,
    this.pushedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['metric'] = Variable<String>(metric);
    map['ts_ms'] = Variable<int>(tsMs);
    map['day'] = Variable<String>(day);
    map['value'] = Variable<double>(value);
    if (!nullToAbsent || pushedAtMs != null) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs);
    }
    return map;
  }

  StrapSamplesCompanion toCompanion(bool nullToAbsent) {
    return StrapSamplesCompanion(
      metric: Value(metric),
      tsMs: Value(tsMs),
      day: Value(day),
      value: Value(value),
      pushedAtMs: pushedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(pushedAtMs),
    );
  }

  factory StoredSample.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSample(
      metric: serializer.fromJson<String>(json['metric']),
      tsMs: serializer.fromJson<int>(json['tsMs']),
      day: serializer.fromJson<String>(json['day']),
      value: serializer.fromJson<double>(json['value']),
      pushedAtMs: serializer.fromJson<int?>(json['pushedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'metric': serializer.toJson<String>(metric),
      'tsMs': serializer.toJson<int>(tsMs),
      'day': serializer.toJson<String>(day),
      'value': serializer.toJson<double>(value),
      'pushedAtMs': serializer.toJson<int?>(pushedAtMs),
    };
  }

  StoredSample copyWith({
    String? metric,
    int? tsMs,
    String? day,
    double? value,
    Value<int?> pushedAtMs = const Value.absent(),
  }) => StoredSample(
    metric: metric ?? this.metric,
    tsMs: tsMs ?? this.tsMs,
    day: day ?? this.day,
    value: value ?? this.value,
    pushedAtMs: pushedAtMs.present ? pushedAtMs.value : this.pushedAtMs,
  );
  StoredSample copyWithCompanion(StrapSamplesCompanion data) {
    return StoredSample(
      metric: data.metric.present ? data.metric.value : this.metric,
      tsMs: data.tsMs.present ? data.tsMs.value : this.tsMs,
      day: data.day.present ? data.day.value : this.day,
      value: data.value.present ? data.value.value : this.value,
      pushedAtMs: data.pushedAtMs.present
          ? data.pushedAtMs.value
          : this.pushedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSample(')
          ..write('metric: $metric, ')
          ..write('tsMs: $tsMs, ')
          ..write('day: $day, ')
          ..write('value: $value, ')
          ..write('pushedAtMs: $pushedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(metric, tsMs, day, value, pushedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSample &&
          other.metric == this.metric &&
          other.tsMs == this.tsMs &&
          other.day == this.day &&
          other.value == this.value &&
          other.pushedAtMs == this.pushedAtMs);
}

class StrapSamplesCompanion extends UpdateCompanion<StoredSample> {
  final Value<String> metric;
  final Value<int> tsMs;
  final Value<String> day;
  final Value<double> value;
  final Value<int?> pushedAtMs;
  final Value<int> rowid;
  const StrapSamplesCompanion({
    this.metric = const Value.absent(),
    this.tsMs = const Value.absent(),
    this.day = const Value.absent(),
    this.value = const Value.absent(),
    this.pushedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StrapSamplesCompanion.insert({
    required String metric,
    required int tsMs,
    required String day,
    required double value,
    this.pushedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : metric = Value(metric),
       tsMs = Value(tsMs),
       day = Value(day),
       value = Value(value);
  static Insertable<StoredSample> custom({
    Expression<String>? metric,
    Expression<int>? tsMs,
    Expression<String>? day,
    Expression<double>? value,
    Expression<int>? pushedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (metric != null) 'metric': metric,
      if (tsMs != null) 'ts_ms': tsMs,
      if (day != null) 'day': day,
      if (value != null) 'value': value,
      if (pushedAtMs != null) 'pushed_at_ms': pushedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StrapSamplesCompanion copyWith({
    Value<String>? metric,
    Value<int>? tsMs,
    Value<String>? day,
    Value<double>? value,
    Value<int?>? pushedAtMs,
    Value<int>? rowid,
  }) {
    return StrapSamplesCompanion(
      metric: metric ?? this.metric,
      tsMs: tsMs ?? this.tsMs,
      day: day ?? this.day,
      value: value ?? this.value,
      pushedAtMs: pushedAtMs ?? this.pushedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (metric.present) {
      map['metric'] = Variable<String>(metric.value);
    }
    if (tsMs.present) {
      map['ts_ms'] = Variable<int>(tsMs.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (pushedAtMs.present) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StrapSamplesCompanion(')
          ..write('metric: $metric, ')
          ..write('tsMs: $tsMs, ')
          ..write('day: $day, ')
          ..write('value: $value, ')
          ..write('pushedAtMs: $pushedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SleepSessionsTable extends SleepSessions
    with TableInfo<$SleepSessionsTable, StoredSleepSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SleepSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _startMsMeta = const VerificationMeta(
    'startMs',
  );
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
    'start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 10,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isNapMeta = const VerificationMeta('isNap');
  @override
  late final GeneratedColumn<bool> isNap = GeneratedColumn<bool>(
    'is_nap',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_nap" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sleepStartMinMeta = const VerificationMeta(
    'sleepStartMin',
  );
  @override
  late final GeneratedColumn<int> sleepStartMin = GeneratedColumn<int>(
    'sleep_start_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sleepEndMinMeta = const VerificationMeta(
    'sleepEndMin',
  );
  @override
  late final GeneratedColumn<int> sleepEndMin = GeneratedColumn<int>(
    'sleep_end_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avgHrMeta = const VerificationMeta('avgHr');
  @override
  late final GeneratedColumn<int> avgHr = GeneratedColumn<int>(
    'avg_hr',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remMinMeta = const VerificationMeta('remMin');
  @override
  late final GeneratedColumn<int> remMin = GeneratedColumn<int>(
    'rem_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lightMinMeta = const VerificationMeta(
    'lightMin',
  );
  @override
  late final GeneratedColumn<int> lightMin = GeneratedColumn<int>(
    'light_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deepMinMeta = const VerificationMeta(
    'deepMin',
  );
  @override
  late final GeneratedColumn<int> deepMin = GeneratedColumn<int>(
    'deep_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wakeMinMeta = const VerificationMeta(
    'wakeMin',
  );
  @override
  late final GeneratedColumn<int> wakeMin = GeneratedColumn<int>(
    'wake_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stagesJsonMeta = const VerificationMeta(
    'stagesJson',
  );
  @override
  late final GeneratedColumn<String> stagesJson = GeneratedColumn<String>(
    'stages_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pushedAtMsMeta = const VerificationMeta(
    'pushedAtMs',
  );
  @override
  late final GeneratedColumn<int> pushedAtMs = GeneratedColumn<int>(
    'pushed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    startMs,
    day,
    isNap,
    sleepStartMin,
    sleepEndMin,
    avgHr,
    score,
    remMin,
    lightMin,
    deepMin,
    wakeMin,
    stagesJson,
    pushedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sleep_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredSleepSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('start_ms')) {
      context.handle(
        _startMsMeta,
        startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('is_nap')) {
      context.handle(
        _isNapMeta,
        isNap.isAcceptableOrUnknown(data['is_nap']!, _isNapMeta),
      );
    } else if (isInserting) {
      context.missing(_isNapMeta);
    }
    if (data.containsKey('sleep_start_min')) {
      context.handle(
        _sleepStartMinMeta,
        sleepStartMin.isAcceptableOrUnknown(
          data['sleep_start_min']!,
          _sleepStartMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sleepStartMinMeta);
    }
    if (data.containsKey('sleep_end_min')) {
      context.handle(
        _sleepEndMinMeta,
        sleepEndMin.isAcceptableOrUnknown(
          data['sleep_end_min']!,
          _sleepEndMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sleepEndMinMeta);
    }
    if (data.containsKey('avg_hr')) {
      context.handle(
        _avgHrMeta,
        avgHr.isAcceptableOrUnknown(data['avg_hr']!, _avgHrMeta),
      );
    } else if (isInserting) {
      context.missing(_avgHrMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('rem_min')) {
      context.handle(
        _remMinMeta,
        remMin.isAcceptableOrUnknown(data['rem_min']!, _remMinMeta),
      );
    } else if (isInserting) {
      context.missing(_remMinMeta);
    }
    if (data.containsKey('light_min')) {
      context.handle(
        _lightMinMeta,
        lightMin.isAcceptableOrUnknown(data['light_min']!, _lightMinMeta),
      );
    } else if (isInserting) {
      context.missing(_lightMinMeta);
    }
    if (data.containsKey('deep_min')) {
      context.handle(
        _deepMinMeta,
        deepMin.isAcceptableOrUnknown(data['deep_min']!, _deepMinMeta),
      );
    } else if (isInserting) {
      context.missing(_deepMinMeta);
    }
    if (data.containsKey('wake_min')) {
      context.handle(
        _wakeMinMeta,
        wakeMin.isAcceptableOrUnknown(data['wake_min']!, _wakeMinMeta),
      );
    } else if (isInserting) {
      context.missing(_wakeMinMeta);
    }
    if (data.containsKey('stages_json')) {
      context.handle(
        _stagesJsonMeta,
        stagesJson.isAcceptableOrUnknown(data['stages_json']!, _stagesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_stagesJsonMeta);
    }
    if (data.containsKey('pushed_at_ms')) {
      context.handle(
        _pushedAtMsMeta,
        pushedAtMs.isAcceptableOrUnknown(
          data['pushed_at_ms']!,
          _pushedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {startMs};
  @override
  StoredSleepSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSleepSession(
      startMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_ms'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      isNap: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_nap'],
      )!,
      sleepStartMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_start_min'],
      )!,
      sleepEndMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sleep_end_min'],
      )!,
      avgHr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avg_hr'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      )!,
      remMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rem_min'],
      )!,
      lightMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}light_min'],
      )!,
      deepMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deep_min'],
      )!,
      wakeMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wake_min'],
      )!,
      stagesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stages_json'],
      )!,
      pushedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pushed_at_ms'],
      ),
    );
  }

  @override
  $SleepSessionsTable createAlias(String alias) {
    return $SleepSessionsTable(attachedDatabase, alias);
  }
}

class StoredSleepSession extends DataClass
    implements Insertable<StoredSleepSession> {
  /// The record's own session timestamp, epoch milliseconds. The key the strap
  /// itself deduplicates on, so it is the key here too.
  final int startMs;

  /// The owner-local calendar date the session started on.
  final String day;

  /// True for a daytime nap block rather than the main night.
  final bool isNap;

  /// Sleep onset, minutes from (midnight − 24 h), as the record encodes it.
  final int sleepStartMin;

  /// Wake, in the same units.
  final int sleepEndMin;

  /// The device's average heart rate for the night. 0 for naps — the record
  /// carries no per-nap average and inventing one would be a made-up number.
  final int avgHr;

  /// **The device's own sleep score**, 0 for naps.
  ///
  /// Stored and shown attributed to the strap. It is NOT Healthee's sleep-health
  /// score, which is the four-dimension judgement the server derives — the app
  /// must never present one as the other.
  final int score;

  /// REM minutes, as the device summed them.
  final int remMin;

  /// Light-sleep minutes.
  final int lightMin;

  /// Deep-sleep minutes.
  final int deepMin;

  /// Awake minutes inside the session.
  final int wakeMin;

  /// The stage timeline as `[[startMs, endMs, type], …]` JSON.
  final String stagesJson;

  /// When the push accepted this night, epoch ms; null while it is pending.
  ///
  /// **Cleared whenever the row is re-written.** The fetch plan re-reads two
  /// days of sleep on purpose so a nap appended later is picked up, and a night
  /// that gained stages after it was pushed is a different record under the same
  /// key. Three nights re-sent per sync is nothing; a night whose second half
  /// never reaches the server is a hole nobody would see.
  final int? pushedAtMs;
  const StoredSleepSession({
    required this.startMs,
    required this.day,
    required this.isNap,
    required this.sleepStartMin,
    required this.sleepEndMin,
    required this.avgHr,
    required this.score,
    required this.remMin,
    required this.lightMin,
    required this.deepMin,
    required this.wakeMin,
    required this.stagesJson,
    this.pushedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['start_ms'] = Variable<int>(startMs);
    map['day'] = Variable<String>(day);
    map['is_nap'] = Variable<bool>(isNap);
    map['sleep_start_min'] = Variable<int>(sleepStartMin);
    map['sleep_end_min'] = Variable<int>(sleepEndMin);
    map['avg_hr'] = Variable<int>(avgHr);
    map['score'] = Variable<int>(score);
    map['rem_min'] = Variable<int>(remMin);
    map['light_min'] = Variable<int>(lightMin);
    map['deep_min'] = Variable<int>(deepMin);
    map['wake_min'] = Variable<int>(wakeMin);
    map['stages_json'] = Variable<String>(stagesJson);
    if (!nullToAbsent || pushedAtMs != null) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs);
    }
    return map;
  }

  SleepSessionsCompanion toCompanion(bool nullToAbsent) {
    return SleepSessionsCompanion(
      startMs: Value(startMs),
      day: Value(day),
      isNap: Value(isNap),
      sleepStartMin: Value(sleepStartMin),
      sleepEndMin: Value(sleepEndMin),
      avgHr: Value(avgHr),
      score: Value(score),
      remMin: Value(remMin),
      lightMin: Value(lightMin),
      deepMin: Value(deepMin),
      wakeMin: Value(wakeMin),
      stagesJson: Value(stagesJson),
      pushedAtMs: pushedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(pushedAtMs),
    );
  }

  factory StoredSleepSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSleepSession(
      startMs: serializer.fromJson<int>(json['startMs']),
      day: serializer.fromJson<String>(json['day']),
      isNap: serializer.fromJson<bool>(json['isNap']),
      sleepStartMin: serializer.fromJson<int>(json['sleepStartMin']),
      sleepEndMin: serializer.fromJson<int>(json['sleepEndMin']),
      avgHr: serializer.fromJson<int>(json['avgHr']),
      score: serializer.fromJson<int>(json['score']),
      remMin: serializer.fromJson<int>(json['remMin']),
      lightMin: serializer.fromJson<int>(json['lightMin']),
      deepMin: serializer.fromJson<int>(json['deepMin']),
      wakeMin: serializer.fromJson<int>(json['wakeMin']),
      stagesJson: serializer.fromJson<String>(json['stagesJson']),
      pushedAtMs: serializer.fromJson<int?>(json['pushedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'startMs': serializer.toJson<int>(startMs),
      'day': serializer.toJson<String>(day),
      'isNap': serializer.toJson<bool>(isNap),
      'sleepStartMin': serializer.toJson<int>(sleepStartMin),
      'sleepEndMin': serializer.toJson<int>(sleepEndMin),
      'avgHr': serializer.toJson<int>(avgHr),
      'score': serializer.toJson<int>(score),
      'remMin': serializer.toJson<int>(remMin),
      'lightMin': serializer.toJson<int>(lightMin),
      'deepMin': serializer.toJson<int>(deepMin),
      'wakeMin': serializer.toJson<int>(wakeMin),
      'stagesJson': serializer.toJson<String>(stagesJson),
      'pushedAtMs': serializer.toJson<int?>(pushedAtMs),
    };
  }

  StoredSleepSession copyWith({
    int? startMs,
    String? day,
    bool? isNap,
    int? sleepStartMin,
    int? sleepEndMin,
    int? avgHr,
    int? score,
    int? remMin,
    int? lightMin,
    int? deepMin,
    int? wakeMin,
    String? stagesJson,
    Value<int?> pushedAtMs = const Value.absent(),
  }) => StoredSleepSession(
    startMs: startMs ?? this.startMs,
    day: day ?? this.day,
    isNap: isNap ?? this.isNap,
    sleepStartMin: sleepStartMin ?? this.sleepStartMin,
    sleepEndMin: sleepEndMin ?? this.sleepEndMin,
    avgHr: avgHr ?? this.avgHr,
    score: score ?? this.score,
    remMin: remMin ?? this.remMin,
    lightMin: lightMin ?? this.lightMin,
    deepMin: deepMin ?? this.deepMin,
    wakeMin: wakeMin ?? this.wakeMin,
    stagesJson: stagesJson ?? this.stagesJson,
    pushedAtMs: pushedAtMs.present ? pushedAtMs.value : this.pushedAtMs,
  );
  StoredSleepSession copyWithCompanion(SleepSessionsCompanion data) {
    return StoredSleepSession(
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      day: data.day.present ? data.day.value : this.day,
      isNap: data.isNap.present ? data.isNap.value : this.isNap,
      sleepStartMin: data.sleepStartMin.present
          ? data.sleepStartMin.value
          : this.sleepStartMin,
      sleepEndMin: data.sleepEndMin.present
          ? data.sleepEndMin.value
          : this.sleepEndMin,
      avgHr: data.avgHr.present ? data.avgHr.value : this.avgHr,
      score: data.score.present ? data.score.value : this.score,
      remMin: data.remMin.present ? data.remMin.value : this.remMin,
      lightMin: data.lightMin.present ? data.lightMin.value : this.lightMin,
      deepMin: data.deepMin.present ? data.deepMin.value : this.deepMin,
      wakeMin: data.wakeMin.present ? data.wakeMin.value : this.wakeMin,
      stagesJson: data.stagesJson.present
          ? data.stagesJson.value
          : this.stagesJson,
      pushedAtMs: data.pushedAtMs.present
          ? data.pushedAtMs.value
          : this.pushedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSleepSession(')
          ..write('startMs: $startMs, ')
          ..write('day: $day, ')
          ..write('isNap: $isNap, ')
          ..write('sleepStartMin: $sleepStartMin, ')
          ..write('sleepEndMin: $sleepEndMin, ')
          ..write('avgHr: $avgHr, ')
          ..write('score: $score, ')
          ..write('remMin: $remMin, ')
          ..write('lightMin: $lightMin, ')
          ..write('deepMin: $deepMin, ')
          ..write('wakeMin: $wakeMin, ')
          ..write('stagesJson: $stagesJson, ')
          ..write('pushedAtMs: $pushedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    startMs,
    day,
    isNap,
    sleepStartMin,
    sleepEndMin,
    avgHr,
    score,
    remMin,
    lightMin,
    deepMin,
    wakeMin,
    stagesJson,
    pushedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSleepSession &&
          other.startMs == this.startMs &&
          other.day == this.day &&
          other.isNap == this.isNap &&
          other.sleepStartMin == this.sleepStartMin &&
          other.sleepEndMin == this.sleepEndMin &&
          other.avgHr == this.avgHr &&
          other.score == this.score &&
          other.remMin == this.remMin &&
          other.lightMin == this.lightMin &&
          other.deepMin == this.deepMin &&
          other.wakeMin == this.wakeMin &&
          other.stagesJson == this.stagesJson &&
          other.pushedAtMs == this.pushedAtMs);
}

class SleepSessionsCompanion extends UpdateCompanion<StoredSleepSession> {
  final Value<int> startMs;
  final Value<String> day;
  final Value<bool> isNap;
  final Value<int> sleepStartMin;
  final Value<int> sleepEndMin;
  final Value<int> avgHr;
  final Value<int> score;
  final Value<int> remMin;
  final Value<int> lightMin;
  final Value<int> deepMin;
  final Value<int> wakeMin;
  final Value<String> stagesJson;
  final Value<int?> pushedAtMs;
  const SleepSessionsCompanion({
    this.startMs = const Value.absent(),
    this.day = const Value.absent(),
    this.isNap = const Value.absent(),
    this.sleepStartMin = const Value.absent(),
    this.sleepEndMin = const Value.absent(),
    this.avgHr = const Value.absent(),
    this.score = const Value.absent(),
    this.remMin = const Value.absent(),
    this.lightMin = const Value.absent(),
    this.deepMin = const Value.absent(),
    this.wakeMin = const Value.absent(),
    this.stagesJson = const Value.absent(),
    this.pushedAtMs = const Value.absent(),
  });
  SleepSessionsCompanion.insert({
    this.startMs = const Value.absent(),
    required String day,
    required bool isNap,
    required int sleepStartMin,
    required int sleepEndMin,
    required int avgHr,
    required int score,
    required int remMin,
    required int lightMin,
    required int deepMin,
    required int wakeMin,
    required String stagesJson,
    this.pushedAtMs = const Value.absent(),
  }) : day = Value(day),
       isNap = Value(isNap),
       sleepStartMin = Value(sleepStartMin),
       sleepEndMin = Value(sleepEndMin),
       avgHr = Value(avgHr),
       score = Value(score),
       remMin = Value(remMin),
       lightMin = Value(lightMin),
       deepMin = Value(deepMin),
       wakeMin = Value(wakeMin),
       stagesJson = Value(stagesJson);
  static Insertable<StoredSleepSession> custom({
    Expression<int>? startMs,
    Expression<String>? day,
    Expression<bool>? isNap,
    Expression<int>? sleepStartMin,
    Expression<int>? sleepEndMin,
    Expression<int>? avgHr,
    Expression<int>? score,
    Expression<int>? remMin,
    Expression<int>? lightMin,
    Expression<int>? deepMin,
    Expression<int>? wakeMin,
    Expression<String>? stagesJson,
    Expression<int>? pushedAtMs,
  }) {
    return RawValuesInsertable({
      if (startMs != null) 'start_ms': startMs,
      if (day != null) 'day': day,
      if (isNap != null) 'is_nap': isNap,
      if (sleepStartMin != null) 'sleep_start_min': sleepStartMin,
      if (sleepEndMin != null) 'sleep_end_min': sleepEndMin,
      if (avgHr != null) 'avg_hr': avgHr,
      if (score != null) 'score': score,
      if (remMin != null) 'rem_min': remMin,
      if (lightMin != null) 'light_min': lightMin,
      if (deepMin != null) 'deep_min': deepMin,
      if (wakeMin != null) 'wake_min': wakeMin,
      if (stagesJson != null) 'stages_json': stagesJson,
      if (pushedAtMs != null) 'pushed_at_ms': pushedAtMs,
    });
  }

  SleepSessionsCompanion copyWith({
    Value<int>? startMs,
    Value<String>? day,
    Value<bool>? isNap,
    Value<int>? sleepStartMin,
    Value<int>? sleepEndMin,
    Value<int>? avgHr,
    Value<int>? score,
    Value<int>? remMin,
    Value<int>? lightMin,
    Value<int>? deepMin,
    Value<int>? wakeMin,
    Value<String>? stagesJson,
    Value<int?>? pushedAtMs,
  }) {
    return SleepSessionsCompanion(
      startMs: startMs ?? this.startMs,
      day: day ?? this.day,
      isNap: isNap ?? this.isNap,
      sleepStartMin: sleepStartMin ?? this.sleepStartMin,
      sleepEndMin: sleepEndMin ?? this.sleepEndMin,
      avgHr: avgHr ?? this.avgHr,
      score: score ?? this.score,
      remMin: remMin ?? this.remMin,
      lightMin: lightMin ?? this.lightMin,
      deepMin: deepMin ?? this.deepMin,
      wakeMin: wakeMin ?? this.wakeMin,
      stagesJson: stagesJson ?? this.stagesJson,
      pushedAtMs: pushedAtMs ?? this.pushedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (isNap.present) {
      map['is_nap'] = Variable<bool>(isNap.value);
    }
    if (sleepStartMin.present) {
      map['sleep_start_min'] = Variable<int>(sleepStartMin.value);
    }
    if (sleepEndMin.present) {
      map['sleep_end_min'] = Variable<int>(sleepEndMin.value);
    }
    if (avgHr.present) {
      map['avg_hr'] = Variable<int>(avgHr.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (remMin.present) {
      map['rem_min'] = Variable<int>(remMin.value);
    }
    if (lightMin.present) {
      map['light_min'] = Variable<int>(lightMin.value);
    }
    if (deepMin.present) {
      map['deep_min'] = Variable<int>(deepMin.value);
    }
    if (wakeMin.present) {
      map['wake_min'] = Variable<int>(wakeMin.value);
    }
    if (stagesJson.present) {
      map['stages_json'] = Variable<String>(stagesJson.value);
    }
    if (pushedAtMs.present) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SleepSessionsCompanion(')
          ..write('startMs: $startMs, ')
          ..write('day: $day, ')
          ..write('isNap: $isNap, ')
          ..write('sleepStartMin: $sleepStartMin, ')
          ..write('sleepEndMin: $sleepEndMin, ')
          ..write('avgHr: $avgHr, ')
          ..write('score: $score, ')
          ..write('remMin: $remMin, ')
          ..write('lightMin: $lightMin, ')
          ..write('deepMin: $deepMin, ')
          ..write('wakeMin: $wakeMin, ')
          ..write('stagesJson: $stagesJson, ')
          ..write('pushedAtMs: $pushedAtMs')
          ..write(')'))
        .toString();
  }
}

class $StoredWorkoutsTable extends StoredWorkouts
    with TableInfo<$StoredWorkoutsTable, StoredWorkout> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredWorkoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _startMsMeta = const VerificationMeta(
    'startMs',
  );
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
    'start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 10,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sportTypeMeta = const VerificationMeta(
    'sportType',
  );
  @override
  late final GeneratedColumn<int> sportType = GeneratedColumn<int>(
    'sport_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _caloriesMeta = const VerificationMeta(
    'calories',
  );
  @override
  late final GeneratedColumn<int> calories = GeneratedColumn<int>(
    'calories',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avgHrMeta = const VerificationMeta('avgHr');
  @override
  late final GeneratedColumn<int> avgHr = GeneratedColumn<int>(
    'avg_hr',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxHrMeta = const VerificationMeta('maxHr');
  @override
  late final GeneratedColumn<int> maxHr = GeneratedColumn<int>(
    'max_hr',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minHrMeta = const VerificationMeta('minHr');
  @override
  late final GeneratedColumn<int> minHr = GeneratedColumn<int>(
    'min_hr',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pushedAtMsMeta = const VerificationMeta(
    'pushedAtMs',
  );
  @override
  late final GeneratedColumn<int> pushedAtMs = GeneratedColumn<int>(
    'pushed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    startMs,
    day,
    sportType,
    durationSec,
    calories,
    avgHr,
    maxHr,
    minHr,
    pushedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_workouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredWorkout> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('start_ms')) {
      context.handle(
        _startMsMeta,
        startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta),
      );
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('sport_type')) {
      context.handle(
        _sportTypeMeta,
        sportType.isAcceptableOrUnknown(data['sport_type']!, _sportTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sportTypeMeta);
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecMeta);
    }
    if (data.containsKey('calories')) {
      context.handle(
        _caloriesMeta,
        calories.isAcceptableOrUnknown(data['calories']!, _caloriesMeta),
      );
    } else if (isInserting) {
      context.missing(_caloriesMeta);
    }
    if (data.containsKey('avg_hr')) {
      context.handle(
        _avgHrMeta,
        avgHr.isAcceptableOrUnknown(data['avg_hr']!, _avgHrMeta),
      );
    } else if (isInserting) {
      context.missing(_avgHrMeta);
    }
    if (data.containsKey('max_hr')) {
      context.handle(
        _maxHrMeta,
        maxHr.isAcceptableOrUnknown(data['max_hr']!, _maxHrMeta),
      );
    } else if (isInserting) {
      context.missing(_maxHrMeta);
    }
    if (data.containsKey('min_hr')) {
      context.handle(
        _minHrMeta,
        minHr.isAcceptableOrUnknown(data['min_hr']!, _minHrMeta),
      );
    } else if (isInserting) {
      context.missing(_minHrMeta);
    }
    if (data.containsKey('pushed_at_ms')) {
      context.handle(
        _pushedAtMsMeta,
        pushedAtMs.isAcceptableOrUnknown(
          data['pushed_at_ms']!,
          _pushedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {startMs};
  @override
  StoredWorkout map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredWorkout(
      startMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_ms'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      sportType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sport_type'],
      )!,
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      )!,
      calories: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calories'],
      )!,
      avgHr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avg_hr'],
      )!,
      maxHr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_hr'],
      )!,
      minHr: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_hr'],
      )!,
      pushedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pushed_at_ms'],
      ),
    );
  }

  @override
  $StoredWorkoutsTable createAlias(String alias) {
    return $StoredWorkoutsTable(attachedDatabase, alias);
  }
}

class StoredWorkout extends DataClass implements Insertable<StoredWorkout> {
  /// When the workout began, epoch milliseconds.
  final int startMs;

  /// The owner-local calendar date it began on.
  final String day;

  /// The device's sport-type code.
  final int sportType;

  /// Duration in seconds.
  final int durationSec;

  /// Calories as the DEVICE reported them. CLAUDE.md pins free-living energy to
  /// the server's MET-by-state model; this is the strap's figure, carried
  /// unaltered and labelled as the strap's.
  final int calories;

  /// Average heart rate over the workout.
  final int avgHr;

  /// Peak heart rate.
  final int maxHr;

  /// Lowest heart rate.
  final int minHr;

  /// When the push accepted this workout, epoch ms; null while it is pending.
  /// Cleared on re-write for the same reason a night's is.
  final int? pushedAtMs;
  const StoredWorkout({
    required this.startMs,
    required this.day,
    required this.sportType,
    required this.durationSec,
    required this.calories,
    required this.avgHr,
    required this.maxHr,
    required this.minHr,
    this.pushedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['start_ms'] = Variable<int>(startMs);
    map['day'] = Variable<String>(day);
    map['sport_type'] = Variable<int>(sportType);
    map['duration_sec'] = Variable<int>(durationSec);
    map['calories'] = Variable<int>(calories);
    map['avg_hr'] = Variable<int>(avgHr);
    map['max_hr'] = Variable<int>(maxHr);
    map['min_hr'] = Variable<int>(minHr);
    if (!nullToAbsent || pushedAtMs != null) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs);
    }
    return map;
  }

  StoredWorkoutsCompanion toCompanion(bool nullToAbsent) {
    return StoredWorkoutsCompanion(
      startMs: Value(startMs),
      day: Value(day),
      sportType: Value(sportType),
      durationSec: Value(durationSec),
      calories: Value(calories),
      avgHr: Value(avgHr),
      maxHr: Value(maxHr),
      minHr: Value(minHr),
      pushedAtMs: pushedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(pushedAtMs),
    );
  }

  factory StoredWorkout.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredWorkout(
      startMs: serializer.fromJson<int>(json['startMs']),
      day: serializer.fromJson<String>(json['day']),
      sportType: serializer.fromJson<int>(json['sportType']),
      durationSec: serializer.fromJson<int>(json['durationSec']),
      calories: serializer.fromJson<int>(json['calories']),
      avgHr: serializer.fromJson<int>(json['avgHr']),
      maxHr: serializer.fromJson<int>(json['maxHr']),
      minHr: serializer.fromJson<int>(json['minHr']),
      pushedAtMs: serializer.fromJson<int?>(json['pushedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'startMs': serializer.toJson<int>(startMs),
      'day': serializer.toJson<String>(day),
      'sportType': serializer.toJson<int>(sportType),
      'durationSec': serializer.toJson<int>(durationSec),
      'calories': serializer.toJson<int>(calories),
      'avgHr': serializer.toJson<int>(avgHr),
      'maxHr': serializer.toJson<int>(maxHr),
      'minHr': serializer.toJson<int>(minHr),
      'pushedAtMs': serializer.toJson<int?>(pushedAtMs),
    };
  }

  StoredWorkout copyWith({
    int? startMs,
    String? day,
    int? sportType,
    int? durationSec,
    int? calories,
    int? avgHr,
    int? maxHr,
    int? minHr,
    Value<int?> pushedAtMs = const Value.absent(),
  }) => StoredWorkout(
    startMs: startMs ?? this.startMs,
    day: day ?? this.day,
    sportType: sportType ?? this.sportType,
    durationSec: durationSec ?? this.durationSec,
    calories: calories ?? this.calories,
    avgHr: avgHr ?? this.avgHr,
    maxHr: maxHr ?? this.maxHr,
    minHr: minHr ?? this.minHr,
    pushedAtMs: pushedAtMs.present ? pushedAtMs.value : this.pushedAtMs,
  );
  StoredWorkout copyWithCompanion(StoredWorkoutsCompanion data) {
    return StoredWorkout(
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      day: data.day.present ? data.day.value : this.day,
      sportType: data.sportType.present ? data.sportType.value : this.sportType,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      calories: data.calories.present ? data.calories.value : this.calories,
      avgHr: data.avgHr.present ? data.avgHr.value : this.avgHr,
      maxHr: data.maxHr.present ? data.maxHr.value : this.maxHr,
      minHr: data.minHr.present ? data.minHr.value : this.minHr,
      pushedAtMs: data.pushedAtMs.present
          ? data.pushedAtMs.value
          : this.pushedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredWorkout(')
          ..write('startMs: $startMs, ')
          ..write('day: $day, ')
          ..write('sportType: $sportType, ')
          ..write('durationSec: $durationSec, ')
          ..write('calories: $calories, ')
          ..write('avgHr: $avgHr, ')
          ..write('maxHr: $maxHr, ')
          ..write('minHr: $minHr, ')
          ..write('pushedAtMs: $pushedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    startMs,
    day,
    sportType,
    durationSec,
    calories,
    avgHr,
    maxHr,
    minHr,
    pushedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredWorkout &&
          other.startMs == this.startMs &&
          other.day == this.day &&
          other.sportType == this.sportType &&
          other.durationSec == this.durationSec &&
          other.calories == this.calories &&
          other.avgHr == this.avgHr &&
          other.maxHr == this.maxHr &&
          other.minHr == this.minHr &&
          other.pushedAtMs == this.pushedAtMs);
}

class StoredWorkoutsCompanion extends UpdateCompanion<StoredWorkout> {
  final Value<int> startMs;
  final Value<String> day;
  final Value<int> sportType;
  final Value<int> durationSec;
  final Value<int> calories;
  final Value<int> avgHr;
  final Value<int> maxHr;
  final Value<int> minHr;
  final Value<int?> pushedAtMs;
  const StoredWorkoutsCompanion({
    this.startMs = const Value.absent(),
    this.day = const Value.absent(),
    this.sportType = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.calories = const Value.absent(),
    this.avgHr = const Value.absent(),
    this.maxHr = const Value.absent(),
    this.minHr = const Value.absent(),
    this.pushedAtMs = const Value.absent(),
  });
  StoredWorkoutsCompanion.insert({
    this.startMs = const Value.absent(),
    required String day,
    required int sportType,
    required int durationSec,
    required int calories,
    required int avgHr,
    required int maxHr,
    required int minHr,
    this.pushedAtMs = const Value.absent(),
  }) : day = Value(day),
       sportType = Value(sportType),
       durationSec = Value(durationSec),
       calories = Value(calories),
       avgHr = Value(avgHr),
       maxHr = Value(maxHr),
       minHr = Value(minHr);
  static Insertable<StoredWorkout> custom({
    Expression<int>? startMs,
    Expression<String>? day,
    Expression<int>? sportType,
    Expression<int>? durationSec,
    Expression<int>? calories,
    Expression<int>? avgHr,
    Expression<int>? maxHr,
    Expression<int>? minHr,
    Expression<int>? pushedAtMs,
  }) {
    return RawValuesInsertable({
      if (startMs != null) 'start_ms': startMs,
      if (day != null) 'day': day,
      if (sportType != null) 'sport_type': sportType,
      if (durationSec != null) 'duration_sec': durationSec,
      if (calories != null) 'calories': calories,
      if (avgHr != null) 'avg_hr': avgHr,
      if (maxHr != null) 'max_hr': maxHr,
      if (minHr != null) 'min_hr': minHr,
      if (pushedAtMs != null) 'pushed_at_ms': pushedAtMs,
    });
  }

  StoredWorkoutsCompanion copyWith({
    Value<int>? startMs,
    Value<String>? day,
    Value<int>? sportType,
    Value<int>? durationSec,
    Value<int>? calories,
    Value<int>? avgHr,
    Value<int>? maxHr,
    Value<int>? minHr,
    Value<int?>? pushedAtMs,
  }) {
    return StoredWorkoutsCompanion(
      startMs: startMs ?? this.startMs,
      day: day ?? this.day,
      sportType: sportType ?? this.sportType,
      durationSec: durationSec ?? this.durationSec,
      calories: calories ?? this.calories,
      avgHr: avgHr ?? this.avgHr,
      maxHr: maxHr ?? this.maxHr,
      minHr: minHr ?? this.minHr,
      pushedAtMs: pushedAtMs ?? this.pushedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (sportType.present) {
      map['sport_type'] = Variable<int>(sportType.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
    }
    if (calories.present) {
      map['calories'] = Variable<int>(calories.value);
    }
    if (avgHr.present) {
      map['avg_hr'] = Variable<int>(avgHr.value);
    }
    if (maxHr.present) {
      map['max_hr'] = Variable<int>(maxHr.value);
    }
    if (minHr.present) {
      map['min_hr'] = Variable<int>(minHr.value);
    }
    if (pushedAtMs.present) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredWorkoutsCompanion(')
          ..write('startMs: $startMs, ')
          ..write('day: $day, ')
          ..write('sportType: $sportType, ')
          ..write('durationSec: $durationSec, ')
          ..write('calories: $calories, ')
          ..write('avgHr: $avgHr, ')
          ..write('maxHr: $maxHr, ')
          ..write('minHr: $minHr, ')
          ..write('pushedAtMs: $pushedAtMs')
          ..write(')'))
        .toString();
  }
}

class $DeviceTotalsTable extends DeviceTotals
    with TableInfo<$DeviceTotalsTable, StoredDeviceTotals> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceTotalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 10,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepsMeta = const VerificationMeta('steps');
  @override
  late final GeneratedColumn<int> steps = GeneratedColumn<int>(
    'steps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<int> distanceM = GeneratedColumn<int>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _caloriesMeta = const VerificationMeta(
    'calories',
  );
  @override
  late final GeneratedColumn<int> calories = GeneratedColumn<int>(
    'calories',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readAtMsMeta = const VerificationMeta(
    'readAtMs',
  );
  @override
  late final GeneratedColumn<int> readAtMs = GeneratedColumn<int>(
    'read_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pushedAtMsMeta = const VerificationMeta(
    'pushedAtMs',
  );
  @override
  late final GeneratedColumn<int> pushedAtMs = GeneratedColumn<int>(
    'pushed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    day,
    steps,
    distanceM,
    calories,
    readAtMs,
    pushedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_totals';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredDeviceTotals> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('steps')) {
      context.handle(
        _stepsMeta,
        steps.isAcceptableOrUnknown(data['steps']!, _stepsMeta),
      );
    } else if (isInserting) {
      context.missing(_stepsMeta);
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    } else if (isInserting) {
      context.missing(_distanceMMeta);
    }
    if (data.containsKey('calories')) {
      context.handle(
        _caloriesMeta,
        calories.isAcceptableOrUnknown(data['calories']!, _caloriesMeta),
      );
    } else if (isInserting) {
      context.missing(_caloriesMeta);
    }
    if (data.containsKey('read_at_ms')) {
      context.handle(
        _readAtMsMeta,
        readAtMs.isAcceptableOrUnknown(data['read_at_ms']!, _readAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_readAtMsMeta);
    }
    if (data.containsKey('pushed_at_ms')) {
      context.handle(
        _pushedAtMsMeta,
        pushedAtMs.isAcceptableOrUnknown(
          data['pushed_at_ms']!,
          _pushedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day};
  @override
  StoredDeviceTotals map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredDeviceTotals(
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      steps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}steps'],
      )!,
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_m'],
      )!,
      calories: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calories'],
      )!,
      readAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_at_ms'],
      )!,
      pushedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pushed_at_ms'],
      ),
    );
  }

  @override
  $DeviceTotalsTable createAlias(String alias) {
    return $DeviceTotalsTable(attachedDatabase, alias);
  }
}

class StoredDeviceTotals extends DataClass
    implements Insertable<StoredDeviceTotals> {
  /// The owner-local calendar date these counters are for, `YYYY-MM-DD`.
  final String day;

  /// Steps since the strap's local midnight. The authoritative step total — the
  /// per-minute stream is, in the legacy code's own words, "possibly frozen /
  /// incomplete" on this firmware.
  final int steps;

  /// Distance in metres since midnight, as the strap computed it.
  final int distanceM;

  /// Calories since midnight, as the strap computed them.
  final int calories;

  /// When the reply landed, epoch milliseconds. A counter read at 09:00 is a
  /// claim about nine hours, not about a day, and the screen says so.
  final int readAtMs;

  /// When `POST /ingest/helio` accepted this row, epoch ms; null while pending.
  ///
  /// ## Why a per-row marker and not a "pushed up to here" cursor
  ///
  /// A high-water cursor is a second claim about what the server holds, and it
  /// is wrong in the direction that loses data. The one-shot stress and nap
  /// passes deliberately write rows OLDER than anything already stored; a cursor
  /// advanced past them would skip every one, permanently, and nothing would
  /// ever revisit them. The marker is on the row the push is about, so a
  /// backfilled row is pending by construction. It is the same argument
  /// `StrapWriter.resumeWindow` makes for the fetch watermark, in the other
  /// direction.
  ///
  /// **Cleared on every re-write**, because this counter is live: it grows all
  /// day under one primary key, so the 09:00 reading being pushed says nothing
  /// about the 21:00 one.
  final int? pushedAtMs;
  const StoredDeviceTotals({
    required this.day,
    required this.steps,
    required this.distanceM,
    required this.calories,
    required this.readAtMs,
    this.pushedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['steps'] = Variable<int>(steps);
    map['distance_m'] = Variable<int>(distanceM);
    map['calories'] = Variable<int>(calories);
    map['read_at_ms'] = Variable<int>(readAtMs);
    if (!nullToAbsent || pushedAtMs != null) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs);
    }
    return map;
  }

  DeviceTotalsCompanion toCompanion(bool nullToAbsent) {
    return DeviceTotalsCompanion(
      day: Value(day),
      steps: Value(steps),
      distanceM: Value(distanceM),
      calories: Value(calories),
      readAtMs: Value(readAtMs),
      pushedAtMs: pushedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(pushedAtMs),
    );
  }

  factory StoredDeviceTotals.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredDeviceTotals(
      day: serializer.fromJson<String>(json['day']),
      steps: serializer.fromJson<int>(json['steps']),
      distanceM: serializer.fromJson<int>(json['distanceM']),
      calories: serializer.fromJson<int>(json['calories']),
      readAtMs: serializer.fromJson<int>(json['readAtMs']),
      pushedAtMs: serializer.fromJson<int?>(json['pushedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'steps': serializer.toJson<int>(steps),
      'distanceM': serializer.toJson<int>(distanceM),
      'calories': serializer.toJson<int>(calories),
      'readAtMs': serializer.toJson<int>(readAtMs),
      'pushedAtMs': serializer.toJson<int?>(pushedAtMs),
    };
  }

  StoredDeviceTotals copyWith({
    String? day,
    int? steps,
    int? distanceM,
    int? calories,
    int? readAtMs,
    Value<int?> pushedAtMs = const Value.absent(),
  }) => StoredDeviceTotals(
    day: day ?? this.day,
    steps: steps ?? this.steps,
    distanceM: distanceM ?? this.distanceM,
    calories: calories ?? this.calories,
    readAtMs: readAtMs ?? this.readAtMs,
    pushedAtMs: pushedAtMs.present ? pushedAtMs.value : this.pushedAtMs,
  );
  StoredDeviceTotals copyWithCompanion(DeviceTotalsCompanion data) {
    return StoredDeviceTotals(
      day: data.day.present ? data.day.value : this.day,
      steps: data.steps.present ? data.steps.value : this.steps,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      calories: data.calories.present ? data.calories.value : this.calories,
      readAtMs: data.readAtMs.present ? data.readAtMs.value : this.readAtMs,
      pushedAtMs: data.pushedAtMs.present
          ? data.pushedAtMs.value
          : this.pushedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredDeviceTotals(')
          ..write('day: $day, ')
          ..write('steps: $steps, ')
          ..write('distanceM: $distanceM, ')
          ..write('calories: $calories, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('pushedAtMs: $pushedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(day, steps, distanceM, calories, readAtMs, pushedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredDeviceTotals &&
          other.day == this.day &&
          other.steps == this.steps &&
          other.distanceM == this.distanceM &&
          other.calories == this.calories &&
          other.readAtMs == this.readAtMs &&
          other.pushedAtMs == this.pushedAtMs);
}

class DeviceTotalsCompanion extends UpdateCompanion<StoredDeviceTotals> {
  final Value<String> day;
  final Value<int> steps;
  final Value<int> distanceM;
  final Value<int> calories;
  final Value<int> readAtMs;
  final Value<int?> pushedAtMs;
  final Value<int> rowid;
  const DeviceTotalsCompanion({
    this.day = const Value.absent(),
    this.steps = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.calories = const Value.absent(),
    this.readAtMs = const Value.absent(),
    this.pushedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceTotalsCompanion.insert({
    required String day,
    required int steps,
    required int distanceM,
    required int calories,
    required int readAtMs,
    this.pushedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : day = Value(day),
       steps = Value(steps),
       distanceM = Value(distanceM),
       calories = Value(calories),
       readAtMs = Value(readAtMs);
  static Insertable<StoredDeviceTotals> custom({
    Expression<String>? day,
    Expression<int>? steps,
    Expression<int>? distanceM,
    Expression<int>? calories,
    Expression<int>? readAtMs,
    Expression<int>? pushedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (steps != null) 'steps': steps,
      if (distanceM != null) 'distance_m': distanceM,
      if (calories != null) 'calories': calories,
      if (readAtMs != null) 'read_at_ms': readAtMs,
      if (pushedAtMs != null) 'pushed_at_ms': pushedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceTotalsCompanion copyWith({
    Value<String>? day,
    Value<int>? steps,
    Value<int>? distanceM,
    Value<int>? calories,
    Value<int>? readAtMs,
    Value<int?>? pushedAtMs,
    Value<int>? rowid,
  }) {
    return DeviceTotalsCompanion(
      day: day ?? this.day,
      steps: steps ?? this.steps,
      distanceM: distanceM ?? this.distanceM,
      calories: calories ?? this.calories,
      readAtMs: readAtMs ?? this.readAtMs,
      pushedAtMs: pushedAtMs ?? this.pushedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (steps.present) {
      map['steps'] = Variable<int>(steps.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<int>(distanceM.value);
    }
    if (calories.present) {
      map['calories'] = Variable<int>(calories.value);
    }
    if (readAtMs.present) {
      map['read_at_ms'] = Variable<int>(readAtMs.value);
    }
    if (pushedAtMs.present) {
      map['pushed_at_ms'] = Variable<int>(pushedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceTotalsCompanion(')
          ..write('day: $day, ')
          ..write('steps: $steps, ')
          ..write('distanceM: $distanceM, ')
          ..write('calories: $calories, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('pushedAtMs: $pushedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [name, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  SyncMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaRow(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaRow extends DataClass implements Insertable<SyncMetaRow> {
  /// The fact's name. See `SyncKeys` in `strap_writer.dart`.
  final String name;

  /// Its value, as text. Callers parse; the table stores.
  final String value;
  const SyncMetaRow({required this.name, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(name: Value(name), value: Value(value));
  }

  factory SyncMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaRow(
      name: serializer.fromJson<String>(json['name']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncMetaRow copyWith({String? name, String? value}) =>
      SyncMetaRow(name: name ?? this.name, value: value ?? this.value);
  SyncMetaRow copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaRow(
      name: data.name.present ? data.name.value : this.name,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('name: $name, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.name == this.name &&
          other.value == this.value);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<String> name;
  final Value<String> value;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.name = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    required String name,
    required String value,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       value = Value(value);
  static Insertable<SyncMetaRow> custom({
    Expression<String>? name,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String>? name,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      name: name ?? this.name,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('name: $name, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GpsRecordingsTable extends GpsRecordings
    with TableInfo<$GpsRecordingsTable, GpsRecordingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GpsRecordingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMsMeta = const VerificationMeta(
    'startMs',
  );
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
    'start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endMsMeta = const VerificationMeta('endMs');
  @override
  late final GeneratedColumn<int> endMs = GeneratedColumn<int>(
    'end_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scope,
    startMs,
    endMs,
    status,
    distanceM,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gps_recordings';
  @override
  VerificationContext validateIntegrity(
    Insertable<GpsRecordingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('start_ms')) {
      context.handle(
        _startMsMeta,
        startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta),
      );
    } else if (isInserting) {
      context.missing(_startMsMeta);
    }
    if (data.containsKey('end_ms')) {
      context.handle(
        _endMsMeta,
        endMs.isAcceptableOrUnknown(data['end_ms']!, _endMsMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GpsRecordingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GpsRecordingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      startMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_ms'],
      )!,
      endMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_ms'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      )!,
    );
  }

  @override
  $GpsRecordingsTable createAlias(String alias) {
    return $GpsRecordingsTable(attachedDatabase, alias);
  }
}

class GpsRecordingRow extends DataClass implements Insertable<GpsRecordingRow> {
  final String id;
  final String scope;
  final int startMs;
  final int? endMs;
  final String status;
  final double distanceM;
  const GpsRecordingRow({
    required this.id,
    required this.scope,
    required this.startMs,
    this.endMs,
    required this.status,
    required this.distanceM,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['scope'] = Variable<String>(scope);
    map['start_ms'] = Variable<int>(startMs);
    if (!nullToAbsent || endMs != null) {
      map['end_ms'] = Variable<int>(endMs);
    }
    map['status'] = Variable<String>(status);
    map['distance_m'] = Variable<double>(distanceM);
    return map;
  }

  GpsRecordingsCompanion toCompanion(bool nullToAbsent) {
    return GpsRecordingsCompanion(
      id: Value(id),
      scope: Value(scope),
      startMs: Value(startMs),
      endMs: endMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endMs),
      status: Value(status),
      distanceM: Value(distanceM),
    );
  }

  factory GpsRecordingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GpsRecordingRow(
      id: serializer.fromJson<String>(json['id']),
      scope: serializer.fromJson<String>(json['scope']),
      startMs: serializer.fromJson<int>(json['startMs']),
      endMs: serializer.fromJson<int?>(json['endMs']),
      status: serializer.fromJson<String>(json['status']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scope': serializer.toJson<String>(scope),
      'startMs': serializer.toJson<int>(startMs),
      'endMs': serializer.toJson<int?>(endMs),
      'status': serializer.toJson<String>(status),
      'distanceM': serializer.toJson<double>(distanceM),
    };
  }

  GpsRecordingRow copyWith({
    String? id,
    String? scope,
    int? startMs,
    Value<int?> endMs = const Value.absent(),
    String? status,
    double? distanceM,
  }) => GpsRecordingRow(
    id: id ?? this.id,
    scope: scope ?? this.scope,
    startMs: startMs ?? this.startMs,
    endMs: endMs.present ? endMs.value : this.endMs,
    status: status ?? this.status,
    distanceM: distanceM ?? this.distanceM,
  );
  GpsRecordingRow copyWithCompanion(GpsRecordingsCompanion data) {
    return GpsRecordingRow(
      id: data.id.present ? data.id.value : this.id,
      scope: data.scope.present ? data.scope.value : this.scope,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      status: data.status.present ? data.status.value : this.status,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GpsRecordingRow(')
          ..write('id: $id, ')
          ..write('scope: $scope, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('status: $status, ')
          ..write('distanceM: $distanceM')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, scope, startMs, endMs, status, distanceM);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GpsRecordingRow &&
          other.id == this.id &&
          other.scope == this.scope &&
          other.startMs == this.startMs &&
          other.endMs == this.endMs &&
          other.status == this.status &&
          other.distanceM == this.distanceM);
}

class GpsRecordingsCompanion extends UpdateCompanion<GpsRecordingRow> {
  final Value<String> id;
  final Value<String> scope;
  final Value<int> startMs;
  final Value<int?> endMs;
  final Value<String> status;
  final Value<double> distanceM;
  final Value<int> rowid;
  const GpsRecordingsCompanion({
    this.id = const Value.absent(),
    this.scope = const Value.absent(),
    this.startMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.status = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GpsRecordingsCompanion.insert({
    required String id,
    required String scope,
    required int startMs,
    this.endMs = const Value.absent(),
    required String status,
    this.distanceM = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       scope = Value(scope),
       startMs = Value(startMs),
       status = Value(status);
  static Insertable<GpsRecordingRow> custom({
    Expression<String>? id,
    Expression<String>? scope,
    Expression<int>? startMs,
    Expression<int>? endMs,
    Expression<String>? status,
    Expression<double>? distanceM,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scope != null) 'scope': scope,
      if (startMs != null) 'start_ms': startMs,
      if (endMs != null) 'end_ms': endMs,
      if (status != null) 'status': status,
      if (distanceM != null) 'distance_m': distanceM,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GpsRecordingsCompanion copyWith({
    Value<String>? id,
    Value<String>? scope,
    Value<int>? startMs,
    Value<int?>? endMs,
    Value<String>? status,
    Value<double>? distanceM,
    Value<int>? rowid,
  }) {
    return GpsRecordingsCompanion(
      id: id ?? this.id,
      scope: scope ?? this.scope,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      status: status ?? this.status,
      distanceM: distanceM ?? this.distanceM,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (endMs.present) {
      map['end_ms'] = Variable<int>(endMs.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GpsRecordingsCompanion(')
          ..write('id: $id, ')
          ..write('scope: $scope, ')
          ..write('startMs: $startMs, ')
          ..write('endMs: $endMs, ')
          ..write('status: $status, ')
          ..write('distanceM: $distanceM, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GpsFixesTable extends GpsFixes
    with TableInfo<$GpsFixesTable, GpsFixRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GpsFixesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordingIdMeta = const VerificationMeta(
    'recordingId',
  );
  @override
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
    'recording_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMsMeta = const VerificationMeta('atMs');
  @override
  late final GeneratedColumn<int> atMs = GeneratedColumn<int>(
    'at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _altitudeMMeta = const VerificationMeta(
    'altitudeM',
  );
  @override
  late final GeneratedColumn<double> altitudeM = GeneratedColumn<double>(
    'altitude_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMMeta = const VerificationMeta(
    'accuracyM',
  );
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
    'accuracy_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordingId,
    atMs,
    latitude,
    longitude,
    altitudeM,
    accuracyM,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gps_fixes';
  @override
  VerificationContext validateIntegrity(
    Insertable<GpsFixRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('recording_id')) {
      context.handle(
        _recordingIdMeta,
        recordingId.isAcceptableOrUnknown(
          data['recording_id']!,
          _recordingIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordingIdMeta);
    }
    if (data.containsKey('at_ms')) {
      context.handle(
        _atMsMeta,
        atMs.isAcceptableOrUnknown(data['at_ms']!, _atMsMeta),
      );
    } else if (isInserting) {
      context.missing(_atMsMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('altitude_m')) {
      context.handle(
        _altitudeMMeta,
        altitudeM.isAcceptableOrUnknown(data['altitude_m']!, _altitudeMMeta),
      );
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(
        _accuracyMMeta,
        accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta),
      );
    } else if (isInserting) {
      context.missing(_accuracyMMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordingId, atMs};
  @override
  GpsFixRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GpsFixRow(
      recordingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recording_id'],
      )!,
      atMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at_ms'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      altitudeM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude_m'],
      ),
      accuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_m'],
      )!,
    );
  }

  @override
  $GpsFixesTable createAlias(String alias) {
    return $GpsFixesTable(attachedDatabase, alias);
  }
}

class GpsFixRow extends DataClass implements Insertable<GpsFixRow> {
  final String recordingId;
  final int atMs;
  final double latitude;
  final double longitude;
  final double? altitudeM;
  final double accuracyM;
  const GpsFixRow({
    required this.recordingId,
    required this.atMs,
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    required this.accuracyM,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['recording_id'] = Variable<String>(recordingId);
    map['at_ms'] = Variable<int>(atMs);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || altitudeM != null) {
      map['altitude_m'] = Variable<double>(altitudeM);
    }
    map['accuracy_m'] = Variable<double>(accuracyM);
    return map;
  }

  GpsFixesCompanion toCompanion(bool nullToAbsent) {
    return GpsFixesCompanion(
      recordingId: Value(recordingId),
      atMs: Value(atMs),
      latitude: Value(latitude),
      longitude: Value(longitude),
      altitudeM: altitudeM == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeM),
      accuracyM: Value(accuracyM),
    );
  }

  factory GpsFixRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GpsFixRow(
      recordingId: serializer.fromJson<String>(json['recordingId']),
      atMs: serializer.fromJson<int>(json['atMs']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      altitudeM: serializer.fromJson<double?>(json['altitudeM']),
      accuracyM: serializer.fromJson<double>(json['accuracyM']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordingId': serializer.toJson<String>(recordingId),
      'atMs': serializer.toJson<int>(atMs),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'altitudeM': serializer.toJson<double?>(altitudeM),
      'accuracyM': serializer.toJson<double>(accuracyM),
    };
  }

  GpsFixRow copyWith({
    String? recordingId,
    int? atMs,
    double? latitude,
    double? longitude,
    Value<double?> altitudeM = const Value.absent(),
    double? accuracyM,
  }) => GpsFixRow(
    recordingId: recordingId ?? this.recordingId,
    atMs: atMs ?? this.atMs,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    altitudeM: altitudeM.present ? altitudeM.value : this.altitudeM,
    accuracyM: accuracyM ?? this.accuracyM,
  );
  GpsFixRow copyWithCompanion(GpsFixesCompanion data) {
    return GpsFixRow(
      recordingId: data.recordingId.present
          ? data.recordingId.value
          : this.recordingId,
      atMs: data.atMs.present ? data.atMs.value : this.atMs,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitudeM: data.altitudeM.present ? data.altitudeM.value : this.altitudeM,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GpsFixRow(')
          ..write('recordingId: $recordingId, ')
          ..write('atMs: $atMs, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('accuracyM: $accuracyM')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(recordingId, atMs, latitude, longitude, altitudeM, accuracyM);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GpsFixRow &&
          other.recordingId == this.recordingId &&
          other.atMs == this.atMs &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitudeM == this.altitudeM &&
          other.accuracyM == this.accuracyM);
}

class GpsFixesCompanion extends UpdateCompanion<GpsFixRow> {
  final Value<String> recordingId;
  final Value<int> atMs;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> altitudeM;
  final Value<double> accuracyM;
  final Value<int> rowid;
  const GpsFixesCompanion({
    this.recordingId = const Value.absent(),
    this.atMs = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitudeM = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GpsFixesCompanion.insert({
    required String recordingId,
    required int atMs,
    required double latitude,
    required double longitude,
    this.altitudeM = const Value.absent(),
    required double accuracyM,
    this.rowid = const Value.absent(),
  }) : recordingId = Value(recordingId),
       atMs = Value(atMs),
       latitude = Value(latitude),
       longitude = Value(longitude),
       accuracyM = Value(accuracyM);
  static Insertable<GpsFixRow> custom({
    Expression<String>? recordingId,
    Expression<int>? atMs,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitudeM,
    Expression<double>? accuracyM,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordingId != null) 'recording_id': recordingId,
      if (atMs != null) 'at_ms': atMs,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitudeM != null) 'altitude_m': altitudeM,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GpsFixesCompanion copyWith({
    Value<String>? recordingId,
    Value<int>? atMs,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? altitudeM,
    Value<double>? accuracyM,
    Value<int>? rowid,
  }) {
    return GpsFixesCompanion(
      recordingId: recordingId ?? this.recordingId,
      atMs: atMs ?? this.atMs,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeM: altitudeM ?? this.altitudeM,
      accuracyM: accuracyM ?? this.accuracyM,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (atMs.present) {
      map['at_ms'] = Variable<int>(atMs.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitudeM.present) {
      map['altitude_m'] = Variable<double>(altitudeM.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GpsFixesCompanion(')
          ..write('recordingId: $recordingId, ')
          ..write('atMs: $atMs, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalStore extends GeneratedDatabase {
  _$LocalStore(QueryExecutor e) : super(e);
  $LocalStoreManager get managers => $LocalStoreManager(this);
  late final $CachedPayloadsTable cachedPayloads = $CachedPayloadsTable(this);
  late final $StrapSamplesTable strapSamples = $StrapSamplesTable(this);
  late final $SleepSessionsTable sleepSessions = $SleepSessionsTable(this);
  late final $StoredWorkoutsTable storedWorkouts = $StoredWorkoutsTable(this);
  late final $DeviceTotalsTable deviceTotals = $DeviceTotalsTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $GpsRecordingsTable gpsRecordings = $GpsRecordingsTable(this);
  late final $GpsFixesTable gpsFixes = $GpsFixesTable(this);
  late final StrapWriter strapWriter = StrapWriter(this as LocalStore);
  late final StrapReader strapReader = StrapReader(this as LocalStore);
  late final PushReader pushReader = PushReader(this as LocalStore);
  late final HorizonPrune horizonPrune = HorizonPrune(this as LocalStore);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedPayloads,
    strapSamples,
    sleepSessions,
    storedWorkouts,
    deviceTotals,
    syncMeta,
    gpsRecordings,
    gpsFixes,
  ];
}

typedef $$CachedPayloadsTableCreateCompanionBuilder =
    CachedPayloadsCompanion Function({
      Value<String> scope,
      required String day,
      required String metric,
      required String payload,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CachedPayloadsTableUpdateCompanionBuilder =
    CachedPayloadsCompanion Function({
      Value<String> scope,
      Value<String> day,
      Value<String> metric,
      Value<String> payload,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CachedPayloadsTableFilterComposer
    extends Composer<_$LocalStore, $CachedPayloadsTable> {
  $$CachedPayloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPayloadsTableOrderingComposer
    extends Composer<_$LocalStore, $CachedPayloadsTable> {
  $$CachedPayloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPayloadsTableAnnotationComposer
    extends Composer<_$LocalStore, $CachedPayloadsTable> {
  $$CachedPayloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get metric =>
      $composableBuilder(column: $table.metric, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CachedPayloadsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $CachedPayloadsTable,
          CachedPayload,
          $$CachedPayloadsTableFilterComposer,
          $$CachedPayloadsTableOrderingComposer,
          $$CachedPayloadsTableAnnotationComposer,
          $$CachedPayloadsTableCreateCompanionBuilder,
          $$CachedPayloadsTableUpdateCompanionBuilder,
          (
            CachedPayload,
            BaseReferences<_$LocalStore, $CachedPayloadsTable, CachedPayload>,
          ),
          CachedPayload,
          PrefetchHooks Function()
        > {
  $$CachedPayloadsTableTableManager(_$LocalStore db, $CachedPayloadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPayloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPayloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPayloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<String> metric = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPayloadsCompanion(
                scope: scope,
                day: day,
                metric: metric,
                payload: payload,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                required String day,
                required String metric,
                required String payload,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedPayloadsCompanion.insert(
                scope: scope,
                day: day,
                metric: metric,
                payload: payload,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPayloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $CachedPayloadsTable,
      CachedPayload,
      $$CachedPayloadsTableFilterComposer,
      $$CachedPayloadsTableOrderingComposer,
      $$CachedPayloadsTableAnnotationComposer,
      $$CachedPayloadsTableCreateCompanionBuilder,
      $$CachedPayloadsTableUpdateCompanionBuilder,
      (
        CachedPayload,
        BaseReferences<_$LocalStore, $CachedPayloadsTable, CachedPayload>,
      ),
      CachedPayload,
      PrefetchHooks Function()
    >;
typedef $$StrapSamplesTableCreateCompanionBuilder =
    StrapSamplesCompanion Function({
      required String metric,
      required int tsMs,
      required String day,
      required double value,
      Value<int?> pushedAtMs,
      Value<int> rowid,
    });
typedef $$StrapSamplesTableUpdateCompanionBuilder =
    StrapSamplesCompanion Function({
      Value<String> metric,
      Value<int> tsMs,
      Value<String> day,
      Value<double> value,
      Value<int?> pushedAtMs,
      Value<int> rowid,
    });

class $$StrapSamplesTableFilterComposer
    extends Composer<_$LocalStore, $StrapSamplesTable> {
  $$StrapSamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tsMs => $composableBuilder(
    column: $table.tsMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StrapSamplesTableOrderingComposer
    extends Composer<_$LocalStore, $StrapSamplesTable> {
  $$StrapSamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get metric => $composableBuilder(
    column: $table.metric,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tsMs => $composableBuilder(
    column: $table.tsMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StrapSamplesTableAnnotationComposer
    extends Composer<_$LocalStore, $StrapSamplesTable> {
  $$StrapSamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get metric =>
      $composableBuilder(column: $table.metric, builder: (column) => column);

  GeneratedColumn<int> get tsMs =>
      $composableBuilder(column: $table.tsMs, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => column,
  );
}

class $$StrapSamplesTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $StrapSamplesTable,
          StoredSample,
          $$StrapSamplesTableFilterComposer,
          $$StrapSamplesTableOrderingComposer,
          $$StrapSamplesTableAnnotationComposer,
          $$StrapSamplesTableCreateCompanionBuilder,
          $$StrapSamplesTableUpdateCompanionBuilder,
          (
            StoredSample,
            BaseReferences<_$LocalStore, $StrapSamplesTable, StoredSample>,
          ),
          StoredSample,
          PrefetchHooks Function()
        > {
  $$StrapSamplesTableTableManager(_$LocalStore db, $StrapSamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StrapSamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StrapSamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StrapSamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> metric = const Value.absent(),
                Value<int> tsMs = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<double> value = const Value.absent(),
                Value<int?> pushedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StrapSamplesCompanion(
                metric: metric,
                tsMs: tsMs,
                day: day,
                value: value,
                pushedAtMs: pushedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String metric,
                required int tsMs,
                required String day,
                required double value,
                Value<int?> pushedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StrapSamplesCompanion.insert(
                metric: metric,
                tsMs: tsMs,
                day: day,
                value: value,
                pushedAtMs: pushedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StrapSamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $StrapSamplesTable,
      StoredSample,
      $$StrapSamplesTableFilterComposer,
      $$StrapSamplesTableOrderingComposer,
      $$StrapSamplesTableAnnotationComposer,
      $$StrapSamplesTableCreateCompanionBuilder,
      $$StrapSamplesTableUpdateCompanionBuilder,
      (
        StoredSample,
        BaseReferences<_$LocalStore, $StrapSamplesTable, StoredSample>,
      ),
      StoredSample,
      PrefetchHooks Function()
    >;
typedef $$SleepSessionsTableCreateCompanionBuilder =
    SleepSessionsCompanion Function({
      Value<int> startMs,
      required String day,
      required bool isNap,
      required int sleepStartMin,
      required int sleepEndMin,
      required int avgHr,
      required int score,
      required int remMin,
      required int lightMin,
      required int deepMin,
      required int wakeMin,
      required String stagesJson,
      Value<int?> pushedAtMs,
    });
typedef $$SleepSessionsTableUpdateCompanionBuilder =
    SleepSessionsCompanion Function({
      Value<int> startMs,
      Value<String> day,
      Value<bool> isNap,
      Value<int> sleepStartMin,
      Value<int> sleepEndMin,
      Value<int> avgHr,
      Value<int> score,
      Value<int> remMin,
      Value<int> lightMin,
      Value<int> deepMin,
      Value<int> wakeMin,
      Value<String> stagesJson,
      Value<int?> pushedAtMs,
    });

class $$SleepSessionsTableFilterComposer
    extends Composer<_$LocalStore, $SleepSessionsTable> {
  $$SleepSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isNap => $composableBuilder(
    column: $table.isNap,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepStartMin => $composableBuilder(
    column: $table.sleepStartMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sleepEndMin => $composableBuilder(
    column: $table.sleepEndMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avgHr => $composableBuilder(
    column: $table.avgHr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remMin => $composableBuilder(
    column: $table.remMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lightMin => $composableBuilder(
    column: $table.lightMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deepMin => $composableBuilder(
    column: $table.deepMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wakeMin => $composableBuilder(
    column: $table.wakeMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stagesJson => $composableBuilder(
    column: $table.stagesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SleepSessionsTableOrderingComposer
    extends Composer<_$LocalStore, $SleepSessionsTable> {
  $$SleepSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isNap => $composableBuilder(
    column: $table.isNap,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepStartMin => $composableBuilder(
    column: $table.sleepStartMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sleepEndMin => $composableBuilder(
    column: $table.sleepEndMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avgHr => $composableBuilder(
    column: $table.avgHr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remMin => $composableBuilder(
    column: $table.remMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lightMin => $composableBuilder(
    column: $table.lightMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deepMin => $composableBuilder(
    column: $table.deepMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wakeMin => $composableBuilder(
    column: $table.wakeMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stagesJson => $composableBuilder(
    column: $table.stagesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SleepSessionsTableAnnotationComposer
    extends Composer<_$LocalStore, $SleepSessionsTable> {
  $$SleepSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<bool> get isNap =>
      $composableBuilder(column: $table.isNap, builder: (column) => column);

  GeneratedColumn<int> get sleepStartMin => $composableBuilder(
    column: $table.sleepStartMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sleepEndMin => $composableBuilder(
    column: $table.sleepEndMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get avgHr =>
      $composableBuilder(column: $table.avgHr, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get remMin =>
      $composableBuilder(column: $table.remMin, builder: (column) => column);

  GeneratedColumn<int> get lightMin =>
      $composableBuilder(column: $table.lightMin, builder: (column) => column);

  GeneratedColumn<int> get deepMin =>
      $composableBuilder(column: $table.deepMin, builder: (column) => column);

  GeneratedColumn<int> get wakeMin =>
      $composableBuilder(column: $table.wakeMin, builder: (column) => column);

  GeneratedColumn<String> get stagesJson => $composableBuilder(
    column: $table.stagesJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => column,
  );
}

class $$SleepSessionsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $SleepSessionsTable,
          StoredSleepSession,
          $$SleepSessionsTableFilterComposer,
          $$SleepSessionsTableOrderingComposer,
          $$SleepSessionsTableAnnotationComposer,
          $$SleepSessionsTableCreateCompanionBuilder,
          $$SleepSessionsTableUpdateCompanionBuilder,
          (
            StoredSleepSession,
            BaseReferences<
              _$LocalStore,
              $SleepSessionsTable,
              StoredSleepSession
            >,
          ),
          StoredSleepSession,
          PrefetchHooks Function()
        > {
  $$SleepSessionsTableTableManager(_$LocalStore db, $SleepSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SleepSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SleepSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SleepSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> startMs = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<bool> isNap = const Value.absent(),
                Value<int> sleepStartMin = const Value.absent(),
                Value<int> sleepEndMin = const Value.absent(),
                Value<int> avgHr = const Value.absent(),
                Value<int> score = const Value.absent(),
                Value<int> remMin = const Value.absent(),
                Value<int> lightMin = const Value.absent(),
                Value<int> deepMin = const Value.absent(),
                Value<int> wakeMin = const Value.absent(),
                Value<String> stagesJson = const Value.absent(),
                Value<int?> pushedAtMs = const Value.absent(),
              }) => SleepSessionsCompanion(
                startMs: startMs,
                day: day,
                isNap: isNap,
                sleepStartMin: sleepStartMin,
                sleepEndMin: sleepEndMin,
                avgHr: avgHr,
                score: score,
                remMin: remMin,
                lightMin: lightMin,
                deepMin: deepMin,
                wakeMin: wakeMin,
                stagesJson: stagesJson,
                pushedAtMs: pushedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> startMs = const Value.absent(),
                required String day,
                required bool isNap,
                required int sleepStartMin,
                required int sleepEndMin,
                required int avgHr,
                required int score,
                required int remMin,
                required int lightMin,
                required int deepMin,
                required int wakeMin,
                required String stagesJson,
                Value<int?> pushedAtMs = const Value.absent(),
              }) => SleepSessionsCompanion.insert(
                startMs: startMs,
                day: day,
                isNap: isNap,
                sleepStartMin: sleepStartMin,
                sleepEndMin: sleepEndMin,
                avgHr: avgHr,
                score: score,
                remMin: remMin,
                lightMin: lightMin,
                deepMin: deepMin,
                wakeMin: wakeMin,
                stagesJson: stagesJson,
                pushedAtMs: pushedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SleepSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $SleepSessionsTable,
      StoredSleepSession,
      $$SleepSessionsTableFilterComposer,
      $$SleepSessionsTableOrderingComposer,
      $$SleepSessionsTableAnnotationComposer,
      $$SleepSessionsTableCreateCompanionBuilder,
      $$SleepSessionsTableUpdateCompanionBuilder,
      (
        StoredSleepSession,
        BaseReferences<_$LocalStore, $SleepSessionsTable, StoredSleepSession>,
      ),
      StoredSleepSession,
      PrefetchHooks Function()
    >;
typedef $$StoredWorkoutsTableCreateCompanionBuilder =
    StoredWorkoutsCompanion Function({
      Value<int> startMs,
      required String day,
      required int sportType,
      required int durationSec,
      required int calories,
      required int avgHr,
      required int maxHr,
      required int minHr,
      Value<int?> pushedAtMs,
    });
typedef $$StoredWorkoutsTableUpdateCompanionBuilder =
    StoredWorkoutsCompanion Function({
      Value<int> startMs,
      Value<String> day,
      Value<int> sportType,
      Value<int> durationSec,
      Value<int> calories,
      Value<int> avgHr,
      Value<int> maxHr,
      Value<int> minHr,
      Value<int?> pushedAtMs,
    });

class $$StoredWorkoutsTableFilterComposer
    extends Composer<_$LocalStore, $StoredWorkoutsTable> {
  $$StoredWorkoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sportType => $composableBuilder(
    column: $table.sportType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avgHr => $composableBuilder(
    column: $table.avgHr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxHr => $composableBuilder(
    column: $table.maxHr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minHr => $composableBuilder(
    column: $table.minHr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredWorkoutsTableOrderingComposer
    extends Composer<_$LocalStore, $StoredWorkoutsTable> {
  $$StoredWorkoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sportType => $composableBuilder(
    column: $table.sportType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avgHr => $composableBuilder(
    column: $table.avgHr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxHr => $composableBuilder(
    column: $table.maxHr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minHr => $composableBuilder(
    column: $table.minHr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredWorkoutsTableAnnotationComposer
    extends Composer<_$LocalStore, $StoredWorkoutsTable> {
  $$StoredWorkoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get sportType =>
      $composableBuilder(column: $table.sportType, builder: (column) => column);

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get calories =>
      $composableBuilder(column: $table.calories, builder: (column) => column);

  GeneratedColumn<int> get avgHr =>
      $composableBuilder(column: $table.avgHr, builder: (column) => column);

  GeneratedColumn<int> get maxHr =>
      $composableBuilder(column: $table.maxHr, builder: (column) => column);

  GeneratedColumn<int> get minHr =>
      $composableBuilder(column: $table.minHr, builder: (column) => column);

  GeneratedColumn<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => column,
  );
}

class $$StoredWorkoutsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $StoredWorkoutsTable,
          StoredWorkout,
          $$StoredWorkoutsTableFilterComposer,
          $$StoredWorkoutsTableOrderingComposer,
          $$StoredWorkoutsTableAnnotationComposer,
          $$StoredWorkoutsTableCreateCompanionBuilder,
          $$StoredWorkoutsTableUpdateCompanionBuilder,
          (
            StoredWorkout,
            BaseReferences<_$LocalStore, $StoredWorkoutsTable, StoredWorkout>,
          ),
          StoredWorkout,
          PrefetchHooks Function()
        > {
  $$StoredWorkoutsTableTableManager(_$LocalStore db, $StoredWorkoutsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredWorkoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredWorkoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredWorkoutsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> startMs = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<int> sportType = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<int> calories = const Value.absent(),
                Value<int> avgHr = const Value.absent(),
                Value<int> maxHr = const Value.absent(),
                Value<int> minHr = const Value.absent(),
                Value<int?> pushedAtMs = const Value.absent(),
              }) => StoredWorkoutsCompanion(
                startMs: startMs,
                day: day,
                sportType: sportType,
                durationSec: durationSec,
                calories: calories,
                avgHr: avgHr,
                maxHr: maxHr,
                minHr: minHr,
                pushedAtMs: pushedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> startMs = const Value.absent(),
                required String day,
                required int sportType,
                required int durationSec,
                required int calories,
                required int avgHr,
                required int maxHr,
                required int minHr,
                Value<int?> pushedAtMs = const Value.absent(),
              }) => StoredWorkoutsCompanion.insert(
                startMs: startMs,
                day: day,
                sportType: sportType,
                durationSec: durationSec,
                calories: calories,
                avgHr: avgHr,
                maxHr: maxHr,
                minHr: minHr,
                pushedAtMs: pushedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredWorkoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $StoredWorkoutsTable,
      StoredWorkout,
      $$StoredWorkoutsTableFilterComposer,
      $$StoredWorkoutsTableOrderingComposer,
      $$StoredWorkoutsTableAnnotationComposer,
      $$StoredWorkoutsTableCreateCompanionBuilder,
      $$StoredWorkoutsTableUpdateCompanionBuilder,
      (
        StoredWorkout,
        BaseReferences<_$LocalStore, $StoredWorkoutsTable, StoredWorkout>,
      ),
      StoredWorkout,
      PrefetchHooks Function()
    >;
typedef $$DeviceTotalsTableCreateCompanionBuilder =
    DeviceTotalsCompanion Function({
      required String day,
      required int steps,
      required int distanceM,
      required int calories,
      required int readAtMs,
      Value<int?> pushedAtMs,
      Value<int> rowid,
    });
typedef $$DeviceTotalsTableUpdateCompanionBuilder =
    DeviceTotalsCompanion Function({
      Value<String> day,
      Value<int> steps,
      Value<int> distanceM,
      Value<int> calories,
      Value<int> readAtMs,
      Value<int?> pushedAtMs,
      Value<int> rowid,
    });

class $$DeviceTotalsTableFilterComposer
    extends Composer<_$LocalStore, $DeviceTotalsTable> {
  $$DeviceTotalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readAtMs => $composableBuilder(
    column: $table.readAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeviceTotalsTableOrderingComposer
    extends Composer<_$LocalStore, $DeviceTotalsTable> {
  $$DeviceTotalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get steps => $composableBuilder(
    column: $table.steps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calories => $composableBuilder(
    column: $table.calories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readAtMs => $composableBuilder(
    column: $table.readAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeviceTotalsTableAnnotationComposer
    extends Composer<_$LocalStore, $DeviceTotalsTable> {
  $$DeviceTotalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get steps =>
      $composableBuilder(column: $table.steps, builder: (column) => column);

  GeneratedColumn<int> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumn<int> get calories =>
      $composableBuilder(column: $table.calories, builder: (column) => column);

  GeneratedColumn<int> get readAtMs =>
      $composableBuilder(column: $table.readAtMs, builder: (column) => column);

  GeneratedColumn<int> get pushedAtMs => $composableBuilder(
    column: $table.pushedAtMs,
    builder: (column) => column,
  );
}

class $$DeviceTotalsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $DeviceTotalsTable,
          StoredDeviceTotals,
          $$DeviceTotalsTableFilterComposer,
          $$DeviceTotalsTableOrderingComposer,
          $$DeviceTotalsTableAnnotationComposer,
          $$DeviceTotalsTableCreateCompanionBuilder,
          $$DeviceTotalsTableUpdateCompanionBuilder,
          (
            StoredDeviceTotals,
            BaseReferences<
              _$LocalStore,
              $DeviceTotalsTable,
              StoredDeviceTotals
            >,
          ),
          StoredDeviceTotals,
          PrefetchHooks Function()
        > {
  $$DeviceTotalsTableTableManager(_$LocalStore db, $DeviceTotalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceTotalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceTotalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceTotalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<int> steps = const Value.absent(),
                Value<int> distanceM = const Value.absent(),
                Value<int> calories = const Value.absent(),
                Value<int> readAtMs = const Value.absent(),
                Value<int?> pushedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceTotalsCompanion(
                day: day,
                steps: steps,
                distanceM: distanceM,
                calories: calories,
                readAtMs: readAtMs,
                pushedAtMs: pushedAtMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                required int steps,
                required int distanceM,
                required int calories,
                required int readAtMs,
                Value<int?> pushedAtMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceTotalsCompanion.insert(
                day: day,
                steps: steps,
                distanceM: distanceM,
                calories: calories,
                readAtMs: readAtMs,
                pushedAtMs: pushedAtMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeviceTotalsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $DeviceTotalsTable,
      StoredDeviceTotals,
      $$DeviceTotalsTableFilterComposer,
      $$DeviceTotalsTableOrderingComposer,
      $$DeviceTotalsTableAnnotationComposer,
      $$DeviceTotalsTableCreateCompanionBuilder,
      $$DeviceTotalsTableUpdateCompanionBuilder,
      (
        StoredDeviceTotals,
        BaseReferences<_$LocalStore, $DeviceTotalsTable, StoredDeviceTotals>,
      ),
      StoredDeviceTotals,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      required String name,
      required String value,
      Value<int> rowid,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<String> name,
      Value<String> value,
      Value<int> rowid,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$LocalStore, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$LocalStore, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$LocalStore, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $SyncMetaTable,
          SyncMetaRow,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaRow,
            BaseReferences<_$LocalStore, $SyncMetaTable, SyncMetaRow>,
          ),
          SyncMetaRow,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$LocalStore db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(name: name, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String name,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                name: name,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $SyncMetaTable,
      SyncMetaRow,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (SyncMetaRow, BaseReferences<_$LocalStore, $SyncMetaTable, SyncMetaRow>),
      SyncMetaRow,
      PrefetchHooks Function()
    >;
typedef $$GpsRecordingsTableCreateCompanionBuilder =
    GpsRecordingsCompanion Function({
      required String id,
      required String scope,
      required int startMs,
      Value<int?> endMs,
      required String status,
      Value<double> distanceM,
      Value<int> rowid,
    });
typedef $$GpsRecordingsTableUpdateCompanionBuilder =
    GpsRecordingsCompanion Function({
      Value<String> id,
      Value<String> scope,
      Value<int> startMs,
      Value<int?> endMs,
      Value<String> status,
      Value<double> distanceM,
      Value<int> rowid,
    });

class $$GpsRecordingsTableFilterComposer
    extends Composer<_$LocalStore, $GpsRecordingsTable> {
  $$GpsRecordingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endMs => $composableBuilder(
    column: $table.endMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GpsRecordingsTableOrderingComposer
    extends Composer<_$LocalStore, $GpsRecordingsTable> {
  $$GpsRecordingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startMs => $composableBuilder(
    column: $table.startMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endMs => $composableBuilder(
    column: $table.endMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GpsRecordingsTableAnnotationComposer
    extends Composer<_$LocalStore, $GpsRecordingsTable> {
  $$GpsRecordingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get endMs =>
      $composableBuilder(column: $table.endMs, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);
}

class $$GpsRecordingsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $GpsRecordingsTable,
          GpsRecordingRow,
          $$GpsRecordingsTableFilterComposer,
          $$GpsRecordingsTableOrderingComposer,
          $$GpsRecordingsTableAnnotationComposer,
          $$GpsRecordingsTableCreateCompanionBuilder,
          $$GpsRecordingsTableUpdateCompanionBuilder,
          (
            GpsRecordingRow,
            BaseReferences<_$LocalStore, $GpsRecordingsTable, GpsRecordingRow>,
          ),
          GpsRecordingRow,
          PrefetchHooks Function()
        > {
  $$GpsRecordingsTableTableManager(_$LocalStore db, $GpsRecordingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GpsRecordingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GpsRecordingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GpsRecordingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<int> startMs = const Value.absent(),
                Value<int?> endMs = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GpsRecordingsCompanion(
                id: id,
                scope: scope,
                startMs: startMs,
                endMs: endMs,
                status: status,
                distanceM: distanceM,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String scope,
                required int startMs,
                Value<int?> endMs = const Value.absent(),
                required String status,
                Value<double> distanceM = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GpsRecordingsCompanion.insert(
                id: id,
                scope: scope,
                startMs: startMs,
                endMs: endMs,
                status: status,
                distanceM: distanceM,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GpsRecordingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $GpsRecordingsTable,
      GpsRecordingRow,
      $$GpsRecordingsTableFilterComposer,
      $$GpsRecordingsTableOrderingComposer,
      $$GpsRecordingsTableAnnotationComposer,
      $$GpsRecordingsTableCreateCompanionBuilder,
      $$GpsRecordingsTableUpdateCompanionBuilder,
      (
        GpsRecordingRow,
        BaseReferences<_$LocalStore, $GpsRecordingsTable, GpsRecordingRow>,
      ),
      GpsRecordingRow,
      PrefetchHooks Function()
    >;
typedef $$GpsFixesTableCreateCompanionBuilder =
    GpsFixesCompanion Function({
      required String recordingId,
      required int atMs,
      required double latitude,
      required double longitude,
      Value<double?> altitudeM,
      required double accuracyM,
      Value<int> rowid,
    });
typedef $$GpsFixesTableUpdateCompanionBuilder =
    GpsFixesCompanion Function({
      Value<String> recordingId,
      Value<int> atMs,
      Value<double> latitude,
      Value<double> longitude,
      Value<double?> altitudeM,
      Value<double> accuracyM,
      Value<int> rowid,
    });

class $$GpsFixesTableFilterComposer
    extends Composer<_$LocalStore, $GpsFixesTable> {
  $$GpsFixesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get altitudeM => $composableBuilder(
    column: $table.altitudeM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GpsFixesTableOrderingComposer
    extends Composer<_$LocalStore, $GpsFixesTable> {
  $$GpsFixesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atMs => $composableBuilder(
    column: $table.atMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get altitudeM => $composableBuilder(
    column: $table.altitudeM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GpsFixesTableAnnotationComposer
    extends Composer<_$LocalStore, $GpsFixesTable> {
  $$GpsFixesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get atMs =>
      $composableBuilder(column: $table.atMs, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get altitudeM =>
      $composableBuilder(column: $table.altitudeM, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);
}

class $$GpsFixesTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $GpsFixesTable,
          GpsFixRow,
          $$GpsFixesTableFilterComposer,
          $$GpsFixesTableOrderingComposer,
          $$GpsFixesTableAnnotationComposer,
          $$GpsFixesTableCreateCompanionBuilder,
          $$GpsFixesTableUpdateCompanionBuilder,
          (GpsFixRow, BaseReferences<_$LocalStore, $GpsFixesTable, GpsFixRow>),
          GpsFixRow,
          PrefetchHooks Function()
        > {
  $$GpsFixesTableTableManager(_$LocalStore db, $GpsFixesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GpsFixesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GpsFixesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GpsFixesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recordingId = const Value.absent(),
                Value<int> atMs = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<double?> altitudeM = const Value.absent(),
                Value<double> accuracyM = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GpsFixesCompanion(
                recordingId: recordingId,
                atMs: atMs,
                latitude: latitude,
                longitude: longitude,
                altitudeM: altitudeM,
                accuracyM: accuracyM,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordingId,
                required int atMs,
                required double latitude,
                required double longitude,
                Value<double?> altitudeM = const Value.absent(),
                required double accuracyM,
                Value<int> rowid = const Value.absent(),
              }) => GpsFixesCompanion.insert(
                recordingId: recordingId,
                atMs: atMs,
                latitude: latitude,
                longitude: longitude,
                altitudeM: altitudeM,
                accuracyM: accuracyM,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GpsFixesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $GpsFixesTable,
      GpsFixRow,
      $$GpsFixesTableFilterComposer,
      $$GpsFixesTableOrderingComposer,
      $$GpsFixesTableAnnotationComposer,
      $$GpsFixesTableCreateCompanionBuilder,
      $$GpsFixesTableUpdateCompanionBuilder,
      (GpsFixRow, BaseReferences<_$LocalStore, $GpsFixesTable, GpsFixRow>),
      GpsFixRow,
      PrefetchHooks Function()
    >;

class $LocalStoreManager {
  final _$LocalStore _db;
  $LocalStoreManager(this._db);
  $$CachedPayloadsTableTableManager get cachedPayloads =>
      $$CachedPayloadsTableTableManager(_db, _db.cachedPayloads);
  $$StrapSamplesTableTableManager get strapSamples =>
      $$StrapSamplesTableTableManager(_db, _db.strapSamples);
  $$SleepSessionsTableTableManager get sleepSessions =>
      $$SleepSessionsTableTableManager(_db, _db.sleepSessions);
  $$StoredWorkoutsTableTableManager get storedWorkouts =>
      $$StoredWorkoutsTableTableManager(_db, _db.storedWorkouts);
  $$DeviceTotalsTableTableManager get deviceTotals =>
      $$DeviceTotalsTableTableManager(_db, _db.deviceTotals);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$GpsRecordingsTableTableManager get gpsRecordings =>
      $$GpsRecordingsTableTableManager(_db, _db.gpsRecordings);
  $$GpsFixesTableTableManager get gpsFixes =>
      $$GpsFixesTableTableManager(_db, _db.gpsFixes);
}
