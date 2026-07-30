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

/// How many consecutive failed account-code/TOTP attempts on this device
/// trigger a security snapshot (front-camera photo + location, encrypted,
/// viewable later in the device's security log). 0 disables the feature
/// entirely; default is 1 (every single failed attempt).
class SecuritySnapshotThresholdNotifier extends StateNotifier<int> {
  SecuritySnapshotThresholdNotifier() : super(1) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_securitySnapshotThresholdPrefsKey) ?? 1;
  }

  Future<void> setThreshold(int threshold) async {
    state = threshold;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_securitySnapshotThresholdPrefsKey, threshold);
  }
}

final securitySnapshotThresholdProvider =
    StateNotifierProvider<SecuritySnapshotThresholdNotifier, int>(
  (ref) => SecuritySnapshotThresholdNotifier(),
);
