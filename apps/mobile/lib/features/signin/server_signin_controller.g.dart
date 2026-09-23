// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_signin_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives the server sign-in screen.

@ProviderFor(ServerSignInController)
final serverSignInControllerProvider = ServerSignInControllerProvider._();

/// Drives the server sign-in screen.
final class ServerSignInControllerProvider
    extends $NotifierProvider<ServerSignInController, ServerSignInState> {
  /// Drives the server sign-in screen.
  ServerSignInControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverSignInControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverSignInControllerHash();

  @$internal
  @override
  ServerSignInController create() => ServerSignInController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServerSignInState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServerSignInState>(value),
    );
  }
}

String _$serverSignInControllerHash() =>
    r'0796ff8360d8bb48b78decceaa4fbf599bb2adb5';

/// Drives the server sign-in screen.

abstract class _$ServerSignInController extends $Notifier<ServerSignInState> {
  ServerSignInState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ServerSignInState, ServerSignInState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ServerSignInState, ServerSignInState>,
              ServerSignInState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
