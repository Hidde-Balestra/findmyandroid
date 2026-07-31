import 'dart:typed_data';

import 'package:camera_bridge/camera_bridge.dart';

/// Abstraction over actually taking a photo, so [SecurityCaptureService]'s
/// orchestration logic (encrypt, upload, threshold handling) can be unit
/// tested with a fake instead of real camera hardware.
abstract class PhotoCapturer {
  Future<Uint8List?> captureFrontPhoto();
}

/// Captures a single still frame from the front camera with no preview ever
/// shown on screen — used for the security-snapshot feature (see
/// SecurityCaptureService). Note this doesn't make the capture invisible:
/// Android has shown a mandatory camera-in-use indicator since Android 12,
/// and many devices/regions (e.g. Japan, South Korea) always play an
/// audible shutter sound regardless of what an app does. This class doesn't
/// attempt to suppress either — those are OS-level anti-covert-surveillance
/// protections, not bugs to work around.
///
/// Backed by the local `camera_bridge` plugin (Camera2 directly) rather than
/// the official `camera` package: that plugin's Android implementation
/// requires a live Activity to check/request camera permission and throws
/// otherwise — even when permission is already granted — which made it
/// unusable from the headless background isolate the lock-screen trigger
/// runs in (only the in-app login trigger, which has a real Activity, ever
/// worked). `camera_bridge` needs only a Context, so both triggers can now
/// actually capture a photo.
class CameraPhotoCapturer implements PhotoCapturer {
  final CameraBridge _cameraBridge;

  CameraPhotoCapturer({CameraBridge? cameraBridge}) : _cameraBridge = cameraBridge ?? CameraBridge();

  @override
  Future<Uint8List?> captureFrontPhoto() => _cameraBridge.captureFrontPhoto();
}
