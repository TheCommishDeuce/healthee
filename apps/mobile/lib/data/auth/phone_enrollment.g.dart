// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'phone_enrollment.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The redemption client. A provider so tests can answer for the server.

@ProviderFor(enrollmentClient)
final enrollmentClientProvider = EnrollmentClientProvider._();

/// The redemption client. A provider so tests can answer for the server.

final class EnrollmentClientProvider
    extends
        $FunctionalProvider<
          EnrollmentClient,
          EnrollmentClient,
          EnrollmentClient
        >
    with $Provider<EnrollmentClient> {
  /// The redemption client. A provider so tests can answer for the server.
  EnrollmentClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'enrollmentClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$enrollmentClientHash();

  @$internal
  @override
  $ProviderElement<EnrollmentClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EnrollmentClient create(Ref ref) {
    return enrollmentClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EnrollmentClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EnrollmentClient>(value),
    );
  }
}

String _$enrollmentClientHash() => r'45cd34f31e50df67eaaecd62c2429a325fb6735c';
