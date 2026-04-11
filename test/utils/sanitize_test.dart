import 'package:letsflutssh/utils/sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      expect(
        sanitizeErrorMessage('192.168.1.100'),
        contains('<ip>'),
      );
      expect(
        sanitizeErrorMessage('10.0.0.1'),
        contains('<ip>'),
      );
    });

    test('redacts port numbers', () {
      expect(
        sanitizeErrorMessage('192.168.1.100:22'),
        contains(':<port>'),
      );
      expect(
        sanitizeErrorMessage('example.com:2222'),
        contains(':<port>'),
      );
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
  });
}
