import 'package:flutter/services.dart';

/// A single location fix read straight from Android's [LocationManager]
/// (GPS/network providers) — no Google Play Services / fused location API
/// involved anywhere in this call.
class LocationFix {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final DateTime timestamp;
  final String provider;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.provider,
    this.accuracy,
    this.altitude,
    this.speed,
  });

  factory LocationFix.fromMap(Map<Object?, Object?> map) {
    return LocationFix(
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      accuracy: map['accuracy'] as double?,
      altitude: map['altitude'] as double?,
      speed: map['speed'] as double?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      provider: map['provider'] as String? ?? 'unknown',
    );
  }
}

/// Thrown when no location could be obtained (permission denied, no provider
/// enabled, or no fix arrived within the timeout).
class LocationBridgeException implements Exception {
  final String code;
  final String message;

  const LocationBridgeException(this.code, this.message);

  @override
  String toString() => 'LocationBridgeException($code): $message';
}

class LocationBridge {
  static const MethodChannel _channel = MethodChannel(
    'nl.hiddebalestra.location_bridge/location',
  );

  Future<bool> hasPermission() async {
    return (await _channel.invokeMethod<bool>('hasPermission')) ?? false;
  }

  Future<bool> isLocationEnabled() async {
    return (await _channel.invokeMethod<bool>('isLocationEnabled')) ?? false;
  }

  /// Requests a single fresh fix, waiting at most [timeout] before falling
  /// back to the most recent last-known fix from any enabled provider.
  Future<LocationFix> getCurrentLocation({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getCurrentLocation',
        {'timeoutMs': timeout.inMilliseconds},
      );
      if (result == null) {
        throw const LocationBridgeException('NO_RESULT', 'Native side returned no location');
      }
      return LocationFix.fromMap(result);
    } on PlatformException catch (e) {
      throw LocationBridgeException(e.code, e.message ?? 'Unknown location error');
    }
  }
}
