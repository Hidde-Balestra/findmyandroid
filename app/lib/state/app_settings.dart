import 'dart:async';

import 'package:device_admin_bridge/device_admin_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModePrefsKey = 'theme_mode';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModePrefsKey);
    state = ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePrefsKey, mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

const _securitySnapshotThresholdPrefsKey = 'security_snapshot_threshold';

/// How many consecutive failed attempts — either the in-app account-code/
/// TOTP login, or (if Device Administrator is activated) the device's own
/// lock-screen credential — trigger a security snapshot (front-camera photo
/// + location, encrypted, viewable later in the device's security log). 0
/// disables the feature entirely; default is 1 (every single failed
/// attempt). Also pushed to the native side (see DeviceAdminBridge), which
/// has no access to Dart's SharedPreferences and needs its own copy to
/// evaluate lock-screen failures with no Flutter isolate necessarily
/// running at that moment.
class SecuritySnapshotThresholdNotifier extends StateNotifier<int> {
  final DeviceAdminBridge _deviceAdminBridge;

  SecuritySnapshotThresholdNotifier({DeviceAdminBridge? deviceAdminBridge})
      : _deviceAdminBridge = deviceAdminBridge ?? DeviceAdminBridge(),
        super(1) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_securitySnapshotThresholdPrefsKey) ?? 1;
    unawaited(_deviceAdminBridge.setThreshold(state));
  }

  Future<void> setThreshold(int threshold) async {
    state = threshold;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_securitySnapshotThresholdPrefsKey, threshold);
    unawaited(_deviceAdminBridge.setThreshold(threshold));
  }
}

final securitySnapshotThresholdProvider =
    StateNotifierProvider<SecuritySnapshotThresholdNotifier, int>(
  (ref) => SecuritySnapshotThresholdNotifier(),
);
