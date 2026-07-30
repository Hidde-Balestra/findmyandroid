import 'dart:convert';
import 'dart:typed_data';

import 'package:findmyandroid/services/api_client.dart';
import 'package:findmyandroid/services/crypto_service.dart';
import 'package:findmyandroid/services/security_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fakes/fake_photo_capturer.dart';
import '../fakes/fake_secure_store.dart';

void main() {
  final crypto = CryptoService();
  final lekBytes = List<int>.generate(32, (i) => i);

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
}
