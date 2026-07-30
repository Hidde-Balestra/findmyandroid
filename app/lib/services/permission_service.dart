import 'package:device_admin_bridge/device_admin_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Every permission/system-toggle this app relies on to keep reporting
/// location and to make "play sound" actually ring: precise location,
/// background location, notifications, exact-alarm scheduling (used by the
/// `alarm` plugin), Do Not Disturb access, battery-optimization exemption,
/// and (Android 14+) full-screen-intent. All are Android system toggles that
/// can't be granted silently — the user has to flip them in Settings.
enum ReliabilityPermission {
  location,
  backgroundLocation,
  notification,
  exactAlarm,
  doNotDisturb,
  batteryOptimization,
  fullScreenAlarm,
  camera,
  deviceAdmin,
}

class PermissionService {
  static const _fullScreenIntentChannel = MethodChannel(
    'nl.hiddebalestra.findmyandroid/full_screen_intent',
  );

  final DeviceAdminBridge _deviceAdminBridge;

  PermissionService({DeviceAdminBridge? deviceAdminBridge})
      : _deviceAdminBridge = deviceAdminBridge ?? DeviceAdminBridge();

  Permission? _permissionFor(ReliabilityPermission permission) => switch (permission) {
        ReliabilityPermission.location => Permission.locationWhenInUse,
        ReliabilityPermission.backgroundLocation => Permission.locationAlways,
        ReliabilityPermission.notification => Permission.notification,
        ReliabilityPermission.exactAlarm => Permission.scheduleExactAlarm,
        ReliabilityPermission.doNotDisturb => Permission.accessNotificationPolicy,
        ReliabilityPermission.batteryOptimization => Permission.ignoreBatteryOptimizations,
        ReliabilityPermission.camera => Permission.camera,
        // Not covered by permission_handler; bridged via a native MethodChannel.
        ReliabilityPermission.fullScreenAlarm => null,
        ReliabilityPermission.deviceAdmin => null,
      };

  Future<bool> isGranted(ReliabilityPermission permission) async {
    if (permission == ReliabilityPermission.fullScreenAlarm) {
      return _isFullScreenIntentGranted();
    }
    if (permission == ReliabilityPermission.deviceAdmin) {
      return _isAndroid ? _deviceAdminBridge.isActive() : true;
    }
    final status = await _permissionFor(permission)!.status;
    return status.isGranted;
  }

  /// Requests the permission through the normal OS dialog where supported.
  /// For permissions Android only grants via a settings screen (background
  /// location on Android 11+, Do Not Disturb access, battery optimization,
  /// full-screen alarms, device administrator), this opens that screen
  /// directly.
  Future<void> request(ReliabilityPermission permission) async {
    if (permission == ReliabilityPermission.fullScreenAlarm) {
      await _openFullScreenIntentSettings();
      return;
    }
    if (permission == ReliabilityPermission.deviceAdmin) {
      if (_isAndroid) await _deviceAdminBridge.requestActivation();
      return;
    }
    if (permission == ReliabilityPermission.backgroundLocation) {
      // Android requires foreground location to already be granted before
      // it will even show the "Allow all the time" background prompt.
      final fine = await Permission.locationWhenInUse.request();
      if (!fine.isGranted) return;
    }
    await _permissionFor(permission)!.request();
  }

  Future<void> openSettings() => openAppSettings();

  /// Requests everything the 5-minute reporting service needs before it's
  /// safe to start. Android 14+ refuses to let a foreground service declare
  /// `FOREGROUND_SERVICE_TYPE_LOCATION` unless the app already holds location
  /// permission at that moment — starting it anyway doesn't just fail
  /// quietly, it crashes the whole app with
  /// ForegroundServiceDidNotStartInTimeException once the OS's startup grace
  /// period elapses. Returns whether location permission ended up granted
  /// (the minimum required to start the service at all).
  Future<bool> requestReportingPermissions() async {
    await request(ReliabilityPermission.notification);
    await request(ReliabilityPermission.location);
    await request(ReliabilityPermission.backgroundLocation);
    return isGranted(ReliabilityPermission.location);
  }

  Future<Map<ReliabilityPermission, bool>> statusSnapshot() async {
    final result = <ReliabilityPermission, bool>{};
    for (final permission in ReliabilityPermission.values) {
      result[permission] = await isGranted(permission);
    }
    return result;
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Future<bool> _isFullScreenIntentGranted() async {
    if (!_isAndroid) return true;
    try {
      final granted = await _fullScreenIntentChannel.invokeMethod<bool>('isGranted');
      return granted ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  Future<void> _openFullScreenIntentSettings() async {
    if (!_isAndroid) return;
    try {
      await _fullScreenIntentChannel.invokeMethod('openSettings');
    } on PlatformException {
      // Ignore: nothing more we can do if the OS refuses to open it.
    } on MissingPluginException {
      // Ignore: e.g. running in a widget test without the native channel.
    }
  }
}
