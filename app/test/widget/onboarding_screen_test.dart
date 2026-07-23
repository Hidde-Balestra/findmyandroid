import 'dart:convert';

import 'package:findmyandroid/screens/onboarding/onboarding_screen.dart';
import 'package:findmyandroid/services/api_client.dart';
import 'package:findmyandroid/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Widget buildTestee(http.Client httpClient) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://example.invalid', httpClient: httpClient),
        ),
      ],
      child: const MaterialApp(home: OnboardingScreen()),
    );
  }

  testWidgets('shows the one-time code and gates Continue behind the confirmation checkbox', (tester) async {
    // The code/QR card is taller than a default 600px test surface, and a
    // plain ListView only mounts on-screen sliver children — use a tall
    // surface so the Continue button below it is actually built.
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('register.php')) {
        return http.Response(
          jsonEncode({
            'code': 'ABCD-EFGH-1234-5678-9012',
            'salt': 'c29tZXNhbHQ=',
            'totpUri': 'otpauth://totp/FindMyAndroid?secret=JBSWY3DPEHPK3PXP&issuer=FindMyAndroid',
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(buildTestee(mockClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create a new account'));
    await tester.pumpAndSettle();

    expect(find.text('ABCD-EFGH-1234-5678-9012'), findsOneWidget);

    final continueButtonFinder = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(continueButtonFinder).onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(continueButtonFinder).onPressed, isNotNull);
  });

  testWidgets('offers a path to pair with an existing account code', (tester) async {
    final mockClient = MockClient((request) async => http.Response('not found', 404));

    await tester.pumpWidget(buildTestee(mockClient));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I already have an account code'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Account code'), findsOneWidget);
    expect(find.widgetWithText(TextField, '6-digit code'), findsOneWidget);
  });
}
