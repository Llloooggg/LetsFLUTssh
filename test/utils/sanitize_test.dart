import 'package:letsflutssh/utils/sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactSecrets', () {
    test('strips OpenSSH PEM private key blocks', () {
      const input =
          'INSERT failed: key_data = -----BEGIN OPENSSH PRIVATE KEY-----\n'
          'b3BlbnNzaC1rZXktdjEAAAA\n'
          'SECRET CONTENT HERE\n'
          '-----END OPENSSH PRIVATE KEY----- trailing';
      final out = redactSecrets(input);
      expect(out, contains('[REDACTED PRIVATE KEY]'));
      expect(out, isNot(contains('SECRET CONTENT')));
      expect(out, isNot(contains('b3BlbnNzaC1rZXktdjEAAAA')));
      expect(out, contains('trailing'));
    });

    test('strips RSA / EC PEM private key blocks', () {
      const input =
          '-----BEGIN RSA PRIVATE KEY-----\nAAAA\n-----END RSA PRIVATE KEY-----';
      expect(redactSecrets(input), '[REDACTED PRIVATE KEY]');
    });

    test('strips long base64 runs (raw key blobs without PEM headers)', () {
      final blob = 'A' * 250;
      expect(
        redactSecrets('before $blob after'),
        'before [REDACTED BASE64] after',
      );
    });

    test('leaves short base64 snippets alone', () {
      const input = 'Error code: AABB1234==';
      expect(redactSecrets(input), input);
    });

    test('strips ENCRYPTED PRIVATE KEY blocks (PKCS#8 with passphrase)', () {
      const input =
          '-----BEGIN ENCRYPTED PRIVATE KEY-----\n'
          'MIIBszBOBgkqhkiG9w0BBQ0wQTApBgkqhkiG9w0BBQwwHAQI\n'
          '-----END ENCRYPTED PRIVATE KEY-----';
      expect(redactSecrets(input), '[REDACTED PRIVATE KEY]');
    });

    test('strips DSA / DSS PEM blocks (legacy formats with hyphens)', () {
      const input =
          '-----BEGIN DSA PRIVATE KEY-----\nABCD\n-----END DSA PRIVATE KEY-----';
      // The DSA suffix matches the RSA-style "<X> PRIVATE KEY" pattern via
      // the broadened type group; redaction must succeed.
      expect(redactSecrets(input), '[REDACTED PRIVATE KEY]');
    });

    test('sqlite-style INSERT parameters with PEM keys are fully redacted', () {
      // Mirrors the drift/sqlite3 leak where a failed INSERT's toString()
      // dumps bound parameters verbatim, including private key PEM.
      const input =
          'SqliteException(787): while executing statement, '
          'FOREIGN KEY constraint failed '
          'Causing statement: INSERT INTO "sessions" (...) VALUES (?, ?), '
          'parameters: 44840ce3-4e4d, '
          '-----BEGIN OPENSSH PRIVATE KEY-----\n'
          'b3BlbnNzaC1rZXktdjEAAAAAB\n'
          '-----END OPENSSH PRIVATE KEY-----, 22';
      final out = redactSecrets(input);
      expect(out, isNot(contains('b3BlbnNzaC1rZXktdjEAAAAAB')));
      expect(out, isNot(contains('BEGIN OPENSSH PRIVATE KEY')));
      expect(out, contains('[REDACTED PRIVATE KEY]'));
      expect(out, contains('FOREIGN KEY constraint failed'));
    });
  });

  group('sanitizeErrorMessage', () {
    test('redacts user@host patterns', () {
      expect(
        sanitizeErrorMessage('admin@example.com'),
        contains('<user>@example.com'),
      );
      expect(
        sanitizeErrorMessage('root@myserver.net'),
        contains('<user>@myserver.net'),
      );
    });

    test('redacts IPv4 addresses', () {
      expect(sanitizeErrorMessage('192.168.1.100'), contains('<ip>'));
      expect(sanitizeErrorMessage('10.0.0.1'), contains('<ip>'));
    });

    test('redacts port numbers', () {
      expect(sanitizeErrorMessage('192.168.1.100:22'), contains(':<port>'));
      expect(sanitizeErrorMessage('example.com:2222'), contains(':<port>'));
    });

    test('redacts user@<ip>:<port> pattern', () {
      // This is the real-world case: admin@192.168.1.100:22
      final result = sanitizeErrorMessage('admin@192.168.1.100:22');
      expect(result, contains('<user>@'));
      expect(result, contains(':<port>'));
      expect(result, isNot(contains('admin')));
      expect(result, isNot(contains('192.168.1.100')));
    });

    test('redacts "as <user>" after host:port in SSH log lines', () {
      // Real-world leak: our own `Connecting to ${host}:${port} as ${user}`
      // log line left the bare username intact even after the host was
      // redacted. The sanitiser now treats "as <token>" as a user
      // reference.
      final result = sanitizeErrorMessage(
        'Connecting to example.com:22 as burzuf',
      );
      expect(result, contains('as <user>'));
      expect(result, isNot(contains('burzuf')));
    });

    test('redacts "user=<name>" shapes used by dartssh2 / OpenSSH', () {
      final result = sanitizeErrorMessage(
        'auth attempt user=admin method=publickey',
      );
      expect(result, contains('user= <user>'));
      expect(result, isNot(contains('admin')));
    });

    test('redacts Windows file paths with usernames', () {
      expect(
        sanitizeErrorMessage('C:\\Users\\john\\Documents\\key.pem'),
        contains('<path>\\'),
      );
    });

    test('redacts Unix/macOS file paths with usernames', () {
      expect(
        sanitizeErrorMessage('/Users/john/.ssh/id_rsa'),
        contains('/<user>/'),
      );
      expect(
        sanitizeErrorMessage('/home/admin/.ssh/known_hosts'),
        contains('/<user>/'),
      );
    });

    test('handles complex error messages', () {
      const input =
          'Connection failed: admin@192.168.1.100:22 - '
          'File not found: /Users/john/.ssh/id_rsa';
      final result = sanitizeErrorMessage(input);

      expect(result, contains('<user>@'));
      expect(result, contains('<ip>'));
      expect(result, contains(':<port>'));
      expect(result, contains('/<user>/'));
      expect(result, isNot(contains('admin')));
      expect(result, isNot(contains('192.168.1.100')));
      expect(result, isNot(contains('john')));
    });

    test('leaves non-sensitive messages unchanged', () {
      const input = 'Failed to load SSH key file';
      expect(sanitizeErrorMessage(input), input);
    });

    test('redacts DBus errors without leaking paths', () {
      // Real Linux desktop error
      const input =
          'org.freedesktop.DBus.Error.ServiceUnknown: '
          'The name org.freedesktop.portal.Desktop was not provided by any .service files';
      final result = sanitizeErrorMessage(input);
      // DBus errors don't contain sensitive data, so should pass through unchanged
      expect(result, contains('DBus.Error.ServiceUnknown'));
      expect(result, contains('freedesktop.portal.Desktop'));
    });
  });
}
