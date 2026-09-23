// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'today_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's [TodayRepository].

@ProviderFor(todayRepository)
final todayRepositoryProvider = TodayRepositoryProvider._();

/// The app's [TodayRepository].

final class TodayRepositoryProvider
    extends
        $FunctionalProvider<TodayRepository, TodayRepository, TodayRepository>
    with $Provider<TodayRepository> {
  /// The app's [TodayRepository].
  TodayRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayRepositoryHash();

  @$internal
  @override
  $ProviderElement<TodayRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TodayRepository create(Ref ref) {
    return todayRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TodayRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TodayRepository>(value),
    );
  }
}

String _$todayRepositoryHash() => r'9b715fc2421c68f4b3cae20c77255b1491fcc32a';

/// The snapshot for the day being read, with its provenance.
///
/// **It watches [viewDateProvider], so the derived half follows the date
/// control.** That single `watch` is what turns the server's new `day` parameter
/// into a screen: stepping back re-requests, and stepping forward to the newest
/// day re-requests again. It is also why nothing downstream has to remember to
/// pass a day — a screen that held the selection and forgot to thread it would be
/// drawing one day's judgements under another's date, which is the failure the
/// whole feature exists to remove.
///
/// The value sent is always the selection, today included, so there is one code
/// path rather than a null-on-today special case that only the current day
/// exercises. The server treats an explicit today and an absent day identically.
///
/// **Signed out, it does not ask** and throws [NotSignedIn] instead: there is no
/// token to send, and the request would go to the build's default address
/// unauthenticated only to fail (B2).
///
/// [ProviderLogger] logs every provider failure through the one logging path, so
/// there is deliberately no `try`/`catch` here: catching would only let us
/// re-throw after a log entry that already happens.

@ProviderFor(todaySnapshot)
final todaySnapshotProvider = TodaySnapshotProvider._();

/// The snapshot for the day being read, with its provenance.
///
/// **It watches [viewDateProvider], so the derived half follows the date
/// control.** That single `watch` is what turns the server's new `day` parameter
/// into a screen: stepping back re-requests, and stepping forward to the newest
/// day re-requests again. It is also why nothing downstream has to remember to
/// pass a day — a screen that held the selection and forgot to thread it would be
/// drawing one day's judgements under another's date, which is the failure the
/// whole feature exists to remove.
///
/// The value sent is always the selection, today included, so there is one code
/// path rather than a null-on-today special case that only the current day
/// exercises. The server treats an explicit today and an absent day identically.
///
/// **Signed out, it does not ask** and throws [NotSignedIn] instead: there is no
/// token to send, and the request would go to the build's default address
/// unauthenticated only to fail (B2).
///
/// [ProviderLogger] logs every provider failure through the one logging path, so
/// there is deliberately no `try`/`catch` here: catching would only let us
/// re-throw after a log entry that already happens.

final class TodaySnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<TodayView>,
          TodayView,
          FutureOr<TodayView>
        >
    with $FutureModifier<TodayView>, $FutureProvider<TodayView> {
  /// The snapshot for the day being read, with its provenance.
  ///
  /// **It watches [viewDateProvider], so the derived half follows the date
  /// control.** That single `watch` is what turns the server's new `day` parameter
  /// into a screen: stepping back re-requests, and stepping forward to the newest
  /// day re-requests again. It is also why nothing downstream has to remember to
  /// pass a day — a screen that held the selection and forgot to thread it would be
  /// drawing one day's judgements under another's date, which is the failure the
  /// whole feature exists to remove.
  ///
  /// The value sent is always the selection, today included, so there is one code
  /// path rather than a null-on-today special case that only the current day
  /// exercises. The server treats an explicit today and an absent day identically.
  ///
  /// **Signed out, it does not ask** and throws [NotSignedIn] instead: there is no
  /// token to send, and the request would go to the build's default address
  /// unauthenticated only to fail (B2).
  ///
  /// [ProviderLogger] logs every provider failure through the one logging path, so
  /// there is deliberately no `try`/`catch` here: catching would only let us
  /// re-throw after a log entry that already happens.
  TodaySnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todaySnapshotProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todaySnapshotHash();

  @$internal
  @override
  $FutureProviderElement<TodayView> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<TodayView> create(Ref ref) {
    return todaySnapshot(ref);
  }
}

String _$todaySnapshotHash() => r'd42f14a44975d7f99c95a857bb990a5f0c4c334d';

/// The last biological age this phone holds, and the day it belonged to.
///
/// Deliberately **lazy**: only the withheld hero watches it, so a payload that
/// carried a number never touches the local tier at all. A field on [TodayView]
/// would scan the cache on every load to answer a question almost every load
/// does not ask.

@ProviderFor(lastKnownBiologicalAge)
final lastKnownBiologicalAgeProvider = LastKnownBiologicalAgeProvider._();

/// The last biological age this phone holds, and the day it belonged to.
///
/// Deliberately **lazy**: only the withheld hero watches it, so a payload that
/// carried a number never touches the local tier at all. A field on [TodayView]
/// would scan the cache on every load to answer a question almost every load
/// does not ask.

final class LastKnownBiologicalAgeProvider
    extends
        $FunctionalProvider<
          AsyncValue<LastKnown<double>?>,
          LastKnown<double>?,
          FutureOr<LastKnown<double>?>
        >
    with
        $FutureModifier<LastKnown<double>?>,
        $FutureProvider<LastKnown<double>?> {
  /// The last biological age this phone holds, and the day it belonged to.
  ///
  /// Deliberately **lazy**: only the withheld hero watches it, so a payload that
  /// carried a number never touches the local tier at all. A field on [TodayView]
  /// would scan the cache on every load to answer a question almost every load
  /// does not ask.
  LastKnownBiologicalAgeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastKnownBiologicalAgeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastKnownBiologicalAgeHash();

  @$internal
  @override
  $FutureProviderElement<LastKnown<double>?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LastKnown<double>?> create(Ref ref) {
    return lastKnownBiologicalAge(ref);
  }
}

String _$lastKnownBiologicalAgeHash() =>
    r'1363b5c2f872c50af294e0a2701d221466cebd12';
