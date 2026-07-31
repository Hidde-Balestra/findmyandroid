import 'dart:typed_data';

import 'package:findmyandroid/services/photo_capturer.dart';

/// Test double avoiding real camera hardware.
class FakePhotoCapturer implements PhotoCapturer {
  final Uint8List? photoBytes;
  final Object? throwsError;
  int captureCallCount = 0;

  FakePhotoCapturer({this.photoBytes, this.throwsError});

  @override
  Future<Uint8List?> captureFrontPhoto() async {
    captureCallCount++;
    if (throwsError != null) throw throwsError!;
    return photoBytes;
  }
}
