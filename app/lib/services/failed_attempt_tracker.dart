import 'package:shared_preferences/shared_preferences.dart';

/// Counts consecutive failed account-code/TOTP attempts on this device, so
/// the security-snapshot feature (see SecurityCaptureService) knows when the
/// configured threshold has been crossed. Persisted across app restarts;
/// reset on the next successful login.
class FailedAttemptTracker {
  static const _prefsKey = 'failed_login_attempts';

  /// Increments the counter and returns the new value.
  Future<int> recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_prefsKey) ?? 0) + 1;
    await prefs.setInt(_prefsKey, next);
    return next;
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, 0);
  }

  Future<int> get count async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsKey) ?? 0;
  }
}
