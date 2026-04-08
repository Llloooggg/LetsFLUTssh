import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  late Connection conn;

  setUp(() {
    conn = Connection(
      id: 'test-id',
      label: 'Test',
      sshConfig: const SSHConfig(
        server: ServerAddress(host: '10.0.0.1', user: 'root'),
      ),
      state: SSHConnectionState.connecting,
    );
  });

  group('progressStream', () {
    test('emits steps added via addProgressStep', () async {
      const step = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );

      final future = conn.progressStream.first;
      conn.addProgressStep(step);

      expect(await future, equals(step));
    });

    test('emits multiple steps in order', () async {
      const step1 = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );
      const step2 = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.success,
      );
      const step3 = ConnectionStep(
        phase: ConnectionPhase.hostKeyVerify,
        status: StepStatus.inProgress,
      );

      final collected = <ConnectionStep>[];
      conn.progressStream.listen(collected.add);

      conn.addProgressStep(step1);
      conn.addProgressStep(step2);
      conn.addProgressStep(step3);

      // Allow microtasks to deliver events.
      await Future<void>.delayed(Duration.zero);

      expect(collected, [step1, step2, step3]);
    });
  });

  group('progressHistory', () {
    test('buffers all added steps', () {
      const step1 = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );
      const step2 = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.success,
      );

      conn.addProgressStep(step1);
      conn.addProgressStep(step2);

      expect(conn.progressHistory, [step1, step2]);
    });

    test('returns unmodifiable list', () {
      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.inProgress,
        ),
      );

      expect(
        () => conn.progressHistory.add(
          const ConnectionStep(
            phase: ConnectionPhase.socketConnect,
            status: StepStatus.success,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('completeReady', () {
    test('closes the progressStream', () async {
      final done = conn.progressStream.isEmpty;
      conn.completeReady();
      expect(await done, isTrue);
    });

    test('completes the ready future', () async {
      conn.completeReady();
      // Should not hang — completes immediately.
      await conn.ready;
    });
  });

  group('addProgressStep after close', () {
    test('is a no-op and does not throw', () {
      conn.completeReady();

      // Should not throw even though the stream is closed.
      expect(
        () => conn.addProgressStep(
          const ConnectionStep(
            phase: ConnectionPhase.authenticate,
            status: StepStatus.failed,
            detail: 'late step',
          ),
        ),
        returnsNormally,
      );
    });

    test('still adds to history even after close', () {
      conn.completeReady();

      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.failed,
        ),
      );

      expect(conn.progressHistory, hasLength(1));
    });
  });

  group('resetForReconnect', () {
    test('creates fresh completer and stream, clears history and error', () {
      // Populate some state first.
      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.success,
        ),
      );
      conn.connectionError = 'some error';
      conn.completeReady();

      conn.resetForReconnect();

      expect(conn.progressHistory, isEmpty);
      expect(conn.connectionError, isNull);
    });

    test('progressStream works again after reset', () async {
      conn.completeReady();
      conn.resetForReconnect();

      const step = ConnectionStep(
        phase: ConnectionPhase.hostKeyVerify,
        status: StepStatus.inProgress,
      );

      final future = conn.progressStream.first;
      conn.addProgressStep(step);

      expect(await future, equals(step));
    });

    test('ready future can be awaited again after reset', () async {
      conn.completeReady();
      conn.resetForReconnect();

      // The new ready should not be completed yet.
      var completed = false;
      conn.ready.then((_) => completed = true);

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      conn.completeReady();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isTrue);
    });
  });
}
