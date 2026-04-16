import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dartssh2/dartssh2.dart' show SftpStatusCode, SftpStatusError;
import 'package:letsflutssh/core/import/import_service.dart';
import 'package:letsflutssh/core/sftp/errors.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/l10n/app_localizations_en.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
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
        expect(
          sanitizeError(Exception('something broke')),
          'Exception: something broke',
        );
      });

      test('returns toString for string error', () {
        expect(sanitizeError('plain error'), 'plain error');
      });
    });

    group('errno-based errors', () {
      test('translates known Linux errno from FileSystemException', () {
        const e = FileSystemException(
          'Cannot open file',
          '/tmp/test.txt',
          OSError('Localized OS msg', 13),
        );
        expect(sanitizeError(e), 'Permission denied: /tmp/test.txt');
      });

      test('translates known Linux errno without path', () {
        const e = SocketException(
          'Connection failed',
          osError: OSError('Localized OS msg', 111),
        );
        expect(sanitizeError(e), 'Connection refused');
      });

      test('translates Windows Winsock errno', () {
        const e = SocketException(
          'Connection failed',
          osError: OSError('Localized OS msg', 10061),
        );
        expect(sanitizeError(e), 'Connection refused');
      });

      test('translates connection timed out (Linux)', () {
        const e = SocketException(
          'Connect',
          osError: OSError('Localized OS msg', 110),
        );
        expect(sanitizeError(e), 'Connection timed out');
      });

      test('translates connection timed out (Windows)', () {
        const e = SocketException(
          'Connect',
          osError: OSError('Timeout', 10060),
        );
        expect(sanitizeError(e), 'Connection timed out');
      });

      test('returns original message for unknown errno', () {
        const e = SocketException(
          'Something',
          osError: OSError('Unknown error', 99999),
        );
        // No match — returns original toString
        expect(sanitizeError(e), e.toString());
      });

      test('translates connection reset (Linux)', () {
        const e = SocketException(
          'Read failed',
          osError: OSError('Localized OS msg', 104),
        );
        expect(sanitizeError(e), 'Connection reset by peer');
      });

      test('translates no route to host (Windows)', () {
        const e = SocketException(
          'Connect',
          osError: OSError('Localized OS msg', 10065),
        );
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
          SocketException(
            'Connection failed',
            osError: OSError('Localized OS msg', 111),
          ),
        );
        expect(
          sanitizeError(e),
          'Failed to connect to host:22 (Connection refused)',
        );
      });

      test('sanitizes SSHError cause with Windows errno', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          SocketException(
            'Connection failed',
            osError: OSError('Localized OS msg', 10061),
          ),
        );
        expect(
          sanitizeError(e),
          'Failed to connect to host:22 (Connection refused)',
        );
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
        expect(
          sanitizeError(e),
          'Authentication failed for user@host (Exception: bad key format)',
        );
      });

      test('handles nested SSHError chain', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          ConnectError(
            'TCP connect failed',
            SocketException(
              'OS Error',
              osError: OSError('Localized OS msg', 113),
            ),
          ),
        );
        expect(
          sanitizeError(e),
          'Failed to connect to host:22 (TCP connect failed (No route to host))',
        );
      });

      test('SSHError with same message as cause collapses', () {
        const e = ConnectError(
          'Connection failed',
          ConnectError('Connection failed'),
        );
        expect(sanitizeError(e), 'Connection failed');
      });
    });

    group('FileSystemException with path', () {
      test('includes path in sanitized message', () {
        const e = FileSystemException(
          'Cannot delete',
          '/home/user/file.txt',
          OSError('Localized OS msg', 2),
        );
        expect(
          sanitizeError(e),
          'No such file or directory: /home/user/file.txt',
        );
      });

      test('handles read-only file system', () {
        const e = FileSystemException(
          'Cannot write',
          '/mnt/readonly/file',
          OSError('Localized OS msg', 30),
        );
        expect(sanitizeError(e), 'Read-only file system: /mnt/readonly/file');
      });
    });
  });

  group('localizeError', () {
    late S l10n;

    setUp(() {
      l10n = SEn();
    });

    group('SSHError subtypes', () {
      test('localizes ConnectError with host and port', () {
        const e = ConnectError(
          'Failed to connect to example.com:22',
          null,
          'example.com',
          22,
        );
        expect(localizeError(l10n, e), 'Failed to connect to example.com:22');
      });

      test('localizes AuthError with user and host', () {
        const e = AuthError(
          'Authentication failed for root@example.com',
          null,
          'root',
          'example.com',
        );
        expect(
          localizeError(l10n, e),
          'Authentication failed for root@example.com',
        );
      });

      test('localizes HostKeyError with host and port', () {
        const e = HostKeyError('Host key rejected', null, 'example.com', 22);
        expect(localizeError(l10n, e), contains('example.com:22'));
      });

      test('localizes ConnectError with errno cause', () {
        const e = ConnectError(
          'Failed to connect to host:22',
          SocketException(
            'Connection failed',
            osError: OSError('Localized OS msg', 111),
          ),
          'host',
          22,
        );
        final result = localizeError(l10n, e);
        expect(result, contains('Failed to connect to host:22'));
        expect(result, contains('Connection refused'));
      });

      test('localizes shell open failure', () {
        const e = ConnectError('Failed to open shell', null, 'host', 22);
        expect(localizeError(l10n, e), 'Failed to open shell');
      });

      test('localizes auth aborted', () {
        const e = AuthError('Authentication aborted', null, 'root', 'host');
        expect(localizeError(l10n, e), 'Authentication aborted');
      });

      test('localizes key file load failure', () {
        const e = AuthError(
          'Failed to load SSH key file',
          null,
          'root',
          'host',
        );
        expect(localizeError(l10n, e), 'Failed to load SSH key file');
      });

      test('localizes PEM parse failure', () {
        const e = AuthError(
          'Failed to parse PEM key data',
          null,
          'root',
          'host',
        );
        expect(localizeError(l10n, e), 'Failed to parse PEM key data');
      });
    });

    group('errno-based errors', () {
      test('localizes Linux errno with path', () {
        const e = FileSystemException(
          'Cannot open file',
          '/tmp/test.txt',
          OSError('Localized OS msg', 13),
        );
        expect(localizeError(l10n, e), 'Permission denied: /tmp/test.txt');
      });

      test('localizes socket errno', () {
        const e = SocketException(
          'Connection failed',
          osError: OSError('Localized OS msg', 111),
        );
        expect(localizeError(l10n, e), 'Connection refused');
      });

      test('localizes Windows Winsock errno', () {
        const e = SocketException(
          'Connection failed',
          osError: OSError('Localized OS msg', 10061),
        );
        expect(localizeError(l10n, e), 'Connection refused');
      });

      test('falls through for unknown errno', () {
        const e = SocketException(
          'Something',
          osError: OSError('Unknown error', 99999),
        );
        expect(localizeError(l10n, e), e.toString());
      });
    });

    group('LFS exceptions', () {
      test('localizes LfsArchiveTooLargeException with MiB values', () {
        const e = LfsArchiveTooLargeException(
          size: 60 * 1024 * 1024,
          limit: 50 * 1024 * 1024,
        );
        final msg = localizeError(l10n, e);
        expect(msg, contains('60.0'));
        expect(msg, contains('50'));
      });

      test('localizes LfsKnownHostsTooLargeException with MiB values', () {
        const e = LfsKnownHostsTooLargeException(
          size: 15 * 1024 * 1024,
          limit: 10 * 1024 * 1024,
        );
        final msg = localizeError(l10n, e);
        expect(msg, contains('15.0'));
        expect(msg, contains('10'));
      });

      test(
        'localizes UnsupportedLfsVersionException with both version numbers',
        () {
          const e = UnsupportedLfsVersionException(found: 7, supported: 1);
          final msg = localizeError(l10n, e);
          expect(msg, contains('7'));
          expect(msg, contains('1'));
        },
      );

      test(
        'LfsDecryptionFailedException returns the generic decrypt message',
        () {
          final e = LfsDecryptionFailedException(cause: Exception('bad tag'));
          expect(localizeError(l10n, e), isNotEmpty);
          // Cause must NOT leak into the UI message (PEM/base64 redaction).
          expect(localizeError(l10n, e), isNot(contains('bad tag')));
        },
      );

      test('LfsImportRolledBackException recursively localizes its cause', () {
        // Nested: rollback wrapping an archive-too-large exception — both
        // layers must make it into the final message.
        const inner = LfsArchiveTooLargeException(
          size: 60 * 1024 * 1024,
          limit: 50 * 1024 * 1024,
        );
        const e = LfsImportRolledBackException(cause: inner);
        final msg = localizeError(l10n, e);
        expect(msg, contains('60.0'));
      });
    });

    group('TimeoutException', () {
      test('localizes with duration', () {
        final e = TimeoutException('timed out', const Duration(seconds: 30));
        expect(localizeError(l10n, e), 'Connection timed out after 30 seconds');
      });

      test('localizes without duration', () {
        final e = TimeoutException('timed out');
        expect(localizeError(l10n, e), 'Connection timed out');
      });
    });

    group('plain errors', () {
      test('returns toString for generic exception', () {
        expect(
          localizeError(l10n, Exception('something broke')),
          'Exception: something broke',
        );
      });

      test('returns toString for string error', () {
        expect(localizeError(l10n, 'plain error'), 'plain error');
      });

      test('localizes TimeoutException with duration', () {
        final error = TimeoutException(
          'timed out',
          const Duration(seconds: 10),
        );
        final result = localizeError(l10n, error);
        expect(result, contains('10'));
      });

      test('localizes TimeoutException without duration', () {
        final error = TimeoutException('timed out');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes SFTPError with SftpStatusCode.noSuchFile', () {
        final error = SFTPError(
          'File not found',
          cause: SftpStatusError(SftpStatusCode.noSuchFile, 'No such file'),
          path: '/remote/file.txt',
        );
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
        expect(result, contains('/remote/file.txt'));
      });

      test('localizes SFTPError with SftpStatusCode.permissionDenied', () {
        final error = SFTPError(
          'Permission denied',
          cause: SftpStatusError(
            SftpStatusCode.permissionDenied,
            'Access denied',
          ),
        );
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes SFTPError with unknown status code', () {
        final error = SFTPError(
          'SFTP failure',
          cause: SftpStatusError(SftpStatusCode.failure, 'Generic failure'),
        );
        final result = localizeError(l10n, error);
        expect(result, contains('SFTP failure'));
      });

      test('localizes SFTPError without status error', () {
        const error = SFTPError('SFTP error', path: '/path');
        final result = localizeError(l10n, error);
        expect(result, contains('/path'));
      });

      test('localizes SFTPError without cause or path', () {
        const error = SFTPError('bare error');
        expect(localizeError(l10n, error), 'bare error');
      });

      test('localizes ConnectError with "Connection disposed"', () {
        const error = ConnectError('Connection disposed');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes ConnectError with "Not connected"', () {
        const error = ConnectError('Not connected');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes ConnectError with "open shell"', () {
        const error = ConnectError('Failed to open shell channel');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes ConnectError with "Connection failed to"', () {
        const error = ConnectError(
          'Connection failed to host',
          null,
          '10.0.0.1',
          22,
        );
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes ConnectError with unknown message', () {
        const error = ConnectError('Something else');
        expect(localizeError(l10n, error), 'Something else');
      });

      test('localizes AuthError with "Authentication aborted"', () {
        const error = AuthError('Authentication aborted');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes AuthError with "load SSH key file"', () {
        const error = AuthError('Failed to load SSH key file');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes AuthError with "parse PEM"', () {
        const error = AuthError('Failed to parse PEM key');
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes AuthError with unknown message', () {
        const error = AuthError('Custom auth error');
        expect(localizeError(l10n, error), 'Custom auth error');
      });

      test('localizes generic SSHError with cause', () {
        const error = SSHError(
          'SSH problem',
          SocketException('OS Error: connection refused, errno = 111'),
        );
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes generic SSHError without cause', () {
        const error = SSHError('SSH problem');
        expect(localizeError(l10n, error), 'SSH problem');
      });

      test('localizes HostKeyError', () {
        const error = HostKeyError('Host key rejected', null, '10.0.0.1', 22);
        final result = localizeError(l10n, error);
        expect(result, isNotEmpty);
      });

      test('localizes OS error with errno via _localizeOsError', () {
        final result = localizeError(
          l10n,
          const FileSystemException(
            'Cannot open file',
            '/tmp/test',
            OSError('Permission denied', 13),
          ),
        );
        expect(result, isNotEmpty);
      });

      test('localizes SocketException with OS error errno', () {
        final result = localizeError(
          l10n,
          const SocketException('OS Error: Connection refused, errno = 111'),
        );
        expect(result, isNotEmpty);
      });
    });

    group('errno localization coverage', () {
      // POSIX errno codes via FileSystemException
      test('errno 1 — Operation not permitted', () {
        const e = FileSystemException('x', '/f', OSError('loc', 1));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 2 — No such file or directory', () {
        const e = FileSystemException('x', '/f', OSError('loc', 2));
        expect(localizeError(l10n, e), contains('/f'));
      });
      test('errno 5 — I/O error', () {
        const e = FileSystemException('x', '/f', OSError('loc', 5));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 12 — Out of memory', () {
        const e = SocketException('x', osError: OSError('loc', 12));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 17 — File exists', () {
        const e = FileSystemException('x', '/f', OSError('loc', 17));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 20 — Not a directory', () {
        const e = FileSystemException('x', '/f', OSError('loc', 20));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 21 — Is a directory', () {
        const e = FileSystemException('x', '/f', OSError('loc', 21));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 22 — Invalid argument', () {
        const e = FileSystemException('x', null, OSError('loc', 22));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 23 — Too many open files', () {
        const e = FileSystemException('x', null, OSError('loc', 23));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 28 — No space left on device', () {
        const e = FileSystemException('x', '/f', OSError('loc', 28));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 32 — Broken pipe', () {
        const e = SocketException('x', osError: OSError('loc', 32));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 36 — File name too long', () {
        const e = FileSystemException('x', '/f', OSError('loc', 36));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 39 — Directory not empty', () {
        const e = FileSystemException('x', '/f', OSError('loc', 39));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 98 — Address already in use', () {
        const e = SocketException('x', osError: OSError('loc', 98));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 99 — Cannot assign address', () {
        const e = SocketException('x', osError: OSError('loc', 99));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 100 — Network is down', () {
        const e = SocketException('x', osError: OSError('loc', 100));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 101 — Network is unreachable', () {
        const e = SocketException('x', osError: OSError('loc', 101));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 112 — Host is down', () {
        const e = SocketException('x', osError: OSError('loc', 112));
        expect(localizeError(l10n, e), isNotEmpty);
      });

      // Windows Winsock codes
      test('errno 10013 — Permission denied (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10013));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10048 — Address in use (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10048));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10049 — Cannot assign address (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10049));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10050 — Network down (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10050));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10051 — Network unreachable (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10051));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10053 — Connection aborted (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10053));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10054 — Connection reset (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10054));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10056 — Already connected (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10056));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10057 — Not connected (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10057));
        expect(localizeError(l10n, e), isNotEmpty);
      });
      test('errno 10064 — Host is down (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10064));
        expect(localizeError(l10n, e), isNotEmpty);
      });
    });

    group('sanitizeError — errno English coverage', () {
      test('errno 1 — Operation not permitted', () {
        const e = FileSystemException('x', '/f', OSError('loc', 1));
        expect(sanitizeError(e), 'Operation not permitted: /f');
      });
      test('errno 5 — I/O error', () {
        const e = FileSystemException('x', '/f', OSError('loc', 5));
        expect(sanitizeError(e), 'I/O error: /f');
      });
      test('errno 12 — Out of memory', () {
        const e = SocketException('x', osError: OSError('loc', 12));
        expect(sanitizeError(e), 'Out of memory');
      });
      test('errno 17 — File exists', () {
        const e = FileSystemException('x', '/f', OSError('loc', 17));
        expect(sanitizeError(e), 'File exists: /f');
      });
      test('errno 20 — Not a directory', () {
        const e = FileSystemException('x', '/f', OSError('loc', 20));
        expect(sanitizeError(e), 'Not a directory: /f');
      });
      test('errno 21 — Is a directory', () {
        const e = FileSystemException('x', '/f', OSError('loc', 21));
        expect(sanitizeError(e), 'Is a directory: /f');
      });
      test('errno 22 — Invalid argument', () {
        const e = SocketException('x', osError: OSError('loc', 22));
        expect(sanitizeError(e), 'Invalid argument');
      });
      test('errno 28 — No space left on device', () {
        const e = FileSystemException('x', '/f', OSError('loc', 28));
        expect(sanitizeError(e), 'No space left on device: /f');
      });
      test('errno 32 — Broken pipe', () {
        const e = SocketException('x', osError: OSError('loc', 32));
        expect(sanitizeError(e), 'Broken pipe');
      });
      test('errno 36 — File name too long', () {
        const e = FileSystemException('x', '/f', OSError('loc', 36));
        expect(sanitizeError(e), 'File name too long: /f');
      });
      test('errno 39 — Directory not empty', () {
        const e = FileSystemException('x', '/f', OSError('loc', 39));
        expect(sanitizeError(e), 'Directory not empty: /f');
      });
      test('errno 98 — Address already in use', () {
        const e = SocketException('x', osError: OSError('loc', 98));
        expect(sanitizeError(e), 'Address already in use');
      });
      test('errno 100 — Network is down', () {
        const e = SocketException('x', osError: OSError('loc', 100));
        expect(sanitizeError(e), 'Network is down');
      });
      test('errno 101 — Network is unreachable', () {
        const e = SocketException('x', osError: OSError('loc', 101));
        expect(sanitizeError(e), 'Network is unreachable');
      });
      test('errno 112 — Host is down', () {
        const e = SocketException('x', osError: OSError('loc', 112));
        expect(sanitizeError(e), 'Host is down');
      });

      // Windows Winsock
      test('errno 10013 — Permission denied (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10013));
        expect(sanitizeError(e), 'Permission denied');
      });
      test('errno 10048 — Address already in use (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10048));
        expect(sanitizeError(e), 'Address already in use');
      });
      test('errno 10050 — Network is down (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10050));
        expect(sanitizeError(e), 'Network is down');
      });
      test('errno 10053 — Connection aborted (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10053));
        expect(sanitizeError(e), 'Connection aborted');
      });
      test('errno 10054 — Connection reset (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10054));
        expect(sanitizeError(e), 'Connection reset by peer');
      });
      test('errno 10056 — Already connected (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10056));
        expect(sanitizeError(e), 'Already connected');
      });
      test('errno 10057 — Not connected (Windows)', () {
        const e = SocketException('x', osError: OSError('loc', 10057));
        expect(sanitizeError(e), 'Not connected');
      });
    });
  });

  group('formatImportSummary', () {
    final l10n = SEn();

    test('only sessions → uses localized session-count string', () {
      final out = formatImportSummary(l10n, const ImportSummary(sessions: 3));
      expect(out, l10n.importedSessions(3));
    });

    test('appends non-zero extras with localized nouns', () {
      final out = formatImportSummary(
        l10n,
        const ImportSummary(sessions: 2, managerKeys: 4, tags: 5, snippets: 1),
      );
      expect(out, contains(l10n.importedSessions(2)));
      expect(out, contains('4 ${l10n.sshKeys}'));
      expect(out, contains('5 ${l10n.tags}'));
      expect(out, contains('1 ${l10n.snippets}'));
    });

    test('surfaces config / known_hosts flags', () {
      final out = formatImportSummary(
        l10n,
        const ImportSummary(
          sessions: 1,
          configApplied: true,
          knownHostsApplied: true,
        ),
      );
      expect(out, contains(l10n.appSettings));
      expect(out, contains(l10n.knownHosts));
    });

    test('zero-everything still produces a message', () {
      final out = formatImportSummary(l10n, const ImportSummary());
      expect(out, l10n.importedSessions(0));
    });
  });
}
