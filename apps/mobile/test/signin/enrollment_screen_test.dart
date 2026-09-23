/// The account screen's enrollment card — nothing is sent before the owner has
/// seen, and confirmed, the server a scanned or pasted link points at.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/auth/enrollment_client.dart';
import 'package:healthee/data/auth/identity_providers.dart';
import 'package:healthee/data/auth/phone_enrollment.dart';
import 'package:healthee/features/signin/server_signin_screen.dart';
import 'package:healthee/features/signin/widgets/enrollment_entry.dart';

import '../pairing/_pairing_fakes.dart';
import '_signin_fakes.dart';

const String _link =
    'healthee://enroll?v=1&server=https%3A%2F%2Fhealth.example.com'
    '&code=one-time-code-for-the-screen';

Widget _host(FakeSecretStore store, ScriptedServer server) => ProviderScope(
  overrides: [
    credentialsProvider.overrideWithValue(Credentials(store)),
    identityAvailableProvider.overrideWithValue(true),
    serverSessionRepositoryProvider.overrideWithValue(
      repositoryWith(store, server),
    ),
    enrollmentClientProvider.overrideWithValue(
      EnrollmentClient(EnrollmentClient.dioFor()..httpClientAdapter = server),
    ),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const ServerSignInScreen()),
);

Future<void> _paste(WidgetTester tester, String link) async {
  final field = find.descendant(
    of: find.byType(EnrollmentEntry),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, link);
  await tester.tap(find.text('Use this link'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a pasted link asks before it sends, then enrolls', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = FakeSecretStore();
    final server = ScriptedServer(
      reply: const ServerReply(
        200,
        body: '{"device_token":"hph_screen-token"}',
      ),
    );
    await tester.pumpWidget(_host(store, server));
    await tester.pumpAndSettle();

    await _paste(tester, _link);

    expect(
      find.textContaining('Connect this phone to health.example.com?'),
      findsOneWidget,
    );
    expect(
      server.sent,
      isEmpty,
      reason: 'nothing may be sent before the owner confirms',
    );

    await tester.tap(find.text('Connect to health.example.com'));
    await tester.pumpAndSettle();

    expect(server.sent.single.uri.path, '/api/enroll');
    final session = (await Credentials(store).serverSession())!;
    expect(session.kind, StoredCredentialKind.enrolled);
  });

  testWidgets('cancelling sends nothing and saves nothing', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = FakeSecretStore();
    final server = ScriptedServer();
    await tester.pumpWidget(_host(store, server));
    await tester.pumpAndSettle();

    await _paste(tester, _link);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Scan the QR code'), findsOneWidget);
    expect(server.sent, isEmpty);
    expect(await Credentials(store).serverSession(), isNull);
  });

  testWidgets('something that is not an enrollment link is named, not sent', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = ScriptedServer();
    await tester.pumpWidget(_host(FakeSecretStore(), server));
    await tester.pumpAndSettle();

    await _paste(tester, 'https://example.com/not-an-enrollment');

    expect(find.text("That isn't a Healthee enrollment code"), findsOneWidget);
    expect(find.textContaining('Connect this phone'), findsNothing);
    expect(server.sent, isEmpty);
  });
}
