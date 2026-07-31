import 'package:location_bridge/location_bridge.dart';

/// Test double avoiding the real LocationManager MethodChannel.
class FakeLocationBridge extends LocationBridge {
  final LocationFix? fix;

  FakeLocationBridge({this.fix});

  @override
  Future<LocationFix> getCurrentLocation({Duration timeout = const Duration(seconds: 20)}) async {
    if (fix == null) throw const LocationBridgeException('NO_FIX', 'No fake fix configured');
    return fix!;
  }
}
