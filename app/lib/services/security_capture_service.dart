import 'dart:convert';

import 'package:location_bridge/location_bridge.dart';

import '../constants.dart';
import 'api_client.dart';
import 'crypto_service.dart';
import 'photo_capturer.dart';
import 'secure_store.dart';

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

  /// Captures, encrypts, and uploads a snapshot. Never throws — a failed
  /// capture (no camera permission, no location fix, offline) just means no
  /// event gets logged this time; it must never crash whatever flow
  /// (typically a failed-login handler) triggered it.
  Future<void> captureAndUpload() async {
    try {
      final deviceToken = await secureStore.deviceToken;
      final lekBytes = await secureStore.lekBytes;
      if (deviceToken == null || lekBytes == null) return;

      final key = cryptoService.keyFromBytes(lekBytes);
      final capturedAt = DateTime.now();

      final photoBytes = await photoCapturer.captureFrontPhoto();
      String? photoCiphertext;
      if (photoBytes != null) {
        photoCiphertext = await cryptoService.encrypt(base64Encode(photoBytes), key);
      }

      String? locationCiphertext;
      try {
        final fix = await locationBridge.getCurrentLocation(timeout: const Duration(seconds: 10));
        locationCiphertext = await cryptoService.encrypt(
          jsonEncode({'lat': fix.latitude, 'lng': fix.longitude}),
          key,
        );
      } catch (_) {
        // No fix available — still upload the photo alone if we have one.
      }

      if (photoCiphertext == null && locationCiphertext == null) return;

      final baseUrl = await secureStore.serverBaseUrl ?? defaultServerBaseUrl;
      final api = apiClientBuilder(baseUrl);
      await api.submitSecurityEvent(
        deviceToken: deviceToken,
        photoCiphertext: photoCiphertext,
        locationCiphertext: locationCiphertext,
        capturedAt: capturedAt,
      );
    } catch (_) {
      // Best-effort by design; see class doc.
    }
  }
}
