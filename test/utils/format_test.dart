import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/ssh/errors.dart';
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

  group('sanitizeError', () {
    group('plain exceptions (no errno)', () {
      test('returns toString for generic exception', () {
        expect(sanitizeError(Exception('something broke')), 'Exception: something broke');
      });

      test('returns toString for string error', () {
        expect(sanitizeError('plain error'), 'plain error');
      });
    });

    group('errno-based errors', () {
      test('translates known Linux errno from FileSystemException', () {
        const e = FileSystemException('Cannot open file', '/tmp/test.txt', OSError('Localized OS msg', 13));
        expect(sanitizeError(e), 'Permission denied: /tmp/test.txt');
      });

      test('translates known Linux errno without path', () {
        const e = SocketException('Connection failed', osError: OSError('Localized OS msg', 111));
        expect(sanitizeError(e), 'Connection refused');
      });

      test('translates Windows Winsock errno', () {
        const e = SocketException('Connection failed', osError: OSError('Localized OS msg', 10061));
        expect(sanitizeError(e), 'Connection refused');
      });

      test('translates connection timed out (Linux)', () {
        const e = SocketException('Connect', osError: OSError('Localized OS msg', 110));
        expect(sanitizeError(e), 'Connection timed out');
      });

      test('translates connection timed out (Windows)', () {
        const e = SocketException('Connect', osError: OSError('Timeout', 10060));
        expect(sanitizeError(e), 'Connection timed out');
      });

      test('returns original message for unknown errno', () {
        const e = SocketException('Something', osError: OSError('Unknown error', 99999));
        // No match — returns original toString
        expect(sanitizeError(e), e.toString());
      });

      test('translates connection reset (Linux)', () {
        const e = SocketException('Read failed', osError: OSError('Localized OS msg', 104));
        expect(sanitizeError(e), 'Connection reset by peer');
      });

      test('translates no route to host (Windows)', () {
        const e = SocketException('Connect', osError: OSError('Localized OS msg', 10065));
        expect(sanitizeError(e), 'No route to host');
      });
    });

    group('SSHError subtypes', () {
      test('returns message for SSHError without cause', () {
        const e = ConnectError('Failed to connect to host:22');
        expect(sanitizeError(e), 'Failed to connect to host:22');
      });

      test('sanitizes SSHError cause with errno', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          SocketException('Connection failed', osError: OSError('Localized OS msg', 111)),
        );
        expect(sanitizeError(e), 'Failed to connect to host:22 (Connection refused)');
      });

      test('sanitizes SSHError cause with Windows errno', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          SocketException('Connection failed', osError: OSError('Localized OS msg', 10061)),
        );
        expect(sanitizeError(e), 'Failed to connect to host:22 (Connection refused)');
      });

      test('preserves SSHError message when cause has unknown errno', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          SocketException('Something', osError: OSError('Unknown', 99999)),
        );
        // Cause not sanitized — falls through to toString
        expect(sanitizeError(e), startsWith('Failed to connect to host:22 ('));
      });

      test('handles AuthError with cause', () {
        final cause = Exception('bad key format');
        final e = AuthError('Authentication failed for user@host', cause);
        expect(sanitizeError(e), 'Authentication failed for user@host (Exception: bad key format)');
      });

      test('handles nested SSHError chain', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          ConnectError('TCP connect failed', SocketException('OS Error', osError: OSError('Localized OS msg', 113))),
        );
        expect(sanitizeError(e), 'Failed to connect to host:22 (TCP connect failed (No route to host))');
      });

      test('SSHError with same message as cause collapses', () {
        const e = ConnectError('Connection failed', ConnectError('Connection failed'));
        expect(sanitizeError(e), 'Connection failed');
      });
    });

    group('FileSystemException with path', () {
      test('includes path in sanitized message', () {
        const e = FileSystemException('Cannot delete', '/home/user/file.txt', OSError('Localized OS msg', 2));
        expect(sanitizeError(e), 'No such file or directory: /home/user/file.txt');
      });

      test('handles read-only file system', () {
        const e = FileSystemException('Cannot write', '/mnt/readonly/file', OSError('Localized OS msg', 30));
        expect(sanitizeError(e), 'Read-only file system: /mnt/readonly/file');
      });
    });
  });
}
