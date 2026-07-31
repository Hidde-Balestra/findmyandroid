import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_bridge/location_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('nl.hiddebalestra.location_bridge/location');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('hasPermission / isLocationEnabled', () {
    test('hasPermission forwards the native result', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'hasPermission');
        return true;
      });

      expect(await LocationBridge().hasPermission(), isTrue);
    });

    test('hasPermission defaults to false if the native side returns null', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);

      expect(await LocationBridge().hasPermission(), isFalse);
    });

    test('isLocationEnabled forwards the native result', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isLocationEnabled');
        return false;
      });

      expect(await LocationBridge().isLocationEnabled(), isFalse);
    });
  });

  group('getCurrentLocation', () {
    test('sends the timeout and parses a full result map into a LocationFix', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return <Object?, Object?>{
          'latitude': 52.1,
          'longitude': 5.1,
          'accuracy': 12.5,
          'altitude': 3.0,
          'speed': 0.5,
          'timestamp': 1700000000000,
          'provider': 'gps',
        };
      });

      final fix = await LocationBridge().getCurrentLocation(timeout: const Duration(seconds: 7));

      expect(received!.method, 'getCurrentLocation');
      expect(received!.arguments, {'timeoutMs': 7000});
      expect(fix.latitude, 52.1);
      expect(fix.longitude, 5.1);
      expect(fix.accuracy, 12.5);
      expect(fix.altitude, 3.0);
      expect(fix.speed, 0.5);
      expect(fix.provider, 'gps');
      expect(fix.timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('defaults optional fields when the native map omits them', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => <Object?, Object?>{
            'latitude': 1.0,
            'longitude': 2.0,
            'timestamp': 1700000000000,
          });

      final fix = await LocationBridge().getCurrentLocation();

      expect(fix.accuracy, isNull);
      expect(fix.altitude, isNull);
      expect(fix.speed, isNull);
      expect(fix.provider, 'unknown');
    });

    test('throws LocationBridgeException when the native side returns no result', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);

      await expectLater(
        LocationBridge().getCurrentLocation(),
        throwsA(isA<LocationBridgeException>().having((e) => e.code, 'code', 'NO_RESULT')),
      );
    });

    test('wraps a PlatformException into a LocationBridgeException with the same code/message', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'PERMISSION_DENIED', message: 'no location permission'),
      );

      await expectLater(
        LocationBridge().getCurrentLocation(),
        throwsA(
          isA<LocationBridgeException>()
              .having((e) => e.code, 'code', 'PERMISSION_DENIED')
              .having((e) => e.message, 'message', 'no location permission'),
        ),
      );
    });
  });
}
