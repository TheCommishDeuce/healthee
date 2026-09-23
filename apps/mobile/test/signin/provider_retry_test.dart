import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/not_signed_in.dart';
import 'package:healthee/data/api/provider_retry.dart';

void main() {
  test('unsupported endpoints surface immediately through the provider graph', () async {
    var attempts = 0;
    final request = RequestOptions(path: '/api/account');
    final failure = DioException(requestOptions: request,
      response: Response<void>(requestOptions: request, statusCode: 404));
    final provider = FutureProvider<int>((ref) async { attempts++; throw failure; });
    final container = ProviderContainer(retry: apiProviderRetry);
    addTearDown(container.dispose);
    await expectLater(container.read(provider.future), throwsA(same(failure)));
    expect(attempts, 1);
    expect(container.read(provider).hasError, isTrue);
    expect(container.read(provider).isLoading, isFalse);
  });
  test('bad inputs and session cancellation do not retry; transient failures are bounded', () {
    final request = RequestOptions(path: '/api/account');
    for (final status in [401, 402, 403, 404, 409, 422, 429]) {
      expect(apiProviderRetry(0, DioException(requestOptions: request,
        response: Response<void>(requestOptions: request, statusCode: status))), isNull);
    }
    expect(apiProviderRetry(0, const FormatException('Invalid response')), isNull);
    expect(apiProviderRetry(0, const NotSignedIn()), isNull);
    final offline = DioException.connectionError(requestOptions: request, reason: 'Offline');
    expect(apiProviderRetry(0, offline), isNotNull);
    expect(apiProviderRetry(1, offline), isNull);
  });
}
