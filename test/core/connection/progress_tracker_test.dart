import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/connection/progress_tracker.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

Connection _makeConnection() => Connection(
  id: 'test',
  label: 'Test',
  sshConfig: const SSHConfig(
    server: ServerAddress(host: 'localhost', user: 'user'),
  ),
);

void main() {
  group('ProgressTracker', () {
    test('replays existing progress history on construction', () {
      final conn = _makeConnection();
      const step = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      );
      conn.addProgressStep(step);

      final tracker = ProgressTracker(conn);
      addTearDown(tracker.dispose);

      expect(tracker.history, [step]);
    });

    test('receives new shared steps from connection', () async {
      final conn = _makeConnection();
      final tracker = ProgressTracker(conn);
      addTearDown(tracker.dispose);

      const step = ConnectionStep(
        phase: ConnectionPhase.authenticate,
        status: StepStatus.success,
      );

      final future = tracker.stream.first;
      conn.addProgressStep(step);
      final received = await future;

      expect(received, step);
      expect(tracker.history, [step]);
    });

    test('addLocalStep does not propagate to connection stream', () async {
      final conn = _makeConnection();
      final tracker = ProgressTracker(conn);
      addTearDown(tracker.dispose);

      const localStep = ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.inProgress,
        detail: 'Opening SFTP',
      );

      final trackerSteps = <ConnectionStep>[];
      tracker.stream.listen(trackerSteps.add);

      final connSteps = <ConnectionStep>[];
      conn.progressStream.listen(connSteps.add);

      tracker.addLocalStep(localStep);

      // Let microtasks run
      await Future<void>.delayed(Duration.zero);

      expect(trackerSteps, [localStep]);
      expect(connSteps, isEmpty);
      expect(tracker.history, [localStep]);
    });

    test('merges shared and local steps in order', () async {
      final conn = _makeConnection();
      const shared1 = ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.success,
      );
      conn.addProgressStep(shared1);

      final tracker = ProgressTracker(conn);
      addTearDown(tracker.dispose);

      const local1 = ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.inProgress,
        detail: 'Opening shell',
      );
      tracker.addLocalStep(local1);

      const shared2 = ConnectionStep(
        phase: ConnectionPhase.authenticate,
        status: StepStatus.success,
      );
      conn.addProgressStep(shared2);

      // Let microtasks run
      await Future<void>.delayed(Duration.zero);

      expect(tracker.history, [shared1, local1, shared2]);
    });

    test('history is unmodifiable', () {
      final conn = _makeConnection();
      final tracker = ProgressTracker(conn);
      addTearDown(tracker.dispose);

      expect(
        () => tracker.history.add(
          const ConnectionStep(
            phase: ConnectionPhase.socketConnect,
            status: StepStatus.inProgress,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('dispose cancels subscription and closes stream', () async {
      final conn = _makeConnection();
      final tracker = ProgressTracker(conn);

      final streamDone = tracker.stream.toList();
      tracker.dispose();

      // Stream should complete after dispose
      await streamDone;

      // Adding to connection after dispose should not crash
      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.success,
        ),
      );

      // Tracker history is frozen at dispose time
      expect(tracker.history, isEmpty);
    });

    test('multiple trackers on same connection are independent', () async {
      final conn = _makeConnection();
      final tracker1 = ProgressTracker(conn);
      final tracker2 = ProgressTracker(conn);
      addTearDown(tracker1.dispose);
      addTearDown(tracker2.dispose);

      const local1 = ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.inProgress,
        detail: 'shell',
      );
      const local2 = ConnectionStep(
        phase: ConnectionPhase.openChannel,
        status: StepStatus.inProgress,
        detail: 'sftp',
      );

      tracker1.addLocalStep(local1);
      tracker2.addLocalStep(local2);

      expect(tracker1.history, [local1]);
      expect(tracker2.history, [local2]);
    });
  });
}
