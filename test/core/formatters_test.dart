import 'package:flutter_test/flutter_test.dart';
import 'package:shuttle/core/utils/formatters.dart';

void main() {
  group('formatBytes', () {
    test('bytes stay bytes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('one decimal below ten, none above', () {
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(45 * 1024), '45 KB');
    });

    test('climbs units', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });

}
