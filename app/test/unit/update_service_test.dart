import 'package:findmyandroid/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('returns 0 for identical versions', () {
      expect(compareVersions('0.1.3', '0.1.3'), 0);
    });

    test('a leading "v" on either side is ignored', () {
      expect(compareVersions('v0.1.4', '0.1.3'), greaterThan(0));
      expect(compareVersions('0.1.4', 'v0.1.3'), greaterThan(0));
    });

    test('patch version difference is detected', () {
      expect(compareVersions('0.1.4', '0.1.3'), greaterThan(0));
      expect(compareVersions('0.1.3', '0.1.4'), lessThan(0));
    });

    test('minor version outweighs patch', () {
      expect(compareVersions('0.2.0', '0.1.9'), greaterThan(0));
    });

    test('major version outweighs minor and patch', () {
      expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    });

    test('a "+build" suffix is ignored', () {
      expect(compareVersions('0.1.3+5', '0.1.3+2'), 0);
    });

    test('missing parts count as zero', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.1', '1.2'), greaterThan(0));
    });
  });
}
