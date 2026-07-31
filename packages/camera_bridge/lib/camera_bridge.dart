import 'package:flutter/services.dart';

/// Thrown when a capture attempt fails outright (permission not granted, no
/// camera responded, capture session/request failed, or it timed out). A
/// missing front camera on this device is not an error -- [CameraBridge]
/// returns `null` for that instead, matching `PhotoCapturer`'s existing
/// contract in the app.
class CameraBridgeException implements Exception {
  final String message;

  const CameraBridgeException(this.message);

  @override
  String toString() => 'CameraBridgeException: $message';
}

/// Captures a single still frame from the front camera via Android's
/// Camera2 API directly, bypassing the official `camera` Flutter plugin.
///
/// The official plugin's Android implementation requires a live Activity to
/// check/request camera permission and throws otherwise -- even when
/// permission is already granted (see `SystemServicesManager` in
/// `camera_android_camerax`). That makes it unusable from
/// `flutter_background_service`'s headless isolate, which is exactly where
/// this app's lock-screen security-snapshot trigger runs. Camera2 has no
/// such requirement, so this works identically from the app's own UI engine
/// or that headless background isolate.
class CameraBridge {
  static const MethodChannel _channel = MethodChannel('nl.hiddebalestra.camera_bridge/camera');

  /// Returns the captured JPEG bytes, `null` if this device has no camera at
  /// all, or throws [CameraBridgeException] for any other failure (camera
  /// permission not granted, capture failed, timed out).
  Future<Uint8List?> captureFrontPhoto() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('captureFrontPhoto');
      return bytes;
    } on PlatformException catch (e) {
      throw CameraBridgeException(e.message ?? 'Unknown camera error');
    }
  }
}
