/// B1, from the owner's phone: right after pairing, Today still said "No strap
/// is paired with this phone".
///
/// The launch auto-sync ran before there was a strap, failed with
/// `StrapNotPaired`, and the link treats that as permanent — nothing retried it.
/// The card cleared only on a manual pull. Pairing is the event that makes that
/// failure false, so a successful pairing runs the sync itself.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/ble/strap_failure.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/sync/sync_failure.dart';
import 'package:healthee/data/sync/sync_outcome.dart';
import 'package:healthee/features/pairing/pairing_controller.dart';
import 'package:healthee/features/pairing/pairing_state.dart';

import '_pairing_fakes.dart';
import '_zepp_stub.dart';

/// Starts where the owner was — the pre-pairing sync failed — and counts syncs.
class _RecordingSync extends SyncController {
  int syncs = 0;

  @override
  StrapConnection build() =>
      ConnectionFailed(SyncFailure.strap(const StrapNotPaired()));

  @override
  Future<SyncOutcome?> syncNow() async {
    syncs++;
    return null;
  }
}

void main() {
  late _RecordingSync sync;
  late ProviderContainer container;

  setUp(() {
    sync = _RecordingSync();
    final store = FakeSecretStore();
    container = ProviderContainer(
      overrides: [
        credentialsProvider.overrideWithValue(Credentials(store)),
        pairingRepositoryProvider.overrideWithValue(
          PairingRepository(
            credentials: Credentials(store),
            zepp: clientWith(happyPathAdapter()),
            scanner: FakeStrapScanner(),
          ),
        ),
        syncControllerProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
  });

  test('A SUCCESSFUL PAIRING RUNS THE SYNC THAT FAILED BEFORE IT', () async {
    final pairing = container.read(pairingControllerProvider.notifier);
    container.listen(pairingControllerProvider, (_, _) {});
    container.read(syncControllerProvider);

    pairing.enterManually(
      mac: 'DB:98:1F:80:4C:3D',
      authKey: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    );
    expect(sync.syncs, 0, reason: 'choosing a strap is not pairing it');

    await pairing.pair();

    expect(container.read(pairingControllerProvider).step, isA<PairedStep>());
    expect(sync.syncs, 1);
  });
}
