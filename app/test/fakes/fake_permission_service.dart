import 'package:findmyandroid/services/permission_service.dart';

/// Test double avoiding real permission_handler platform channel calls.
class FakePermissionService implements PermissionService {
  final Map<ReliabilityPermission, bool> granted;
  int openSettingsCallCount = 0;
  int requestCallCount = 0;

  FakePermissionService({Map<ReliabilityPermission, bool>? granted})
      : granted = granted ?? {for (final p in ReliabilityPermission.values) p: false};

  @override
  Future<bool> isGranted(ReliabilityPermission permission) async => granted[permission] ?? false;

  @override
  Future<void> request(ReliabilityPermission permission) async {
    requestCallCount++;
    granted[permission] = true;
  }

  @override
  Future<void> openSettings() async {
    openSettingsCallCount++;
  }

  @override
  Future<Map<ReliabilityPermission, bool>> statusSnapshot() async => Map.of(granted);
}
