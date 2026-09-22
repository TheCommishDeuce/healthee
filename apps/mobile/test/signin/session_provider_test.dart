import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/api_client.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/stored_server_session.dart';

import '../pairing/_pairing_fakes.dart';

void main() {
  test('a session switch rebuilds the API client for the new owner', () async {
    final credentials = Credentials(FakeSecretStore());
    await credentials.setServerSession(
      baseUrl: 'https://test.example',
      token: 'owner-a',
      kind: StoredCredentialKind.shared,
    );
    final container = ProviderContainer(
      overrides: [credentialsProvider.overrideWithValue(credentials)],
    );
    addTearDown(container.dispose);
    await container.read(serverSessionProvider.future);
    final originalApi = container.read(apiClientProvider);

    await credentials.setServerSession(
      baseUrl: 'https://test.example',
      token: 'owner-b',
      kind: StoredCredentialKind.shared,
    );
    container.invalidate(serverSessionProvider);
    await container.read(serverSessionProvider.future);
    await container.pump();
    expect(identical(container.read(apiClientProvider), originalApi), isFalse);
  });
}
