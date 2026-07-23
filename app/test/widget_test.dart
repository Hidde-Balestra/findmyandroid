import 'package:findmyandroid/main.dart';
import 'package:findmyandroid/services/api_client.dart';
import 'package:findmyandroid/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots to the onboarding welcome screen when unpaired', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mockClient = MockClient((request) async => http.Response('not found', 404));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'https://example.invalid', httpClient: mockClient),
          ),
          // Avoids depending on flutter_secure_storage's real platform
          // channel (unavailable in widget tests) just to resolve "is this
          // phone paired?" — that's exercised directly in secure_store tests.
          isPairedProvider.overrideWith((ref) async => false),
        ],
        child: const FindMyAndroidApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Find My Android'), findsWidgets);
    expect(find.text('Create a new account'), findsOneWidget);
  });
}
