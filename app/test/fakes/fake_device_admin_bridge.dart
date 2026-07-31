import 'package:device_admin_bridge/device_admin_bridge.dart';

/// Test double avoiding the real MethodChannel — DeviceAdminBridge has no
/// abstract interface (it's a thin real-plugin wrapper), so this overrides
/// every method actually used by production code instead.
class FakeDeviceAdminBridge extends DeviceAdminBridge {
  final bool activeValue;
  bool pendingTrigger;
  int? lastThreshold;
  int consumeCallCount = 0;
  bool? lastDebugNotifyEnabled;
  int sendTestNotificationCallCount = 0;

  FakeDeviceAdminBridge({this.activeValue = true, this.pendingTrigger = false});

  @override
  Future<bool> isActive() async => activeValue;

  @override
  Future<void> requestActivation() async {}

  @override
  Future<void> setThreshold(int threshold) async {
    lastThreshold = threshold;
  }

  @override
  Future<bool> consumePendingLockscreenTrigger() async {
    consumeCallCount++;
    final wasPending = pendingTrigger;
    pendingTrigger = false;
    return wasPending;
  }

  @override
  Future<void> setDebugNotifyEnabled(bool enabled) async {
    lastDebugNotifyEnabled = enabled;
  }

  @override
  Future<void> sendTestNotification() async {
    sendTestNotificationCallCount++;
  }
}
