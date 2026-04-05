import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/errors.dart';

void main() {
  group('SSHError', () {
    test('toString without cause', () {
      const error = SSHError('connection refused');
      expect(error.toString(), 'SSHError: connection refused');
    });

    test('toString with cause', () {
      final error = SSHError('connection refused', Exception('timeout'));
      expect(error.toString(), contains('caused by:'));
      expect(error.toString(), contains('connection refused'));
    });

    test('message getter', () {
      const error = SSHError('test message');
      expect(error.message, 'test message');
      expect(error.cause, isNull);
    });

    test('implements Exception', () {
      const error = SSHError('test');
      expect(error, isA<Exception>());
    });
  });

  group('AuthError', () {
    test('toString uses AuthError prefix', () {
      const error = AuthError('wrong password');
      expect(error.toString(), 'AuthError: wrong password');
    });

    test('extends SSHError', () {
      const error = AuthError('bad key');
      expect(error, isA<SSHError>());
    });

    test('with cause', () {
      const error = AuthError('auth failed', FormatException('bad PEM'));
      expect(error.cause, isA<FormatException>());
      expect(error.toString(), contains('caused by:'));
    });
  });

  group('ConnectError', () {
    test('toString uses ConnectError prefix', () {
      const error = ConnectError('host unreachable');
      expect(error.toString(), 'ConnectError: host unreachable');
    });

    test('extends SSHError', () {
      const error = ConnectError('timeout');
      expect(error, isA<SSHError>());
    });
  });

  group('SSHError — userMessage edge cases', () {
    test('userMessage returns just message when cause message equals message', () {
      // cause.toString() after stripping prefix == message → return message only
      final error = SSHError('timeout', Exception('timeout'));
      expect(error.userMessage, 'timeout');
    });

    test('userMessage with nested SSHError cause', () {
      const inner = AuthError('bad key');
      const outer = ConnectError('connection failed', inner);
      expect(outer.userMessage, 'connection failed (bad key)');
    });
  });

  group('HostKeyError', () {
    test('toString uses HostKeyError prefix', () {
      const error = HostKeyError('key mismatch');
      expect(error.toString(), 'HostKeyError: key mismatch');
    });

    test('extends SSHError', () {
      const error = HostKeyError('changed');
      expect(error, isA<SSHError>());
    });
  });
}
