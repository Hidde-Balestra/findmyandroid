import 'package:findmyandroid/screens/settings/debug_screen.dart';
import 'package:findmyandroid/state/app_settings.dart';
import 'package:findmyandroid/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_device_admin_bridge.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestee(FakeDeviceAdminBridge bridge) {
    return ProviderScope(
      overrides: [
        deviceAdminBridgeProvider.overrideWithValue(bridge),
        debugLockscreenNotifyProvider.overrideWith(
          (ref) => DebugLockscreenNotifyNotifier(deviceAdminBridge: bridge),
        ),
      ],
      child: const MaterialApp(home: DebugScreen()),
    );
  }

  testWidgets('toggle starts off and enabling it pushes the flag to the native side', (tester) async {
    final bridge = FakeDeviceAdminBridge();

    await tester.pumpWidget(buildTestee(bridge));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    expect(bridge.lastDebugNotifyEnabled, isTrue);
  });

  testWidgets('tapping "Send test notification" calls the bridge', (tester) async {
    final bridge = FakeDeviceAdminBridge();

    await tester.pumpWidget(buildTestee(bridge));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Send test notification'));
    await tester.pumpAndSettle();

    expect(bridge.sendTestNotificationCallCount, 1);
  });
}
