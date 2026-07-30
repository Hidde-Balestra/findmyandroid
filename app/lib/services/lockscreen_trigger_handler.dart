import 'package:device_admin_bridge/device_admin_bridge.dart';

import 'security_capture_service.dart';

/// Polls whether too many failed lock-screen unlock attempts have happened
/// since the last check (see DeviceAdminBridge/SecurityDeviceAdminReceiver
/// for why the counting happens natively rather than here), and if so runs
/// the same [SecurityCaptureService] used for the in-app failed-login
/// trigger. Called from the background check-in's 5-minute tick — the same
/// interval as location reporting and "play sound" polling — so a
/// lock-screen-triggered snapshot can take up to 5 minutes to fire, the same
/// deliberate trade-off already made for those two features.
class LockscreenTriggerHandler {
  final DeviceAdminBridge deviceAdminBridge;
  final SecurityCaptureService securityCaptureService;

  LockscreenTriggerHandler({
    required this.deviceAdminBridge,
    required this.securityCaptureService,
  });

  Future<void> checkAndHandle() async {
    if (await deviceAdminBridge.consumePendingLockscreenTrigger()) {
      await securityCaptureService.captureAndUpload();
    }
  }
}
