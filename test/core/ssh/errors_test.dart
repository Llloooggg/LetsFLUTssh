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

    test('stores user and host', () {
      const error = AuthError('auth failed', null, 'root', 'example.com');
      expect(error.user, 'root');
      expect(error.host, 'example.com');
    });

    test('user and host default to null', () {
      const error = AuthError('auth failed');
      expect(error.user, isNull);
      expect(error.host, isNull);
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

    test('stores host and port', () {
      const error = ConnectError('failed', null, 'example.com', 22);
      expect(error.host, 'example.com');
      expect(error.port, 22);
    });

    test('host and port default to null', () {
      const error = ConnectError('failed');
      expect(error.host, isNull);
      expect(error.port, isNull);
    });
  });

  group('SSHError — userMessage edge cases', () {
    test(
      'userMessage returns just message when cause message equals message',
      () {
        // cause.toString() after stripping prefix == message → return message only
        final error = SSHError('timeout', Exception('timeout'));
        expect(error.userMessage, 'timeout');
      },
    );

    test('userMessage with nested SSHError cause', () {
      const inner = AuthError('bad key');
      const outer = ConnectError('connection failed', inner);
      expect(outer.userMessage, 'connection failed (bad key)');
    });

    test('userMessage drops an empty-string cause rather than show "( )"', () {
      // A cause whose stringification is empty must not produce a bare
      // "message ()" — the `causeStr.isNotEmpty` guard keeps the output
      // to the message alone.
      const error = SSHError('outer', '');
      expect(error.userMessage, 'outer');
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

    test('stores host and port', () {
      const error = HostKeyError('rejected', null, 'example.com', 22);
      expect(error.host, 'example.com');
      expect(error.port, 22);
    });

    test('host and port default to null', () {
      const error = HostKeyError('rejected');
      expect(error.host, isNull);
      expect(error.port, isNull);
    });
  });

  group('SSHError — _rootCauseMessage prefix stripping', () {
    test('strips SocketException: prefix from string causes', () {
      // Plain `Exception(message)` toString-prefixes "Exception: "; we
      // strip that out for cleaner display. SocketException uses the
      // same shape, but its toString is locale-sensitive in production
      // — for this test we lean on the fact that the prefix-strip
      // routine matches by string prefix, so a manually-constructed
      // string-typed cause exercises the same code path.
      const error = SSHError('outer', 'SocketException: Connection refused');
      expect(error.userMessage, 'outer (Connection refused)');
    });

    test('strips Exception: prefix from string causes', () {
      const error = SSHError('outer', 'Exception: inner-detail');
      expect(error.userMessage, 'outer (inner-detail)');
    });

    test('strips SSHAuthFailError: prefix', () {
      const error = SSHError('outer', 'SSHAuthFailError: bad password');
      expect(error.userMessage, 'outer (bad password)');
    });

    test('strips SSHAuthAbortError: prefix', () {
      const error = SSHError('outer', 'SSHAuthAbortError: cancelled');
      expect(error.userMessage, 'outer (cancelled)');
    });

    test('non-prefixed string cause passes through verbatim', () {
      const error = SSHError('outer', 'plain string detail');
      expect(error.userMessage, 'outer (plain string detail)');
    });

    test('cause whose message equals the outer collapses to one copy', () {
      // Pin the "cause echoes outer" branch — userMessage returns just
      // the message without the redundant parenthesised cause.
      const error = SSHError('same', 'same');
      expect(error.userMessage, 'same');
    });
  });

  group('ProxyJumpCycleError', () {
    test('message names the offending session', () {
      final err = ProxyJumpCycleError('sid-99');
      expect(err.message, contains('sid-99'));
      expect(err.offendingSessionId, 'sid-99');
      expect(err, isA<SSHError>());
    });
  });

  group('ProxyJumpDepthError', () {
    test('message includes the depth limit', () {
      final err = ProxyJumpDepthError(8);
      expect(err.message, contains('8'));
      expect(err.depth, 8);
    });
  });

  group('ProxyJumpBastionError', () {
    test('wraps the underlying cause + names the bastion', () {
      const inner = ConnectError('refused');
      final err = ProxyJumpBastionError('alice@bastion', inner);
      expect(err.bastionLabel, 'alice@bastion');
      expect(err.cause, same(inner));
      expect(err.message, contains('alice@bastion'));
    });

    test('userMessage unwraps the cause for display', () {
      const inner = ConnectError('refused');
      final err = ProxyJumpBastionError('b', inner);
      expect(err.userMessage, contains('refused'));
    });
  });

  group('HardwareKeyPromptCancelled', () {
    test('carries the supplied message and is an SSHError', () {
      // The connect-progress UI shows this as a deliberate user
      // dismissal, not a fault — message passes through verbatim and
      // the type stays in the SSHError hierarchy so existing catch
      // clauses still see it.
      const error = HardwareKeyPromptCancelled('PIN prompt cancelled');
      expect(error.message, 'PIN prompt cancelled');
      expect(error, isA<SSHError>());
    });

    test('toString uses the HardwareKeyPromptCancelled prefix', () {
      const error = HardwareKeyPromptCancelled('cancelled');
      expect(error.toString(), 'HardwareKeyPromptCancelled: cancelled');
    });

    test('userMessage with no cause is just the message', () {
      const error = HardwareKeyPromptCancelled('user dismissed');
      expect(error.userMessage, 'user dismissed');
    });
  });
}
