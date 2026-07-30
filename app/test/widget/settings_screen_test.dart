import 'package:findmyandroid/screens/settings/settings_screen.dart';
import 'package:findmyandroid/services/permission_service.dart';
import 'package:findmyandroid/services/update_service.dart';
import 'package:findmyandroid/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_permission_service.dart';
import '../fakes/fake_update_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Find My Android',
      packageName: 'nl.hiddebalestra.findmyandroid',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> useTallTestView(WidgetTester tester) async {
    // The settings list is longer than a default 600px test surface — make
    // the surface tall enough that every tile is actually built (a plain
    // ListView only mounts on-screen sliver children) instead of scrolling.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildTestee({
    required FakePermissionService permissionService,
    required FakeUpdateService updateService,
  }) {
    return ProviderScope(
      overrides: [
        permissionServiceProvider.overrideWithValue(permissionService),
        updateServiceProvider.overrideWithValue(updateService),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  testWidgets('lists every reliability permission with its granted state', (tester) async {
    final permissionService = FakePermissionService(
      granted: {
        ReliabilityPermission.location: true,
        ReliabilityPermission.backgroundLocation: false,
        ReliabilityPermission.notification: true,
        ReliabilityPermission.exactAlarm: false,
        ReliabilityPermission.doNotDisturb: false,
        ReliabilityPermission.batteryOptimization: true,
        ReliabilityPermission.fullScreenAlarm: false,
        ReliabilityPermission.camera: false,
        ReliabilityPermission.deviceAdmin: false,
      },
    );

    await useTallTestView(tester);
    await tester.pumpWidget(buildTestee(
      permissionService: permissionService,
      updateService: FakeUpdateService(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Background location'), findsOneWidget);
    expect(find.text('Do Not Disturb access'), findsOneWidget);
    expect(find.text('Full-screen alerts'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Device administrator'), findsOneWidget);

    // 3 granted -> check_circle icons; 6 not granted -> "Open settings" buttons.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    expect(find.widgetWithText(TextButton, 'Open settings'), findsNWidgets(6));
  });

  testWidgets('tapping "Open settings" requests the permission and refreshes', (tester) async {
    final permissionService = FakePermissionService();

    await useTallTestView(tester);
    await tester.pumpWidget(buildTestee(
      permissionService: permissionService,
      updateService: FakeUpdateService(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Open settings').first);
    await tester.pumpAndSettle();

    expect(permissionService.requestCallCount, 1);
  });

  testWidgets('shows the "view release" button when an update is available', (tester) async {
    await useTallTestView(tester);
    await tester.pumpWidget(buildTestee(
      permissionService: FakePermissionService(),
      updateService: FakeUpdateService(
        result: const UpdateCheckResult(
          status: UpdateStatus.updateAvailable,
          latestVersion: '9.9.9',
          releaseUrl: 'https://github.com/Hidde-Balestra/findmyandroid/releases/tag/v9.9.9',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Update available: v9.9.9'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'View release'), findsOneWidget);
  });
}
