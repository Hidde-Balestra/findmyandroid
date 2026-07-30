import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:location_bridge/location_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import 'api_client.dart';
import 'crypto_service.dart';
import 'photo_capturer.dart';
import 'secure_store.dart';

/// SharedPreferences key holding a human-readable summary of the last
/// captureAndUpload() attempt (e.g. "Uploaded photo+location at 14:02" or
/// "Failed: camera returned no photo"). captureAndUpload() never throws or
/// otherwise surfaces errors to its caller by design (see below), so this is
/// the only way to tell whether the feature actually did anything — shown
/// in Settings, and visible via `adb logcat` (tag "flutter") either way.
const lastSecuritySnapshotStatusPrefsKey = 'last_security_snapshot_status';

/// Captures a security snapshot (front-camera photo + current location,
/// both end-to-end encrypted the same way as ordinary location check-ins)
/// after too many failed account-code/TOTP attempts on this device — see
/// FailedAttemptTracker for the threshold logic and login_dialog.dart for
/// where it's triggered from. Documented, not hidden: this is the same
/// pattern legitimate anti-theft tools (Cerberus, Prey, Find My Device) use
/// — a failed-login security log the account owner can review later, not a
/// covert always-on capability. It uses the device's own scoped token, the
/// same one the background check-in uses, so it works even for someone who
/// never completed an interactive login.
class SecurityCaptureService {
  final PhotoCapturer photoCapturer;
  final LocationBridge locationBridge;
  final CryptoService cryptoService;
  final SecureStore secureStore;
  final ApiClient Function(String baseUrl) apiClientBuilder;

  SecurityCaptureService({
    required this.photoCapturer,
    LocationBridge? locationBridge,
    CryptoService? cryptoService,
    SecureStore? secureStore,
    ApiClient Function(String baseUrl)? apiClientBuilder,
  })  : locationBridge = locationBridge ?? LocationBridge(),
        cryptoService = cryptoService ?? CryptoService(),
        secureStore = secureStore ?? SecureStore(),
        apiClientBuilder = apiClientBuilder ?? ((baseUrl) => ApiClient(baseUrl: baseUrl));

  Future<void> _reportStatus(String status) async {
    debugPrint('[SecurityCapture] $status');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastSecuritySnapshotStatusPrefsKey, '$status (${DateTime.now().toLocal()})');
    } catch (_) {
      // Losing the status text isn't worth failing the whole attempt over.
    }
  }

  /// Captures, encrypts, and uploads a snapshot. Never throws — a failed
  /// capture (no camera permission, no location fix, offline) just means no
  /// event gets logged this time; it must never crash whatever flow
  /// (typically a failed-login handler) triggered it. Every outcome is
  /// still recorded via [_reportStatus] so it's never a silent black box.
  Future<void> captureAndUpload() async {
    try {
      final deviceToken = await secureStore.deviceToken;
      final lekBytes = await secureStore.lekBytes;
      if (deviceToken == null || lekBytes == null) {
        await _reportStatus('Skipped: this device is not paired yet');
        return;
      }

      final key = cryptoService.keyFromBytes(lekBytes);
      final capturedAt = DateTime.now();

      final photoBytes = await photoCapturer.captureFrontPhoto();
      String? photoCiphertext;
      if (photoBytes != null) {
        photoCiphertext = await cryptoService.encrypt(base64Encode(photoBytes), key);
      } else {
        debugPrint('[SecurityCapture] No photo captured (camera permission denied, no camera, or capture failed)');
      }

      String? locationCiphertext;
      try {
        final fix = await locationBridge.getCurrentLocation(timeout: const Duration(seconds: 10));
        locationCiphertext = await cryptoService.encrypt(
          jsonEncode({'lat': fix.latitude, 'lng': fix.longitude}),
          key,
        );
      } catch (e) {
        debugPrint('[SecurityCapture] No location fix available: $e');
      }

      if (photoCiphertext == null && locationCiphertext == null) {
        await _reportStatus('Failed: got neither a photo nor a location fix');
        return;
      }

      final baseUrl = await secureStore.serverBaseUrl ?? defaultServerBaseUrl;
      final api = apiClientBuilder(baseUrl);
      await api.submitSecurityEvent(
        deviceToken: deviceToken,
        photoCiphertext: photoCiphertext,
        locationCiphertext: locationCiphertext,
        capturedAt: capturedAt,
      );

      final parts = [
        if (photoCiphertext != null) 'photo',
        if (locationCiphertext != null) 'location',
      ].join(' + ');
      await _reportStatus('Uploaded $parts successfully');
    } catch (e) {
      await _reportStatus('Failed: $e');
    }
  }
}
