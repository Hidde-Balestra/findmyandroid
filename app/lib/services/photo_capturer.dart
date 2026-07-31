import 'dart:typed_data';

import 'package:camera/camera.dart';

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
/// Known hard limitation: the official `camera` plugin's Android
/// implementation requires a live Activity to check/request camera
/// permission (see CameraAndroidCameraxPlugin/SystemServicesManager) and
/// throws `PlatformException`/`IllegalStateException` otherwise — even when
/// permission is already granted. That means this only works when called
/// from the app's own foreground isolate (the in-app failed-login trigger);
/// called from the headless background service (the lock-screen trigger),
/// it will always fail. Exceptions are deliberately *not* swallowed here —
/// [SecurityCaptureService] logs the real cause instead of just recording
/// "no photo", which otherwise looks indistinguishable from a permission or
/// hardware problem.
class CameraPhotoCapturer implements PhotoCapturer {
  @override
  Future<Uint8List?> captureFrontPhoto() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;
    final front = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
    try {
      await controller.initialize();
      final file = await controller.takePicture();
      return await file.readAsBytes();
    } finally {
      await controller.dispose();
    }
  }
}
