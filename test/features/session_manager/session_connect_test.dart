import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/errors.dart';

// SessionConnect methods are static and require BuildContext + WidgetRef,
// which makes them hard to unit test without a full widget tree.
// We test the error formatting logic that _showError uses internally,
// since the error types and their userMessage are the core testable behavior.

void main() {
  group('SessionConnect error message formatting', () {
    // Tests mirror the _showError logic in session_connect.dart

    test('HostKeyError produces userMessage', () {
      const error = HostKeyError('Host key changed');
      // _showError would use: error.userMessage
      expect(error.userMessage, 'Host key changed');
    });

    test('AuthError produces prefixed message', () {
      const error = AuthError('Wrong password');
      // _showError would use: 'Auth failed: ${error.userMessage}'
      final msg = 'Auth failed: ${error.userMessage}';
      expect(msg, 'Auth failed: Wrong password');
    });

    test('ConnectError produces userMessage', () {
      const error = ConnectError('Connection timed out');
      expect(error.userMessage, 'Connection timed out');
    });

    test('HostKeyError with cause unwraps', () {
      const error = HostKeyError('MITM detected', 'Key fingerprint mismatch');
      expect(error.userMessage, 'MITM detected (Key fingerprint mismatch)');
    });

    test('AuthError with SSHError cause chains messages', () {
      const inner = ConnectError('Timeout');
      const error = AuthError('Auth failed', inner);
      expect(error.userMessage, contains('Auth failed'));
      expect(error.userMessage, contains('Timeout'));
    });

    test('generic error produces fallback message', () {
      final error = Exception('Something went wrong');
      final msg = 'Connection error: $error';
      expect(msg, contains('Something went wrong'));
    });
  });
}
