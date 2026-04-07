import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';

void main() {
  group('ConnectionPhase', () {
    test('has exactly 4 values', () {
      expect(ConnectionPhase.values, hasLength(4));
    });

    test('contains expected values', () {
      expect(
        ConnectionPhase.values,
        containsAll([
          ConnectionPhase.socketConnect,
          ConnectionPhase.hostKeyVerify,
          ConnectionPhase.authenticate,
          ConnectionPhase.openChannel,
        ]),
      );
    });
  });

  group('StepStatus', () {
    test('has exactly 3 values', () {
      expect(StepStatus.values, hasLength(3));
    });

    test('contains expected values', () {
      expect(
        StepStatus.values,
        containsAll([
          StepStatus.inProgress,
          StepStatus.success,
          StepStatus.failed,
        ]),
      );
    });
  });

  group('ConnectionStep', () {
    test('equality: identical fields are equal', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
        detail: 'hello',
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
        detail: 'hello',
      );
      expect(a, equals(b));
    });

    test('equality: different phase are not equal', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.success,
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.authenticate,
        status: StepStatus.success,
      );
      expect(a, isNot(equals(b)));
    });

    test('equality: different status are not equal', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.success,
      );
      expect(a, isNot(equals(b)));
    });

    test('equality: different detail are not equal', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.failed,
        detail: 'error A',
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.failed,
        detail: 'error B',
      );
      expect(a, isNot(equals(b)));
    });

    test('equality: null detail vs non-null are not equal', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
        detail: 'some detail',
      );
      expect(a, isNot(equals(b)));
    });

    test('hashCode: equal objects have equal hashCodes', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.authenticate,
        status: StepStatus.failed,
        detail: 'bad key',
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.authenticate,
        status: StepStatus.failed,
        detail: 'bad key',
      );
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hashCode: different objects likely differ', () {
      const a = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );
      const b = ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.success,
      );
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('toString includes phase, status, and detail', () {
      const step = ConnectionStep(
        phase: ConnectionPhase.hostKeyVerify,
        status: StepStatus.success,
        detail: 'SHA256:abc',
      );
      final str = step.toString();
      expect(str, contains('ConnectionStep'));
      expect(str, contains('hostKeyVerify'));
      expect(str, contains('success'));
      expect(str, contains('SHA256:abc'));
    });

    test('toString with null detail', () {
      const step = ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.inProgress,
      );
      final str = step.toString();
      expect(str, contains('null'));
    });
  });
}
