import 'package:camera_bridge/camera_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nl.hiddebalestra.camera_bridge/camera');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('returns the captured JPEG bytes from the native side', () async {
    final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return jpegBytes;
    });

    final result = await CameraBridge().captureFrontPhoto();

    expect(received!.method, 'captureFrontPhoto');
    expect(result, jpegBytes);
  });

  test('returns null when the native side reports no camera available', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await CameraBridge().captureFrontPhoto(), isNull);
  });

  test('wraps a PlatformException into a CameraBridgeException', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'CAPTURE_FAILED', message: 'Camera permission not granted'),
    );

    await expectLater(
      CameraBridge().captureFrontPhoto(),
      throwsA(isA<CameraBridgeException>().having((e) => e.message, 'message', 'Camera permission not granted')),
    );
  });
}
