import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/features/session_manager/session_forwards_logic.dart';

void main() {
  group('validatePortForwardPort', () {
    test('valid TCP ports pass', () {
      expect(validatePortForwardPort('1'), isNull);
      expect(validatePortForwardPort('22'), isNull);
      expect(validatePortForwardPort('8080'), isNull);
      expect(validatePortForwardPort('65535'), isNull);
    });

    test('whitespace around the value is tolerated', () {
      expect(validatePortForwardPort(' 22 '), isNull);
      expect(validatePortForwardPort('\t22\n'), isNull);
    });

    test('out-of-range numbers are rejected', () {
      expect(validatePortForwardPort('0'), portValidationError);
      expect(validatePortForwardPort('-1'), portValidationError);
      expect(validatePortForwardPort('65536'), portValidationError);
      expect(validatePortForwardPort('999999'), portValidationError);
    });

    test('non-numeric input is rejected', () {
      expect(validatePortForwardPort(''), portValidationError);
      expect(validatePortForwardPort(null), portValidationError);
      expect(validatePortForwardPort('   '), portValidationError);
      expect(validatePortForwardPort('22a'), portValidationError);
      expect(validatePortForwardPort('22.5'), portValidationError);
      expect(validatePortForwardPort('twenty-two'), portValidationError);
    });
  });

  group('validatePortForwardHost', () {
    test('dynamic forward never requires a host', () {
      expect(validatePortForwardHost(null, PortForwardKind.dynamic_), isNull);
      expect(validatePortForwardHost('', PortForwardKind.dynamic_), isNull);
      expect(validatePortForwardHost('   ', PortForwardKind.dynamic_), isNull);
      expect(
        validatePortForwardHost('192.0.2.1', PortForwardKind.dynamic_),
        isNull,
      );
    });

    test(
      'static (local / remote) forward requires a non-empty trimmed host',
      () {
        for (final kind in [PortForwardKind.local, PortForwardKind.remote]) {
          expect(
            validatePortForwardHost(null, kind),
            hostValidationEmpty,
            reason: '$kind null host',
          );
          expect(
            validatePortForwardHost('', kind),
            hostValidationEmpty,
            reason: '$kind empty host',
          );
          expect(
            validatePortForwardHost('   ', kind),
            hostValidationEmpty,
            reason: '$kind whitespace-only host',
          );
          expect(
            validatePortForwardHost('192.0.2.1', kind),
            isNull,
            reason: '$kind valid host',
          );
          expect(
            validatePortForwardHost('  example.org  ', kind),
            isNull,
            reason: '$kind whitespace-padded valid host',
          );
        }
      },
    );
  });
}
