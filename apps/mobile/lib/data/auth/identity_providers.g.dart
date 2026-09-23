// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's identity client, or null on a build with no provider configured.

@ProviderFor(identityClient)
final identityClientProvider = IdentityClientProvider._();

/// The app's identity client, or null on a build with no provider configured.

final class IdentityClientProvider
    extends
        $FunctionalProvider<IdentityClient?, IdentityClient?, IdentityClient?>
    with $Provider<IdentityClient?> {
  /// The app's identity client, or null on a build with no provider configured.
  IdentityClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'identityClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$identityClientHash();

  @$internal
  @override
  $ProviderElement<IdentityClient?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  IdentityClient? create(Ref ref) {
    return identityClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IdentityClient? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IdentityClient?>(value),
    );
  }
}

String _$identityClientHash() => r'e930c2903f8f9f190342eb64b023e15b07061ca1';

/// Whether this build can sign in with an email and a password.
///
/// A provider rather than `Env.hasIdentityProvider` read at the call site, and
/// the difference is testability: the dart-defines behind that getter are
/// compile-time constants, so a widget test can never see a build that HAS an
/// identity provider — every sign-in test would silently exercise the
/// transitional pasted-token path and the real one would ship unproven.
///
/// Derived from [identityClientProvider] rather than from `Env` directly, so
/// there is one answer to "is there a provider" and not two that can disagree.

@ProviderFor(identityAvailable)
final identityAvailableProvider = IdentityAvailableProvider._();

/// Whether this build can sign in with an email and a password.
///
/// A provider rather than `Env.hasIdentityProvider` read at the call site, and
/// the difference is testability: the dart-defines behind that getter are
/// compile-time constants, so a widget test can never see a build that HAS an
/// identity provider — every sign-in test would silently exercise the
/// transitional pasted-token path and the real one would ship unproven.
///
/// Derived from [identityClientProvider] rather than from `Env` directly, so
/// there is one answer to "is there a provider" and not two that can disagree.

final class IdentityAvailableProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether this build can sign in with an email and a password.
  ///
  /// A provider rather than `Env.hasIdentityProvider` read at the call site, and
  /// the difference is testability: the dart-defines behind that getter are
  /// compile-time constants, so a widget test can never see a build that HAS an
  /// identity provider — every sign-in test would silently exercise the
  /// transitional pasted-token path and the real one would ship unproven.
  ///
  /// Derived from [identityClientProvider] rather than from `Env` directly, so
  /// there is one answer to "is there a provider" and not two that can disagree.
  IdentityAvailableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'identityAvailableProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$identityAvailableHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return identityAvailable(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$identityAvailableHash() => r'c777c8b3920e51dcae0bc20fd0778480ccf03325';
