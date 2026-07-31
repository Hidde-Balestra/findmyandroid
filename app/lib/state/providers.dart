import 'package:device_admin_bridge/device_admin_bridge.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/crypto_service.dart';
import '../services/failed_attempt_tracker.dart';
import '../services/permission_service.dart';
import '../services/photo_capturer.dart';
import '../services/ring_service.dart';
import '../services/secure_store.dart';
import '../services/security_capture_service.dart';
import '../services/update_service.dart';
import '../constants.dart';

final secureStoreProvider = Provider((ref) => SecureStore());
final cryptoServiceProvider = Provider((ref) => CryptoService());
final permissionServiceProvider = Provider((ref) => PermissionService());
final updateServiceProvider = Provider((ref) => UpdateService());
final ringServiceProvider = Provider((ref) => RingService());
final failedAttemptTrackerProvider = Provider((ref) => FailedAttemptTracker());
final deviceAdminBridgeProvider = Provider((ref) => DeviceAdminBridge());

/// Captures+uploads a security snapshot after too many failed login
/// attempts (see FailedAttemptTracker/SecuritySnapshotThresholdNotifier).
/// Overridable in tests with a fake PhotoCapturer/ApiClient.
final securityCaptureServiceProvider = Provider(
  (ref) => SecurityCaptureService(photoCapturer: CameraPhotoCapturer()),
);

/// Server base URL, defaulting to [defaultServerBaseUrl] until the user
/// overrides it (e.g. for self-hosting) in Settings.
final serverBaseUrlProvider = FutureProvider((ref) async {
  final store = ref.watch(secureStoreProvider);
  return await store.serverBaseUrl ?? defaultServerBaseUrl;
});

final apiClientProvider = Provider((ref) {
  final baseUrl = ref.watch(serverBaseUrlProvider).valueOrNull ?? defaultServerBaseUrl;
  return ApiClient(baseUrl: baseUrl);
});

/// Whether this phone has completed pairing (has a device token + cached
/// location-encryption key). Re-evaluated whenever [pairingRefreshProvider]
/// is bumped (e.g. right after onboarding finishes, or "forget this device").
final pairingRefreshProvider = StateProvider((ref) => 0);

final isPairedProvider = FutureProvider((ref) async {
  ref.watch(pairingRefreshProvider);
  final store = ref.watch(secureStoreProvider);
  return store.isPaired;
});

final backgroundServiceProvider = Provider((ref) => FlutterBackgroundService());

/// Whether the 5-minute reporting service is currently running. Re-evaluated
/// whenever [pairingRefreshProvider] is bumped, so the UI notices right after
/// [startReportingIfPossible] (or "forget this device") changes it.
final isReportingProvider = FutureProvider((ref) async {
  ref.watch(pairingRefreshProvider);
  final service = ref.watch(backgroundServiceProvider);
  return service.isRunning();
});

/// Starts the background reporting service, but only after confirming
/// location permission is actually granted — starting it without that
/// permission doesn't fail quietly, it crashes the app once Android's
/// foreground-service startup grace period elapses (see
/// PermissionService.requestReportingPermissions). Returns whether the
/// service is running afterwards.
Future<bool> startReportingIfPossible(WidgetRef ref) async {
  final permissionService = ref.read(permissionServiceProvider);
  final granted = await permissionService.requestReportingPermissions();
  final service = ref.read(backgroundServiceProvider);
  if (granted && !await service.isRunning()) {
    await service.startService();
  }
  ref.read(pairingRefreshProvider.notifier).state++;
  return service.isRunning();
}
