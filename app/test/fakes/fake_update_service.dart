import 'package:findmyandroid/services/update_service.dart';

/// Test double avoiding real network calls to the GitHub Releases API.
class FakeUpdateService implements UpdateService {
  final UpdateCheckResult result;
  int openReleasePageCallCount = 0;

  FakeUpdateService({this.result = const UpdateCheckResult(status: UpdateStatus.upToDate)});

  @override
  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async => result;

  @override
  Future<void> openReleasePage(String url) async {
    openReleasePageCallCount++;
  }
}
