import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for location samples.
///
/// The location-encryption key (LEK) is derived client-side only, via
/// PBKDF2-HMAC-SHA256, from the account code plus a per-account salt the
/// server hands back at registration (the salt is not secret). PBKDF2 rather
/// than a memory-hard KDF like Argon2id is a deliberate choice: the account
/// code is a 160-bit server-generated random value, not a human-guessable
/// password, so there is no dictionary/brute-force risk for a slow KDF to
/// defend against — and PBKDF2 is natively supported by browsers'
/// SubtleCrypto, which lets the web viewer derive the identical key with
/// zero extra dependencies (no WASM/CDN Argon2 library to trust or load).
/// The server never sees the code in plaintext (only receives it once, over
/// TLS, to hash for login) and never sees the LEK or any decrypted
/// location: it only ever stores/serves the opaque ciphertext blob this
/// class produces.
class CryptoService {
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _pbkdf2Iterations = 210000; // matches the web viewer's SubtleCrypto derivation

  final _kdf = Pbkdf2.hmacSha256(iterations: _pbkdf2Iterations, bits: 256);
  final _cipher = AesGcm.with256bits();

  /// Derives the 256-bit location-encryption key from the account code and
  /// the account's public salt. Deterministic: the same code+salt always
  /// yields the same key, which is what lets a second device (or the web
  /// viewer) decrypt history just by knowing the code. The code is
  /// lowercased first — the backend normalizes case the same way for login,
  /// since mobile keyboards love to autocapitalize the first character of a
  /// pasted/typed code — so a differently-cased retype still derives the
  /// identical key.
  Future<SecretKey> deriveKey({required String code, required String saltBase64}) {
    final salt = base64Decode(saltBase64);
    return _kdf.deriveKeyFromPassword(password: code.toLowerCase(), nonce: salt);
  }

  /// Encrypts [plaintext] with a fresh random nonce and returns a single
  /// base64 blob (nonce + ciphertext + auth tag) suitable for sending to the
  /// backend as-is.
  Future<String> encrypt(String plaintext, SecretKey key) async {
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return base64Encode(secretBox.concatenation());
  }

  /// Reverses [encrypt]. Throws [SecretBoxAuthenticationError] if the blob
  /// was tampered with or the key is wrong.
  Future<String> decrypt(String blobBase64, SecretKey key) async {
    final bytes = base64Decode(blobBase64);
    final secretBox = SecretBox.fromConcatenation(
      bytes,
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final plainBytes = await _cipher.decrypt(secretBox, secretKey: key);
    return utf8.decode(plainBytes);
  }

  Future<List<int>> keyBytes(SecretKey key) async {
    final data = await key.extractBytes();
    return data;
  }

  SecretKey keyFromBytes(List<int> bytes) => SecretKeyData(bytes);
}

/// A single location fix plus its capture time, the unit this app encrypts
/// and stores — decoupled from [LocationFix] so encoding/decoding doesn't
/// depend on the native plugin's type.
class LocationSample {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime capturedAt;

  const LocationSample({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracy,
  });

  String toJson() => jsonEncode({
        'lat': latitude,
        'lng': longitude,
        'accuracy': accuracy,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
      });

  static LocationSample fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return LocationSample(
      latitude: (map['lat'] as num).toDouble(),
      longitude: (map['lng'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      capturedAt: DateTime.parse(map['capturedAt'] as String),
    );
  }
}
