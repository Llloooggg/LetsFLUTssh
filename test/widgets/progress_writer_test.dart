import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/connection/progress_tracker.dart';
import 'package:letsflutssh/widgets/terminal/progress_writer.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

class _FakeL10n implements S {
  @override
  String progressConnecting(String host, int port) =>
      'Connecting to $host:$port';

  @override
  String get progressVerifyingHostKey => 'Verifying host key';

  @override
  String progressAuthenticating(String user) => 'Authenticating as $user';

  @override
  String get progressOpeningShell => 'Opening shell';

  @override
  String get progressOpeningSftp => 'Opening SFTP channel';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> written;
  late ProgressWriter writer;
  const config = SSHConfig(
    server: ServerAddress(host: '10.0.0.1', user: 'root'),
  );

  setUp(() {
    written = <String>[];
    writer = ProgressWriter.sink(
      sink: written.add,
      l10n: _FakeL10n(),
      config: config,
    );
  });

  String allText() => written.join();

  group('writeStep', () {
    test('inProgress writes yellow marker with dots', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.inProgress,
        ),
      );

      final content = allText();
      expect(content, contains('[*]'));
      expect(content, contains('Connecting to 10.0.0.1:22'));
      expect(content, contains('...'));
    });

    test('success writes green checkmark marker', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.hostKeyVerify,
          status: StepStatus.success,
        ),
      );

      final content = allText();
      expect(content, contains('[✓]'));
      expect(content, contains('Verifying host key'));
    });

    test('failed writes red cross marker with detail', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.failed,
          detail: 'wrong password',
        ),
      );

      final content = allText();
      expect(content, contains('[✗]'));
      expect(content, contains('Authenticating as root'));
      expect(content, contains('wrong password'));
    });

    test('failed without detail does not include a trailing colon', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.openChannel,
          status: StepStatus.failed,
        ),
      );

      final content = allText();
      expect(content, contains('Opening shell'));
      expect(content, isNot(contains('Opening shell:')));
    });

    test('each phase uses correct label', () {
      for (final phase in ConnectionPhase.values) {
        final captured = <String>[];
        final w = ProgressWriter.sink(
          sink: captured.add,
          l10n: _FakeL10n(),
          config: config,
        );
        w.writeStep(
          ConnectionStep(phase: phase, status: StepStatus.inProgress),
        );
        final text = captured.join();

        switch (phase) {
          case ConnectionPhase.socketConnect:
            expect(text, contains('Connecting to 10.0.0.1:22'));
          case ConnectionPhase.hostKeyVerify:
            expect(text, contains('Verifying host key'));
          case ConnectionPhase.authenticate:
            expect(text, contains('Authenticating as root'));
          case ConnectionPhase.openChannel:
            expect(text, contains('Opening shell'));
        }
      }
    });
  });

  group('clear', () {
    test('writes without error', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.inProgress,
        ),
      );
      expect(() => writer.clear(), returnsNormally);
      // clear emits a screen-clear + cursor-show sequence.
      expect(allText(), contains('\x1B[2J'));
    });
  });

  group('subscribe', () {
    test('replays history then listens to stream', () async {
      final conn = Connection(
        id: 'test-id',
        label: 'Test',
        sshConfig: config,
        state: SSHConnectionState.connecting,
      );

      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.inProgress,
        ),
      );
      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.success,
        ),
      );

      final tracker = ProgressTracker(conn);
      final sub = writer.subscribe(tracker);

      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.hostKeyVerify,
          status: StepStatus.inProgress,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final content = allText();
      expect(content, contains('Connecting to 10.0.0.1:22'));
      expect(content, contains('Verifying host key'));

      await sub.cancel();
      tracker.dispose();
    });

    test('returns cancellable subscription', () async {
      final conn = Connection(
        id: 'test-id',
        label: 'Test',
        sshConfig: config,
        state: SSHConnectionState.connecting,
      );

      final tracker = ProgressTracker(conn);
      final sub = writer.subscribe(tracker);
      await sub.cancel();
      tracker.dispose();

      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.inProgress,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });
  });
}
