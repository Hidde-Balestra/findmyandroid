import 'package:findmyandroid/services/secure_store.dart';

/// Test double avoiding real flutter_secure_storage platform channel calls.
/// Overrides every getter SecureStore exposes rather than extending its
/// real backing storage.
class FakeSecureStore implements SecureStore {
  String? deviceTokenValue;
  List<int>? lekBytesValue;
  String? serverBaseUrlValue;
  String? deviceIdValue;
  String? accountSaltValue;

  FakeSecureStore({
    this.deviceTokenValue,
    this.lekBytesValue,
    this.serverBaseUrlValue,
    this.deviceIdValue,
    this.accountSaltValue,
  });

  @override
  Future<String?> get deviceToken async => deviceTokenValue;

  @override
  Future<List<int>?> get lekBytes async => lekBytesValue;

  @override
  Future<String?> get serverBaseUrl async => serverBaseUrlValue;

  @override
  Future<String?> get deviceId async => deviceIdValue;

  @override
  Future<String?> get accountSalt async => accountSaltValue;

  @override
  Future<bool> get isPaired async => deviceTokenValue != null;

  @override
  Future<void> setServerBaseUrl(String url) async => serverBaseUrlValue = url;

  @override
  Future<void> savePairing({
    required String deviceId,
    required String deviceToken,
    required String accountSalt,
    required List<int> lekBytes,
  }) async {
    deviceIdValue = deviceId;
    deviceTokenValue = deviceToken;
    accountSaltValue = accountSalt;
    lekBytesValue = lekBytes;
  }

  @override
  Future<void> clear() async {
    deviceTokenValue = null;
    lekBytesValue = null;
    deviceIdValue = null;
    accountSaltValue = null;
  }
}
