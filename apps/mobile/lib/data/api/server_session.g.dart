// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's [ServerSessionRepository].

@ProviderFor(serverSessionRepository)
final serverSessionRepositoryProvider = ServerSessionRepositoryProvider._();

/// The app's [ServerSessionRepository].

final class ServerSessionRepositoryProvider
    extends
        $FunctionalProvider<
          ServerSessionRepository,
          ServerSessionRepository,
          ServerSessionRepository
        >
    with $Provider<ServerSessionRepository> {
  /// The app's [ServerSessionRepository].
  ServerSessionRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverSessionRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverSessionRepositoryHash();

  @$internal
  @override
  $ProviderElement<ServerSessionRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ServerSessionRepository create(Ref ref) {
    return serverSessionRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServerSessionRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServerSessionRepository>(value),
    );
  }
}

String _$serverSessionRepositoryHash() =>
    r'd857c2f916f205cce692498eb641b324853c4c25';

/// Whether this phone is signed in, for anything that wants to say so.
///
/// `keepAlive` because the Today screen and the sign-in screen both watch it and
/// it is one keystore read; invalidated by the sign-in controller on both
/// transitions.

@ProviderFor(serverSession)
final serverSessionProvider = ServerSessionProvider._();

/// Whether this phone is signed in, for anything that wants to say so.
///
/// `keepAlive` because the Today screen and the sign-in screen both watch it and
/// it is one keystore read; invalidated by the sign-in controller on both
/// transitions.

final class ServerSessionProvider
    extends
        $FunctionalProvider<
          AsyncValue<ServerSessionStatus>,
          ServerSessionStatus,
          FutureOr<ServerSessionStatus>
        >
    with
        $FutureModifier<ServerSessionStatus>,
        $FutureProvider<ServerSessionStatus> {
  /// Whether this phone is signed in, for anything that wants to say so.
  ///
  /// `keepAlive` because the Today screen and the sign-in screen both watch it and
  /// it is one keystore read; invalidated by the sign-in controller on both
  /// transitions.
  ServerSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverSessionHash();

  @$internal
  @override
  $FutureProviderElement<ServerSessionStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ServerSessionStatus> create(Ref ref) {
    return serverSession(ref);
  }
}

String _$serverSessionHash() => r'd9f3becb03ac35dad6d74a32873907d60f209a29';
