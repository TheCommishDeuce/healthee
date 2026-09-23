/// B2, from the owner's phone: signed out, Today said "Couldn't reach your
/// server for today's judgements" beside "not signed in".
///
/// Two claims. A phone with no session does not ASK — there is no token to send,
/// and the request went to the build's default address unauthenticated. And the
/// refusal is a typed [NotSignedIn], so a screen can say "sign in" rather than
/// blaming a server nobody contacted.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/not_signed_in.dart';
import 'package:healthee/data/api/provider_retry.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/today_repository.dart';

/// Answers every request with the contract snapshot, and counts them.
class _Counting implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      File('../../packages/contracts/snapshots/today.json').readAsStringSync(),
      200,
      headers: const {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late LocalStore store;
  late _Counting transport;

  setUp(() {
    store = LocalStore.memory();
    transport = _Counting();
  });
  tearDown(() => store.close());

  ProviderContainer containerFor(ServerSessionStatus session) {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = transport;
    // The app's own retry policy, so "surfaces at once" is what the app does.
    final container = ProviderContainer(
      retry: apiProviderRetry,
      overrides: [
        serverSessionProvider.overrideWith((ref) async => session),
        localStoreProvider.overrideWithValue(store),
        todayProvider.overrideWithValue('2026-09-23'),
        todayRepositoryProvider.overrideWithValue(TodayRepository(dio, store)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('SIGNED OUT: no request is made, and the refusal is typed', () async {
    final container = containerFor(const ServerSessionStatus.signedOut());
    // Held open: an auto-dispose provider read once is disposed mid-load.
    container.listen(todaySnapshotProvider, (_, _) {});

    await expectLater(
      container.read(todaySnapshotProvider.future),
      throwsA(isA<NotSignedIn>()),
    );
    expect(transport.calls, 0);
  });

  test('signed in: the request is made as before', () async {
    final container = containerFor(
      const ServerSessionStatus(
        signedIn: true,
        baseUrl: 'https://example.invalid',
      ),
    );

    await container.read(todaySnapshotProvider.future);
    expect(transport.calls, 1);
  });
}
