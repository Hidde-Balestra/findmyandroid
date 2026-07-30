import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/device.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class RegisterResult {
  final String code;
  final String saltBase64;
  final String totpProvisioningUri;

  const RegisterResult({
    required this.code,
    required this.saltBase64,
    required this.totpProvisioningUri,
  });

  /// The raw base32 TOTP secret, for authenticator apps that only support
  /// typing/pasting a code rather than scanning a QR image.
  String get totpSecret => Uri.parse(totpProvisioningUri).queryParameters['secret'] ?? '';
}

class LoginResult {
  final String sessionToken;
  final String saltBase64;

  const LoginResult({required this.sessionToken, required this.saltBase64});
}

class PairDeviceResult {
  final String deviceId;
  final String deviceToken;

  const PairDeviceResult({required this.deviceId, required this.deviceToken});
}

/// Talks to the PHP backend. Every call that only submits/reads a single
/// device's own data uses that device's scoped API token; every call that
/// manages the account (pairing, history, queuing a ring) uses the
/// interactive account session obtained via [login].
class ApiClient {
  final String baseUrl;
  final http.Client _http;

  ApiClient({required this.baseUrl, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl/$path');

  Map<String, String> _bearer(String token) => {'Authorization': 'Bearer $token'};

  Future<RegisterResult> register() async {
    final response = await _http.post(_uri('register.php'));
    final json = _decode(response);
    return RegisterResult(
      code: json['code'] as String,
      saltBase64: json['salt'] as String,
      totpProvisioningUri: json['totpUri'] as String,
    );
  }

  Future<LoginResult> login({required String code, required String totp}) async {
    final response = await _http.post(
      _uri('login.php'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'totp': totp}),
    );
    final json = _decode(response);
    return LoginResult(
      sessionToken: json['sessionToken'] as String,
      saltBase64: json['salt'] as String,
    );
  }

  Future<PairDeviceResult> pairDevice({required String sessionToken, required String label}) async {
    final response = await _http.post(
      _uri('devices.php'),
      headers: {..._bearer(sessionToken), 'Content-Type': 'application/json'},
      body: jsonEncode({'label': label}),
    );
    final json = _decode(response);
    return PairDeviceResult(
      deviceId: json['deviceId'] as String,
      deviceToken: json['deviceToken'] as String,
    );
  }

  Future<List<Device>> listDevices(String sessionToken) async {
    final response = await _http.get(_uri('devices.php'), headers: _bearer(sessionToken));
    final json = _decode(response);
    return (json['devices'] as List).map((e) => Device.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> forgetDevice({required String sessionToken, required String deviceId}) async {
    await _http.delete(_uri('devices.php?deviceId=$deviceId'), headers: _bearer(sessionToken));
  }

  /// Submits one encrypted location sample. Called from the background
  /// check-in every 5 minutes using the device's own scoped token.
  Future<void> submitLocation({
    required String deviceToken,
    required String ciphertextBlob,
    required DateTime capturedAt,
  }) async {
    final response = await _http.post(
      _uri('locations.php'),
      headers: {..._bearer(deviceToken), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'ciphertext': ciphertextBlob,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
      }),
    );
    _decode(response);
  }

  Future<List<LocationPoint>> listLocations({
    required String sessionToken,
    required String deviceId,
    int limit = 50,
  }) async {
    final response = await _http.get(
      _uri('locations.php?deviceId=$deviceId&limit=$limit'),
      headers: _bearer(sessionToken),
    );
    final json = _decode(response);
    return (json['locations'] as List).map((e) => LocationPoint.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Queues a "play sound" command for [deviceId], picked up next time that
  /// device polls (at most 5 minutes later, piggybacked on its own
  /// check-in — see README for why there's no push/WebSocket channel).
  Future<void> queueRing({required String sessionToken, required String deviceId}) async {
    final response = await _http.post(
      _uri('ring.php'),
      headers: {..._bearer(sessionToken), 'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': deviceId}),
    );
    _decode(response);
  }

  /// Polled by the device's own background check-in. Returns true if a ring
  /// command was pending (and is now marked delivered server-side).
  Future<bool> pollRing(String deviceToken) async {
    final response = await _http.get(_uri('ring.php'), headers: _bearer(deviceToken));
    final json = _decode(response);
    return json['ring'] == true;
  }

  /// Submits a security snapshot (see SecurityCaptureService) using the
  /// device's own scoped token — at least one of the two ciphertexts must
  /// be provided.
  Future<void> submitSecurityEvent({
    required String deviceToken,
    required DateTime capturedAt,
    String? photoCiphertext,
    String? locationCiphertext,
  }) async {
    final response = await _http.post(
      _uri('security_events.php'),
      headers: {..._bearer(deviceToken), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'photoCiphertext': ?photoCiphertext,
        'locationCiphertext': ?locationCiphertext,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
      }),
    );
    _decode(response);
  }

  Future<List<SecurityEvent>> listSecurityEvents({
    required String sessionToken,
    required String deviceId,
    int limit = 20,
  }) async {
    final response = await _http.get(
      _uri('security_events.php?deviceId=$deviceId&limit=$limit'),
      headers: _bearer(sessionToken),
    );
    final json = _decode(response);
    return (json['events'] as List).map((e) => SecurityEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Invalid server response', statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(json['message'] as String? ?? 'Request failed', statusCode: response.statusCode);
    }
    return json;
  }
}
