import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:findmyandroid/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final crypto = CryptoService();
  final salt = base64Encode(List<int>.generate(16, (i) => i));

  group('deriveKey', () {
    test('is deterministic for the same code and salt', () async {
      final keyA = await crypto.deriveKey(code: 'correct-horse-battery-staple', saltBase64: salt);
      final keyB = await crypto.deriveKey(code: 'correct-horse-battery-staple', saltBase64: salt);
      expect(await keyA.extractBytes(), await keyB.extractBytes());
    });

    test('differs for a different code', () async {
      final keyA = await crypto.deriveKey(code: 'code-one', saltBase64: salt);
      final keyB = await crypto.deriveKey(code: 'code-two', saltBase64: salt);
      expect(await keyA.extractBytes(), isNot(await keyB.extractBytes()));
    });

    test('differs for a different salt', () async {
      final otherSalt = base64Encode(List<int>.generate(16, (i) => i + 1));
      final keyA = await crypto.deriveKey(code: 'same-code', saltBase64: salt);
      final keyB = await crypto.deriveKey(code: 'same-code', saltBase64: otherSalt);
      expect(await keyA.extractBytes(), isNot(await keyB.extractBytes()));
    });
  });

  group('encrypt/decrypt round-trip', () {
    late SecretKey key;

    setUpAll(() async {
      key = await crypto.deriveKey(code: 'account-code', saltBase64: salt);
    });

    test('decrypts back to the original plaintext', () async {
      const sample = '{"lat":52.37,"lng":4.90}';
      final blob = await crypto.encrypt(sample, key);
      final decrypted = await crypto.decrypt(blob, key);
      expect(decrypted, sample);
    });

    test('produces a different ciphertext each time (random nonce)', () async {
      const sample = 'same plaintext';
      final blobA = await crypto.encrypt(sample, key);
      final blobB = await crypto.encrypt(sample, key);
      expect(blobA, isNot(blobB));
    });

    test('fails to decrypt with the wrong key', () async {
      final wrongKey = await crypto.deriveKey(code: 'a-different-code', saltBase64: salt);
      final blob = await crypto.encrypt('secret location', key);
      expect(() => crypto.decrypt(blob, wrongKey), throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('keyFromBytes round-trips through raw bytes like keyBytes produces', () async {
      final bytes = await crypto.keyBytes(key);
      final restoredKey = crypto.keyFromBytes(bytes);
      final blob = await crypto.encrypt('round trip via cached bytes', key);
      final decrypted = await crypto.decrypt(blob, restoredKey);
      expect(decrypted, 'round trip via cached bytes');
    });
  });

  group('LocationSample json', () {
    test('round-trips through toJson/fromJson', () {
      final sample = LocationSample(
        latitude: 52.379189,
        longitude: 4.899431,
        accuracy: 12.5,
        capturedAt: DateTime.utc(2026, 7, 23, 10, 30),
      );
      final restored = LocationSample.fromJson(sample.toJson());
      expect(restored.latitude, sample.latitude);
      expect(restored.longitude, sample.longitude);
      expect(restored.accuracy, sample.accuracy);
      expect(restored.capturedAt, sample.capturedAt);
    });
  });
}
