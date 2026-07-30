import 'package:findmyandroid/screens/home/login_dialog.dart';
import 'package:findmyandroid/services/api_client.dart';
import 'package:findmyandroid/services/security_capture_service.dart';
import 'package:findmyandroid/state/app_settings.dart';
import 'package:findmyandroid/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_photo_capturer.dart';

/// Records whether captureAndUpload() got called instead of actually
/// touching the camera/network.
class _SpySecurityCaptureService extends SecurityCaptureService {
  bool captureCalled = false;

  _SpySecurityCaptureService() : super(photoCapturer: FakePhotoCapturer());

  @override
  Future<void> captureAndUpload() async {
    captureCalled = true;
  }
}

void main() {
  /// Seeds the security-snapshot threshold in SharedPreferences *before* the
  /// widget tree (and therefore the provider reading it) is ever built,
  /// rather than trying to override the StateNotifierProvider directly —
  /// avoids racing SecuritySnapshotThresholdNotifier's own async prefs load.
  Future<void> seedThreshold(int threshold) async {
    SharedPreferences.setMockInitialValues({'security_snapshot_threshold': threshold});
  }

  Widget buildTestee(http.Client httpClient, SecurityCaptureService captureService) {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://example.invalid', httpClient: httpClient),
        ),
        securityCaptureServiceProvider.overrideWithValue(captureService),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            // Warms SecuritySnapshotThresholdNotifier's async prefs load the
            // same way real usage does well before a real failed login (app
            // start, or a prior Settings visit) — a synchronous ref.read
            // right as the login fails would otherwise race that load.
            ref.watch(securitySnapshotThresholdProvider);
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => showAccountLoginDialog(context, ref),
                child: const Text('Show login'),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> attemptLogin(WidgetTester tester) async {
    await tester.tap(find.text('Show login'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Account code'), 'wrong-code');
    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();
  }

  testWidgets('triggers a security snapshot once the threshold (1) is reached', (tester) async {
    await seedThreshold(1);
    final spy = _SpySecurityCaptureService();
    final mockClient = MockClient((_) async => http.Response('{"message":"Invalid code"}', 401));

    await tester.pumpWidget(buildTestee(mockClient, spy));
    await attemptLogin(tester);

    expect(find.textContaining('Login failed'), findsOneWidget);
    expect(spy.captureCalled, isTrue);
  });

  testWidgets('does not trigger before the threshold (3) is reached', (tester) async {
    await seedThreshold(3);
    final spy = _SpySecurityCaptureService();
    final mockClient = MockClient((_) async => http.Response('{"message":"Invalid code"}', 401));

    await tester.pumpWidget(buildTestee(mockClient, spy));
    await attemptLogin(tester);

    expect(find.textContaining('Login failed'), findsOneWidget);
    expect(spy.captureCalled, isFalse);
  });

  testWidgets('never triggers when the feature is disabled (threshold 0)', (tester) async {
    await seedThreshold(0);
    final spy = _SpySecurityCaptureService();
    final mockClient = MockClient((_) async => http.Response('{"message":"Invalid code"}', 401));

    await tester.pumpWidget(buildTestee(mockClient, spy));
    await attemptLogin(tester);

    expect(find.textContaining('Login failed'), findsOneWidget);
    expect(spy.captureCalled, isFalse);
  });

  testWidgets('reaching the threshold across repeated failures triggers exactly once', (tester) async {
    await seedThreshold(2);
    final spy = _SpySecurityCaptureService();
    final mockClient = MockClient((_) async => http.Response('{"message":"Invalid code"}', 401));

    await tester.pumpWidget(buildTestee(mockClient, spy));

    await attemptLogin(tester);
    expect(spy.captureCalled, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await attemptLogin(tester);
    expect(spy.captureCalled, isTrue);
  });

  testWidgets('a successful login resets the counter', (tester) async {
    await seedThreshold(2);
    final spy = _SpySecurityCaptureService();
    var callCount = 0;
    final mockClient = MockClient((_) async {
      callCount++;
      // First call fails, second (the retry with the right code) succeeds.
      if (callCount == 1) return http.Response('{"message":"Invalid code"}', 401);
      return http.Response('{"sessionToken":"tok","salt":"c2FsdA=="}', 200);
    });

    await tester.pumpWidget(buildTestee(mockClient, spy));

    await attemptLogin(tester);
    expect(spy.captureCalled, isFalse);

    // Successful retry — should reset the failure count rather than leaving
    // it primed to trigger on the very next unrelated failed attempt.
    await tester.enterText(find.widgetWithText(TextField, 'Account code'), 'right-code');
    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(spy.captureCalled, isFalse);
  });
}
