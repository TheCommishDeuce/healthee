// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weight_outbox.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's [WeightOutbox].

@ProviderFor(weightOutbox)
final weightOutboxProvider = WeightOutboxProvider._();

/// The app's [WeightOutbox].

final class WeightOutboxProvider
    extends $FunctionalProvider<WeightOutbox, WeightOutbox, WeightOutbox>
    with $Provider<WeightOutbox> {
  /// The app's [WeightOutbox].
  WeightOutboxProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'weightOutboxProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$weightOutboxHash();

  @$internal
  @override
  $ProviderElement<WeightOutbox> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  WeightOutbox create(Ref ref) {
    return weightOutbox(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WeightOutbox value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WeightOutbox>(value),
    );
  }
}

String _$weightOutboxHash() => r'4d7231fb96a04b97a18560e45c326a7c72b5ec6d';

/// How many weigh-ins are waiting to upload.
///
/// A read, not a drift `watch()` stream (nothing in this app uses one, and its
/// cancel timer outlives a widget test): whoever changes the outbox — the weight
/// sheet and the foreground push — invalidates this.

@ProviderFor(pendingWeightCount)
final pendingWeightCountProvider = PendingWeightCountProvider._();

/// How many weigh-ins are waiting to upload.
///
/// A read, not a drift `watch()` stream (nothing in this app uses one, and its
/// cancel timer outlives a widget test): whoever changes the outbox — the weight
/// sheet and the foreground push — invalidates this.

final class PendingWeightCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// How many weigh-ins are waiting to upload.
  ///
  /// A read, not a drift `watch()` stream (nothing in this app uses one, and its
  /// cancel timer outlives a widget test): whoever changes the outbox — the weight
  /// sheet and the foreground push — invalidates this.
  PendingWeightCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingWeightCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingWeightCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return pendingWeightCount(ref);
  }
}

String _$pendingWeightCountHash() =>
    r'9e60ac49eeafe48aa5a14e157bb11b52bc0d5f7e';
