/// The pairing flow's one piece of logic. The widgets below it only draw.
///
/// Every method here has the same shape: publish a busy label, run one
/// repository call, and land on either a new step or a named failure. There is
/// no path that ends anywhere else — `on PairingException` is the only catch,
/// and it always sets [PairingState.failure], so "the button did nothing" is not
/// a state this can reach.
///
/// ## The password's whole life
///
/// It arrives in [signIn], is held in a private field for as long as the flow is
/// open, and is written to the keystore only if the owner ticked the box. It is
/// never in [PairingState], never in a log line, and never sent anywhere except
/// Zepp's own sign-in endpoint. [forget] drops it, and the screen calls that on
/// dispose.
library;

import 'dart:async';

import 'package:healthee/data/pairing/paired_strap.dart';
import 'package:healthee/data/pairing/pairing_exception.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/pairing/zepp_device.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/features/pairing/pairing_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pairing_controller.g.dart';

/// Drives the pairing screen.
@riverpod
class PairingController extends _$PairingController {
  String? _email;
  String? _password;

  @override
  PairingState build() => const PairingState.start();

  /// Step 1 + 2 + 3: sign in to Zepp and fetch the account's straps.
  Future<void> signIn({required String email, required String password}) async {
    state = state.working('Signing in to Zepp…');
    try {
      final devices = await ref
          .read(pairingRepositoryProvider)
          .devicesForAccount(email: email, password: password);
      // Held only after Zepp itself accepted them — remembering a credential we
      // never confirmed would store a typo the owner would then have to find.
      _email = email;
      _password = password;
      state = state.at(ChooseDeviceStep(devices));
    } on PairingException catch (error) {
      state = state.failing(error.failure);
    }
  }

  /// The owner tapped a strap in the list.
  void chooseDevice(ZeppDevice device) {
    state = state.at(ConfirmStrapStep(strap: device.strap));
  }

  /// The manual fallback. Reachable from the sign-in form at any time, including
  /// before a failure — someone who signs in to Zepp with Google has no password
  /// to try, and making them fail once first would be theatre.
  void useManualEntry() {
    state = state.at(const ManualEntryStep());
  }

  /// Back to the Zepp form.
  void useAccountEntry() {
    state = state.at(const ZeppSignInStep());
  }

  /// Validates a typed MAC and key, then moves to confirmation.
  ///
  /// Validation is [PairedStrap.parse]'s, so a hand-typed pairing is held to
  /// exactly the shape an account-supplied one is.
  void enterManually({required String mac, required String authKey}) {
    try {
      final strap = PairedStrap.parse(mac: mac, authKey: authKey);
      state = state.at(ConfirmStrapStep(strap: strap));
    } on PairingException catch (error) {
      state = state.failing(error.failure);
    }
  }

  /// Looks for the chosen strap on the air.
  ///
  /// A no-op unless we are on [ConfirmStrapStep]; the button that calls it only
  /// exists there, and a guard is cheaper than a cast that could throw.
  Future<void> scan() async {
    final step = state.step;
    if (step is! ConfirmStrapStep) {
      return;
    }
    state = state.working('Listening for the strap…');
    try {
      final outcome = await ref
          .read(pairingRepositoryProvider)
          .confirmInRange(step.strap);
      state = state.at(step.withOutcome(outcome));
    } on PairingException catch (error) {
      state = state.failing(error.failure);
    }
  }

  /// Records the opt-in to remember the Zepp sign-in.
  void setRememberZepp({required bool value}) {
    state = state.remembering(value: value);
  }

  /// Writes the pairing to the keystore. The end of the flow.
  ///
  /// Then runs a sync, unawaited (B1). The launch auto-sync ran before there was
  /// a strap and failed with `StrapNotPaired`, which the link treats as
  /// permanent — so nothing retried it, and Today kept saying "No strap is
  /// paired" beside a strap that was. Pairing is what makes that failure false.
  Future<void> pair() async {
    final step = state.step;
    if (step is! ConfirmStrapStep) {
      return;
    }
    state = state.working('Saving the pairing…');
    final email = _email;
    final password = _password;
    // The opt-in can only apply to a sign-in that actually happened — a manual
    // pairing has no Zepp credential to remember, whatever the box says.
    final remember = state.rememberZepp && email != null && password != null
        ? (email: email, password: password)
        : null;
    await ref.read(pairingRepositoryProvider).pair(step.strap, rememberZepp: remember);
    forget();
    ref.invalidate(pairingSummaryProvider);
    state = state.at(PairedStep(step.strap));
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
  }

  /// Forgets the strap and any remembered sign-in, and returns to the start.
  Future<void> unpair() async {
    state = state.working('Forgetting this strap…');
    await ref.read(pairingRepositoryProvider).unpair();
    ref.invalidate(pairingSummaryProvider);
    restart();
  }

  /// Drops the in-memory Zepp credential. Called after pairing and on dispose.
  void forget() {
    _email = null;
    _password = null;
  }

  /// Back to the start, keeping nothing.
  void restart() {
    forget();
    state = const PairingState.start();
  }
}
