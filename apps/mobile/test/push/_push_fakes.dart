/// The one edge the push tests fake: the socket.
///
/// Everything above it is the real thing — a real in-memory SQLite store, the
/// real `PushReader`, the real `PushBatch.toJson`, the real dio client with its
/// real interceptors. What is replaced is `HttpClientAdapter`, the last hop
/// before the network, so the body these tests assert on is the body that would
/// have gone out on the wire.
///
/// Faking `PushClient` instead would have been easier and would have proved
/// less: the interesting bugs in a push live in the JSON, not in the call.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/secret_store.dart';
import 'package:healthee/data/push/push_client.dart';

/// A transport that records every request and answers however the test says.
class FakeIngestTransport implements HttpClientAdapter {
  /// [failWith] makes every request fail with that status; null means succeed.
  FakeIngestTransport({this.failWith, this.failFirst = 0, this.failAfter});

  /// The status to answer with instead of 200, or null to succeed.
  int? failWith;

  /// Fail only the first N requests, then succeed. For resume tests.
  int failFirst;

  /// Succeed for the first N requests, then fail every one after.
  ///
  /// The mirror of [failFirst], and the shape a transport that dies mid-backlog
  /// actually has: pages land, then the socket goes.
  int? failAfter;

  /// Every request body sent, decoded, in order.
  final List<Map<String, Object?>> bodies = [];

  /// The raw JSON of every request body, for secrecy assertions.
  final List<String> rawBodies = [];

  /// The `Authorization` header of every request, in order.
  final List<Object?> authorizations = [];

  /// How many requests were made.
  int get calls => rawBodies.length;

  /// The most recent body. Fails loudly rather than returning an empty map,
  /// because an empty map is what a broken push would also produce.
  Map<String, Object?> get lastBody => bodies.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = options.data is String
        ? options.data as String
        : jsonEncode(options.data);
    rawBodies.add(raw);
    authorizations.add(options.headers['Authorization']);
    bodies.add(jsonDecode(raw) as Map<String, Object?>);

    final shouldFail =
        failWith != null ||
        rawBodies.length <= failFirst ||
        (failAfter != null && rawBodies.length > failAfter!);
    if (shouldFail) {
      final status = failWith ?? 503;
      return ResponseBody.fromString(
        '{"detail":"nope"}',
        status,
        headers: _json,
      );
    }
    final body = _summaryFor(bodies.last);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: _json);
  }

  /// An `IngestSummary` shaped like the server's, counting what actually came in
  /// — so a test that asserts on the receipt is asserting on the payload.
  static Map<String, Object?> _summaryFor(Map<String, Object?> body) {
    int len(String key) => (body[key] as List?)?.length ?? 0;
    return <String, Object?>{
      'samples_accepted': len('samples'),
      'samples_rejected': 0,
      'sleep': len('sleep'),
      'workouts': len('workouts'),
      'daily_totals': len('daily_totals'),
      'days_derived': 1,
      'server_ts': 1754300000,
    };
  }

  static const Map<String, List<String>> _json = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  void close({bool force = false}) {}
}

/// A [PushClient] over [transport], with the app's real dio configuration.
PushClient clientOver(FakeIngestTransport transport) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://example.invalid',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
  dio.httpClientAdapter = transport;
  return PushClient(dio);
}

/// A keystore that is a map.
class MapSecretStore implements SecretStore {
  /// [values] seeds the store.
  MapSecretStore([Map<String, String>? values]) : values = {...?values};

  /// Everything currently stored.
  final Map<String, String> values;

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

/// Credentials holding an API token, which is what a push needs to run.
Credentials signedIn({String token = 'TEST-API-TOKEN'}) => Credentials(
  MapSecretStore({
    'helio_token': token,
    'helio_base_url': 'https://test.example',
  }),
);

/// Credentials holding nothing — a phone that has never signed in.
Credentials signedOut() => Credentials(MapSecretStore());

/// A keystore that refuses, the way a locked or broken one does.
///
/// Distinct from [signedOut]: "there is no token" and "the store could not be
/// asked" are different states, and Standards §1 requires a caller to be able to
/// tell them apart.
class RefusingSecretStore implements SecretStore {
  /// Refuses every operation.
  const RefusingSecretStore();

  static final PlatformException _refused = PlatformException(
    code: 'Unavailable',
    message: 'the keystore is locked',
  );

  @override
  Future<String?> read({required String key}) async => throw _refused;

  @override
  Future<void> write({required String key, required String value}) async =>
      throw _refused;

  @override
  Future<void> delete({required String key}) async => throw _refused;
}
