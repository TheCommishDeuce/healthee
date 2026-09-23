// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mirror_sync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's [MirrorSync].

@ProviderFor(mirrorSync)
final mirrorSyncProvider = MirrorSyncProvider._();

/// The app's [MirrorSync].

final class MirrorSyncProvider
    extends $FunctionalProvider<MirrorSync, MirrorSync, MirrorSync>
    with $Provider<MirrorSync> {
  /// The app's [MirrorSync].
  MirrorSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mirrorSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mirrorSyncHash();

  @$internal
  @override
  $ProviderElement<MirrorSync> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MirrorSync create(Ref ref) {
    return mirrorSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MirrorSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MirrorSync>(value),
    );
  }
}

String _$mirrorSyncHash() => r'0dc84e8ebc38283e40cbd9f54f9107cb6a62d204';

/// What is mirrored; invalidated after a run.

@ProviderFor(mirrorStats)
final mirrorStatsProvider = MirrorStatsProvider._();

/// What is mirrored; invalidated after a run.

final class MirrorStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<MirrorStats>,
          MirrorStats,
          FutureOr<MirrorStats>
        >
    with $FutureModifier<MirrorStats>, $FutureProvider<MirrorStats> {
  /// What is mirrored; invalidated after a run.
  MirrorStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mirrorStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mirrorStatsHash();

  @$internal
  @override
  $FutureProviderElement<MirrorStats> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MirrorStats> create(Ref ref) {
    return mirrorStats(ref);
  }
}

String _$mirrorStatsHash() => r'acc4b9fe641bbec08354f519567f0ff625b90a54';
