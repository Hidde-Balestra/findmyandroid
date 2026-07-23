import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything this app persists on-device, all via Android Keystore-backed
/// encrypted storage. Deliberately never stores the raw account code or TOTP
/// secret — only the derived location-encryption key and the device's own
/// scoped API token, so a stolen/rooted device can't be used to reconstruct
/// the account credentials.
class SecureStore {
  static const _keyDeviceId = 'device_id';
  static const _keyDeviceToken = 'device_token';
  static const _keyAccountSalt = 'account_salt';
  static const _keyLekBytes = 'lek_bytes';
  static const _keyServerBaseUrl = 'server_base_url';

  final FlutterSecureStorage _storage;

  SecureStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  Future<void> savePairing({
    required String deviceId,
    required String deviceToken,
    required String accountSalt,
    required List<int> lekBytes,
  }) async {
    await Future.wait([
      _storage.write(key: _keyDeviceId, value: deviceId),
      _storage.write(key: _keyDeviceToken, value: deviceToken),
      _storage.write(key: _keyAccountSalt, value: accountSalt),
      _storage.write(key: _keyLekBytes, value: base64Encode(lekBytes)),
    ]);
  }

  Future<String?> get deviceId => _storage.read(key: _keyDeviceId);
  Future<String?> get deviceToken => _storage.read(key: _keyDeviceToken);
  Future<String?> get accountSalt => _storage.read(key: _keyAccountSalt);

  Future<List<int>?> get lekBytes async {
    final value = await _storage.read(key: _keyLekBytes);
    if (value == null) return null;
    return base64Decode(value);
  }

  Future<bool> get isPaired async => (await deviceToken) != null;

  Future<void> setServerBaseUrl(String url) => _storage.write(key: _keyServerBaseUrl, value: url);
  Future<String?> get serverBaseUrl => _storage.read(key: _keyServerBaseUrl);

  /// "Forget this device": wipes everything, including the cached LEK. The
  /// account itself is untouched server-side; the phone just stops being
  /// paired to it.
  Future<void> clear() => _storage.deleteAll();
}
