import 'package:device_admin_bridge/device_admin_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nl.hiddebalestra.device_admin_bridge/device_admin');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('isActive forwards the native result and defaults to false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isActive');
      return true;
    });
    expect(await DeviceAdminBridge().isActive(), isTrue);

    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await DeviceAdminBridge().isActive(), isFalse);
  });

  test('requestActivation invokes the native method', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await DeviceAdminBridge().requestActivation();

    expect(received!.method, 'requestActivation');
  });

  test('setThreshold sends the threshold argument', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await DeviceAdminBridge().setThreshold(3);

    expect(received!.method, 'setThreshold');
    expect(received!.arguments, {'threshold': 3});
  });

  test('consumePendingLockscreenTrigger forwards the native result and defaults to false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consumePendingTrigger');
      return true;
    });
    expect(await DeviceAdminBridge().consumePendingLockscreenTrigger(), isTrue);

    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await DeviceAdminBridge().consumePendingLockscreenTrigger(), isFalse);
  });

  test('setDebugNotifyEnabled sends the enabled argument', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await DeviceAdminBridge().setDebugNotifyEnabled(true);

    expect(received!.method, 'setDebugNotifyEnabled');
    expect(received!.arguments, {'enabled': true});
  });

  test('sendTestNotification invokes the native method', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await DeviceAdminBridge().sendTestNotification();

    expect(received!.method, 'sendTestNotification');
  });
}
