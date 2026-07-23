import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/crypto_service.dart';
import '../services/permission_service.dart';
import '../services/ring_service.dart';
import '../services/secure_store.dart';
import '../services/update_service.dart';
import '../constants.dart';

final secureStoreProvider = Provider((ref) => SecureStore());
final cryptoServiceProvider = Provider((ref) => CryptoService());
final permissionServiceProvider = Provider((ref) => PermissionService());
final updateServiceProvider = Provider((ref) => UpdateService());
final ringServiceProvider = Provider((ref) => RingService());

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
