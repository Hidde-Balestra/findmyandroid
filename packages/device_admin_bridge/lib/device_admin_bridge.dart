import 'package:flutter/services.dart';

/// Bridges Android's Device Administrator APIs. This is the only way a
/// regular app can be notified that the device's lock-screen credential
/// (PIN/pattern/password) was entered incorrectly — Android otherwise gives
/// third-party apps no visibility into lock-screen unlock attempts at all,
/// on purpose. Activating it shows the user Android's own prominent
/// "Activate device administrator?" warning (listing everything the API
/// *could* do, e.g. wipe data, set password policies), even though this app
/// only ever uses the failed-attempt notification.
///
/// The failed-attempt counting and threshold check happen entirely on the
/// native side (in `SecurityDeviceAdminReceiver`/`DeviceAdminPrefs`), since
/// a failed unlock attempt can occur with no Flutter isolate running to
/// react to it. [consumePendingLockscreenTrigger] is polled from Dart
/// instead — see where it's called from for the resulting latency
/// trade-off.
class DeviceAdminBridge {
  static const MethodChannel _channel = MethodChannel(
    'nl.hiddebalestra.device_admin_bridge/device_admin',
  );

  Future<bool> isActive() async {
    return (await _channel.invokeMethod<bool>('isActive')) ?? false;
  }

  /// Opens Android's own "Activate device administrator?" system screen.
  /// There is no other way to grant this — it cannot be requested via a
  /// normal runtime permission dialog.
  Future<void> requestActivation() => _channel.invokeMethod('requestActivation');

  /// Keeps the native side's copy of the security-snapshot threshold (see
  /// SecuritySnapshotThresholdNotifier) up to date — the native receiver
  /// has no access to Dart's SharedPreferences storage, so this must be
  /// pushed explicitly whenever it changes and once at app startup.
  Future<void> setThreshold(int threshold) => _channel.invokeMethod('setThreshold', {'threshold': threshold});

  /// Returns true (and atomically clears the flag) if the native receiver
  /// has recorded enough consecutive failed lock-screen attempts to cross
  /// the configured threshold since this was last called. Normally polled
  /// from the 5-minute background tick (see LockscreenTriggerHandler) —
  /// [listenForImmediateLockscreenTrigger] below shortcuts that wait when
  /// possible.
  Future<bool> consumePendingLockscreenTrigger() async {
    return (await _channel.invokeMethod<bool>('consumePendingTrigger')) ?? false;
  }

  /// Registers [onTriggered] to run as soon as the native receiver crosses
  /// the failed-lock-screen-attempt threshold, instead of waiting for the
  /// next 5-minute poll. Works because `SecurityDeviceAdminReceiver` pushes
  /// a "lockscreenFailureDetected" call back into whichever engine(s) this
  /// channel is currently attached to (see DeviceAdminBridgePlugin) the
  /// moment the threshold is crossed -- this only has any effect from the
  /// background isolate, since that's the one with a matching engine
  /// attached whenever the reporting service is running. The 5-minute poll
  /// still exists as a fallback for the (rare) case where the background
  /// service isn't running at the exact moment of the failed attempt.
  void listenForImmediateLockscreenTrigger(Future<void> Function() onTriggered) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'lockscreenFailureDetected') {
        await onTriggered();
      }
    });
  }

  /// Debug aid (Settings → Debug): when enabled, the native receiver posts
  /// an immediate system notification on every failed lock-screen attempt,
  /// independent of the security-snapshot threshold and the up-to-5-minute
  /// background poll — lets the user confirm onPasswordFailed() is actually
  /// firing on their device without waiting on the rest of that pipeline.
  Future<void> setDebugNotifyEnabled(bool enabled) =>
      _channel.invokeMethod('setDebugNotifyEnabled', {'enabled': enabled});

  /// Posts the same debug notification as above on demand, without needing
  /// to actually fail a lock-screen unlock — useful for checking that
  /// notification permission/channel setup works at all on this device.
  Future<void> sendTestNotification() => _channel.invokeMethod('sendTestNotification');
}
