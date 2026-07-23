import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:location_bridge/location_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/api_client.dart';
import '../services/crypto_service.dart';
import '../services/ring_service.dart';
import '../services/secure_store.dart';

const lastCheckInPrefsKey = 'last_check_in_summary';

/// Configures the persistent foreground service that reports location every
/// 5 minutes. A foreground service (not WorkManager) is required because
/// WorkManager periodic tasks can't run more often than every 15 minutes.
Future<void> configureBackgroundService(FlutterBackgroundService service) async {
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Find My Android',
      initialNotificationContent: 'Waiting for the first location check-in…',
      foregroundServiceTypes: const [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(onForeground: _onStart, onBackground: (_) async => true),
  );
}

/// Updates the persistent notification when running as an Android foreground
/// service (a no-op elsewhere — iOS has no equivalent, and this also keeps
/// the function safe to call from tests that don't run inside the service).
Future<void> _updateNotification(ServiceInstance service, String content) async {
  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(title: 'Find My Android', content: content);
  }
}

/// Entry point run in the background isolate. Must be a top-level/static
/// function and marked as a VM entry point so it survives tree-shaking.
/// Plugins declared in pubspec.yaml (including the local `location_bridge`
/// and `flutter_secure_storage`) are auto-registered on this isolate's
/// FlutterEngine the same way they are on the UI engine — no extra manual
/// registration step is needed.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  final secureStore = SecureStore();
  final cryptoService = CryptoService();
  final ringService = RingService();
  final locationBridge = LocationBridge();

  Future<void> tick() async {
    try {
      final deviceToken = await secureStore.deviceToken;
      final baseUrl = await secureStore.serverBaseUrl ?? defaultServerBaseUrl;
      final lekBytes = await secureStore.lekBytes;
      if (deviceToken == null || lekBytes == null) {
        await _updateNotification(service, 'Not paired yet — open the app to finish setup.');
        return;
      }

      final apiClient = ApiClient(baseUrl: baseUrl);
      final fix = await locationBridge.getCurrentLocation();
      final sample = LocationSample(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        capturedAt: DateTime.now(),
      );
      final key = cryptoService.keyFromBytes(lekBytes);
      final ciphertext = await cryptoService.encrypt(sample.toJson(), key);

      await apiClient.submitLocation(
        deviceToken: deviceToken,
        ciphertextBlob: ciphertext,
        capturedAt: sample.capturedAt,
      );

      final ringPending = await apiClient.pollRing(deviceToken);
      if (ringPending) {
        await ringService.init();
        await ringService.ringNow(
          title: 'Find My Android',
          body: 'Someone asked this phone to play a sound.',
          stopButtonLabel: 'Stop',
        );
      }

      final summary = 'Last check-in: ${DateTime.now().toLocal()}';
      await _updateNotification(service, summary);
      (await SharedPreferences.getInstance()).setString(lastCheckInPrefsKey, summary);
    } catch (_) {
      // Swallow errors: a single failed check-in (offline, GPS unavailable,
      // server unreachable) must not crash the long-running foreground
      // service — it just tries again on the next tick.
      final summary =
          'Last check-in failed at ${DateTime.now().toLocal()} — retrying in ${reportingInterval.inMinutes} min.';
      await _updateNotification(service, summary);
      (await SharedPreferences.getInstance()).setString(lastCheckInPrefsKey, summary);
    }
  }

  unawaited(tick());
  Timer.periodic(reportingInterval, (_) => unawaited(tick()));

  service.on('stopService').listen((_) => service.stopSelf());
}
