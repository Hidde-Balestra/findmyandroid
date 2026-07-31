import 'dart:convert';
import 'dart:typed_data';

import 'package:findmyandroid/services/api_client.dart';
import 'package:findmyandroid/services/crypto_service.dart';
import 'package:findmyandroid/services/security_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:location_bridge/location_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_location_bridge.dart';
import '../fakes/fake_photo_capturer.dart';
import '../fakes/fake_secure_store.dart';

void main() {
  final crypto = CryptoService();
  final lekBytes = List<int>.generate(32, (i) => i);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('captureAndUpload', () {
    test('does nothing when this device has no device token yet', () async {
      var uploadCalled = false;
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: Uint8List.fromList([1, 2, 3])),
        secureStore: FakeSecureStore(deviceTokenValue: null, lekBytesValue: lekBytes),
        apiClientBuilder: (baseUrl) {
          uploadCalled = true;
          return ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => http.Response('{}', 200)));
        },
      );

      await service.captureAndUpload();

      expect(uploadCalled, isFalse);
    });

    test('does nothing when the location-encryption key is not cached', () async {
      var uploadCalled = false;
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: Uint8List.fromList([1, 2, 3])),
        secureStore: FakeSecureStore(deviceTokenValue: 'device-token', lekBytesValue: null),
        apiClientBuilder: (baseUrl) {
          uploadCalled = true;
          return ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => http.Response('{}', 200)));
        },
      );

      await service.captureAndUpload();

      expect(uploadCalled, isFalse);
    });

    test('never throws even if the photo capture and upload both fail', () async {
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: null),
        secureStore: FakeSecureStore(deviceTokenValue: 'device-token', lekBytesValue: lekBytes),
        apiClientBuilder: (baseUrl) => ApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((_) async => http.Response('{"message":"boom"}', 500)),
        ),
      );

      await expectLater(service.captureAndUpload(), completes);
    });

    test('a thrown photo-capture error does not stop the location upload', () async {
      // Regression: the official camera plugin can only run with a live
      // Activity attached, so calling this from the headless background
      // isolate (the lock-screen trigger) always throws. That must not
      // abort the whole capture -- location should still upload.
      http.Request? capturedRequest;
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(throwsError: Exception('Activity must be set to request camera permissions.')),
        locationBridge: FakeLocationBridge(
          fix: LocationFix(latitude: 52.1, longitude: 5.1, timestamp: DateTime.now(), provider: 'gps'),
        ),
        secureStore: FakeSecureStore(
          deviceTokenValue: 'device-token',
          lekBytesValue: lekBytes,
          serverBaseUrlValue: 'https://example.invalid',
        ),
        apiClientBuilder: (baseUrl) => ApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            capturedRequest = request;
            return http.Response('{"message":"stored"}', 201);
          }),
        ),
      );

      await service.captureAndUpload();

      expect(capturedRequest, isNotNull);
      final body = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(body.containsKey('photoCiphertext'), isFalse);
      expect(body['locationCiphertext'], isNotNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(lastSecuritySnapshotStatusPrefsKey), contains('Uploaded'));
    });

    test('uploads an encrypted photo that decrypts back to the captured bytes', () async {
      final photoBytes = Uint8List.fromList(List.generate(64, (i) => i % 256));
      http.Request? capturedRequest;

      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: photoBytes),
        secureStore: FakeSecureStore(
          deviceTokenValue: 'device-token-abc',
          lekBytesValue: lekBytes,
          serverBaseUrlValue: 'https://example.invalid',
        ),
        apiClientBuilder: (baseUrl) => ApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            capturedRequest = request;
            return http.Response('{"message":"stored"}', 201);
          }),
        ),
      );

      await service.captureAndUpload();

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.url.path, endsWith('security_events.php'));
      expect(capturedRequest!.headers['Authorization'], 'Bearer device-token-abc');

      final body = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(body['photoCiphertext'], isNotNull);
      expect(body.containsKey('capturedAt'), isTrue);

      // No location plugin is available in this test environment, so only
      // the photo should have been encrypted and sent.
      expect(body.containsKey('locationCiphertext'), isFalse);

      final key = crypto.keyFromBytes(lekBytes);
      final decryptedBase64 = await crypto.decrypt(body['photoCiphertext'] as String, key);
      expect(base64Decode(decryptedBase64), photoBytes);
    });
  });

  group('status reporting', () {
    // Regression coverage for a real observability gap: captureAndUpload()
    // deliberately never throws or otherwise signals its caller (see class
    // doc), which previously meant a failed/skipped attempt was completely
    // invisible. Every outcome must now be recorded so it can be surfaced
    // in Settings instead of looking like the feature silently does nothing.
    test('records a status when skipped because the device is not paired', () async {
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: Uint8List.fromList([1, 2, 3])),
        secureStore: FakeSecureStore(deviceTokenValue: null, lekBytesValue: lekBytes),
      );

      await service.captureAndUpload();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(lastSecuritySnapshotStatusPrefsKey), contains('not paired'));
    });

    test('records a status when neither a photo nor a location was obtained', () async {
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: null),
        secureStore: FakeSecureStore(deviceTokenValue: 'device-token', lekBytesValue: lekBytes),
      );

      await service.captureAndUpload();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(lastSecuritySnapshotStatusPrefsKey), contains('neither a photo nor a location'));
    });

    test('records a success status after a successful upload', () async {
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: Uint8List.fromList([1, 2, 3])),
        secureStore: FakeSecureStore(
          deviceTokenValue: 'device-token',
          lekBytesValue: lekBytes,
          serverBaseUrlValue: 'https://example.invalid',
        ),
        apiClientBuilder: (baseUrl) => ApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((_) async => http.Response('{"message":"stored"}', 201)),
        ),
      );

      await service.captureAndUpload();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(lastSecuritySnapshotStatusPrefsKey), contains('Uploaded'));
    });

    test('records a failure status when the upload itself fails', () async {
      final service = SecurityCaptureService(
        photoCapturer: FakePhotoCapturer(photoBytes: Uint8List.fromList([1, 2, 3])),
        secureStore: FakeSecureStore(
          deviceTokenValue: 'device-token',
          lekBytesValue: lekBytes,
          serverBaseUrlValue: 'https://example.invalid',
        ),
        apiClientBuilder: (baseUrl) => ApiClient(
          baseUrl: baseUrl,
          httpClient: MockClient((_) async => http.Response('{"message":"server exploded"}', 500)),
        ),
      );

      await service.captureAndUpload();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(lastSecuritySnapshotStatusPrefsKey), contains('Failed'));
    });
  });
}
