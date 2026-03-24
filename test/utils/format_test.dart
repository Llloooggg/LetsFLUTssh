import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/utils/format.dart';

void main() {
  group('formatSize', () {
    test('bytes', () {
      expect(formatSize(0), '0 B');
      expect(formatSize(512), '512 B');
      expect(formatSize(1023), '1023 B');
    });

    test('kilobytes', () {
      expect(formatSize(1024), '1.0 KB');
      expect(formatSize(1536), '1.5 KB');
      expect(formatSize(1024 * 100), '100.0 KB');
    });

    test('megabytes', () {
      expect(formatSize(1024 * 1024), '1.0 MB');
      expect(formatSize(1024 * 1024 * 50), '50.0 MB');
    });

    test('gigabytes', () {
      expect(formatSize(1024 * 1024 * 1024), '1.00 GB');
      expect(formatSize(1024 * 1024 * 1024 * 3), '3.00 GB');
    });
  });

  group('formatTimestamp', () {
    test('formats correctly', () {
      final dt = DateTime(2025, 3, 15, 9, 5);
      expect(formatTimestamp(dt), '2025-03-15 09:05');
    });

    test('pads single digits', () {
      final dt = DateTime(2025, 1, 2, 3, 4);
      expect(formatTimestamp(dt), '2025-01-02 03:04');
    });
  });

  group('formatDuration', () {
    test('milliseconds', () {
      expect(formatDuration(const Duration(milliseconds: 500)), '500ms');
    });

    test('seconds', () {
      expect(formatDuration(const Duration(seconds: 30)), '30s');
    });

    test('minutes and seconds', () {
      expect(formatDuration(const Duration(minutes: 2, seconds: 15)), '2m 15s');
    });

    test('hours and minutes', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 30)), '1h 30m');
    });
  });
}
