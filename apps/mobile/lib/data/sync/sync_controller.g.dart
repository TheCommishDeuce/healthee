// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's sync engine, wired to the one client, store and scanner.

@ProviderFor(syncEngine)
final syncEngineProvider = SyncEngineProvider._();

/// The app's sync engine, wired to the one client, store and scanner.

final class SyncEngineProvider
    extends $FunctionalProvider<SyncEngine, SyncEngine, SyncEngine>
    with $Provider<SyncEngine> {
  /// The app's sync engine, wired to the one client, store and scanner.
  SyncEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncEngineHash();

  @$internal
  @override
  $ProviderElement<SyncEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncEngine create(Ref ref) {
    return syncEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncEngine>(value),
    );
  }
}

String _$syncEngineHash() => r'8a25407e5aa5e872e39c97dc606b240219a6ddd8';

/// The wall clock, as a provider so a test can pin it.
///
/// Overriding `DateTime.now` is not possible and a test that waited out a
/// fifteen-minute window would not be a test. Everything time-dependent in this
/// file reads the clock through here.

@ProviderFor(syncClock)
final syncClockProvider = SyncClockProvider._();

/// The wall clock, as a provider so a test can pin it.
///
/// Overriding `DateTime.now` is not possible and a test that waited out a
/// fifteen-minute window would not be a test. Everything time-dependent in this
/// file reads the clock through here.

final class SyncClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The wall clock, as a provider so a test can pin it.
  ///
  /// Overriding `DateTime.now` is not possible and a test that waited out a
  /// fifteen-minute window would not be a test. Everything time-dependent in this
  /// file reads the clock through here.
  SyncClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return syncClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$syncClockHash() => r'c02b1d0a7e2e6d34fcd79235b527cfb9a1f4e513';

/// The debounce, reading the persisted "last complete sync" stamp.

@ProviderFor(autoSyncGate)
final autoSyncGateProvider = AutoSyncGateProvider._();

/// The debounce, reading the persisted "last complete sync" stamp.

final class AutoSyncGateProvider
    extends $FunctionalProvider<AutoSyncGate, AutoSyncGate, AutoSyncGate>
    with $Provider<AutoSyncGate> {
  /// The debounce, reading the persisted "last complete sync" stamp.
  AutoSyncGateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'autoSyncGateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$autoSyncGateHash();

  @$internal
  @override
  $ProviderElement<AutoSyncGate> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AutoSyncGate create(Ref ref) {
    return autoSyncGate(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutoSyncGate value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutoSyncGate>(value),
    );
  }
}

String _$autoSyncGateHash() => r'7256aaa136a7027bd5c60fb65b147735a26193d4';

/// Holds what the link to the strap is doing, and drives it.

@ProviderFor(SyncController)
final syncControllerProvider = SyncControllerProvider._();

/// Holds what the link to the strap is doing, and drives it.
final class SyncControllerProvider
    extends $NotifierProvider<SyncController, StrapConnection> {
  /// Holds what the link to the strap is doing, and drives it.
  SyncControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncControllerHash();

  @$internal
  @override
  SyncController create() => SyncController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StrapConnection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StrapConnection>(value),
    );
  }
}

String _$syncControllerHash() => r'd3b8dfe6fa13cefb752dffbd2345d65abdd26ecc';

/// Holds what the link to the strap is doing, and drives it.

abstract class _$SyncController extends $Notifier<StrapConnection> {
  StrapConnection build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StrapConnection, StrapConnection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StrapConnection, StrapConnection>,
              StrapConnection,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
