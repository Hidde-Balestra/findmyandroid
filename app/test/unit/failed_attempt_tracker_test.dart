import 'package:findmyandroid/services/failed_attempt_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('count starts at zero', () async {
    final tracker = FailedAttemptTracker();
    expect(await tracker.count, 0);
  });

  test('recordFailure increments and returns the new count', () async {
    final tracker = FailedAttemptTracker();
    expect(await tracker.recordFailure(), 1);
    expect(await tracker.recordFailure(), 2);
    expect(await tracker.recordFailure(), 3);
    expect(await tracker.count, 3);
  });

  test('reset zeroes the count', () async {
    final tracker = FailedAttemptTracker();
    await tracker.recordFailure();
    await tracker.recordFailure();
    await tracker.reset();
    expect(await tracker.count, 0);
  });

  test('persists across separate instances (same underlying storage)', () async {
    await FailedAttemptTracker().recordFailure();
    await FailedAttemptTracker().recordFailure();
    expect(await FailedAttemptTracker().count, 2);
  });
}
