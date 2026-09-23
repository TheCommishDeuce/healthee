import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/api/not_signed_in.dart';

/// Unsupported endpoints and refused access need a visible remedy, not repeated
/// loading. A transient HTTP read gets at most one automatic retry.
Duration? apiProviderRetry(int retryCount, Object error) {
  if (error is FormatException) return null;
  // Retrying cannot sign anyone in; a sign-in re-runs the provider by itself.
  if (error is NotSignedIn) return null;
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (error.type == DioExceptionType.cancel ||
        (status != null && status >= 400 && status < 500)) {
      return null;
    }
    return ProviderContainer.defaultRetry(retryCount, error, maxRetries: 1);
  }
  return ProviderContainer.defaultRetry(retryCount, error);
}
