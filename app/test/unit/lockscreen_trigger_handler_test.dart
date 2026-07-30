import 'package:findmyandroid/services/lockscreen_trigger_handler.dart';
import 'package:findmyandroid/services/security_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_device_admin_bridge.dart';
import '../fakes/fake_photo_capturer.dart';

/// Records whether captureAndUpload() got called instead of actually
/// touching the camera/network — mirrors the spy used in login_dialog_test.
class _SpySecurityCaptureService extends SecurityCaptureService {
  bool captureCalled = false;

  _SpySecurityCaptureService() : super(photoCapturer: FakePhotoCapturer());

  @override
  Future<void> captureAndUpload() async {
    captureCalled = true;
  }
}

void main() {
  group('checkAndHandle', () {
    test('captures a snapshot when a lock-screen trigger is pending', () async {
      final spy = _SpySecurityCaptureService();
      final handler = LockscreenTriggerHandler(
        deviceAdminBridge: FakeDeviceAdminBridge(pendingTrigger: true),
        securityCaptureService: spy,
      );

      await handler.checkAndHandle();

      expect(spy.captureCalled, isTrue);
    });

    test('does nothing when no trigger is pending', () async {
      final spy = _SpySecurityCaptureService();
      final handler = LockscreenTriggerHandler(
        deviceAdminBridge: FakeDeviceAdminBridge(pendingTrigger: false),
        securityCaptureService: spy,
      );

      await handler.checkAndHandle();

      expect(spy.captureCalled, isFalse);
    });

    test('consumes the pending flag so a second poll does not re-trigger', () async {
      final spy = _SpySecurityCaptureService();
      final bridge = FakeDeviceAdminBridge(pendingTrigger: true);
      final handler = LockscreenTriggerHandler(
        deviceAdminBridge: bridge,
        securityCaptureService: spy,
      );

      await handler.checkAndHandle();
      spy.captureCalled = false;
      await handler.checkAndHandle();

      expect(spy.captureCalled, isFalse);
      expect(bridge.consumeCallCount, 2);
    });
  });
}
