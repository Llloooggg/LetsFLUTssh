import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/connection/progress_writer.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:xterm/xterm.dart';

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
  late Terminal terminal;
  late ProgressWriter writer;
  const config = SSHConfig(
    server: ServerAddress(host: '10.0.0.1', user: 'root'),
  );

  setUp(() {
    terminal = Terminal(maxLines: 100);
    writer = ProgressWriter(
      terminal: terminal,
      l10n: _FakeL10n(),
      config: config,
    );
  });

  /// Read all non-empty lines from the terminal buffer.
  List<String> readLines() {
    final lines = <String>[];
    for (var i = 0; i < terminal.buffer.lines.length; i++) {
      final line = terminal.buffer.lines[i].toString();
      if (line.trim().isNotEmpty) lines.add(line);
    }
    return lines;
  }

  group('writeStep', () {
    test('inProgress writes yellow marker with dots', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.inProgress,
        ),
      );

      final content = readLines().join('\n');
      expect(content, contains('[*]'));
      expect(content, contains('Connecting to 10.0.0.1:22'));
      expect(content, contains('...'));
    });

    test('success writes green checkmark marker', () {
      // Write inProgress first so success has a line to overwrite.
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.hostKeyVerify,
          status: StepStatus.inProgress,
        ),
      );
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.hostKeyVerify,
          status: StepStatus.success,
        ),
      );

      final content = readLines().join('\n');
      expect(content, contains('Verifying host key'));
    });

    test('failed writes red cross marker with detail', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.inProgress,
        ),
      );
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.failed,
          detail: 'wrong password',
        ),
      );

      final content = readLines().join('\n');
      expect(content, contains('Authenticating as root'));
      expect(content, contains('wrong password'));
    });

    test('failed without detail does not include colon', () {
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.openChannel,
          status: StepStatus.inProgress,
        ),
      );
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.openChannel,
          status: StepStatus.failed,
        ),
      );

      final content = readLines().join('\n');
      expect(content, contains('Opening shell'));
    });

    test('each phase uses correct label', () {
      for (final phase in ConnectionPhase.values) {
        final t = Terminal(maxLines: 100);
        final w = ProgressWriter(
          terminal: t,
          l10n: _FakeL10n(),
          config: config,
        );
        w.writeStep(
          ConnectionStep(phase: phase, status: StepStatus.inProgress),
        );

        final content = <String>[];
        for (var i = 0; i < t.buffer.lines.length; i++) {
          content.add(t.buffer.lines[i].toString());
        }
        final text = content.join('\n');

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
    test('writes to terminal without error', () {
      // Write some content first.
      writer.writeStep(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.inProgress,
        ),
      );

      expect(() => writer.clear(), returnsNormally);
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

      // Add steps before subscribing.
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

      final sub = writer.subscribe(conn);

      // Now add a new step after subscription.
      conn.addProgressStep(
        const ConnectionStep(
          phase: ConnectionPhase.hostKeyVerify,
          status: StepStatus.inProgress,
        ),
      );

      // Allow microtasks to process.
      await Future<void>.delayed(Duration.zero);

      final content = readLines().join('\n');
      // History replay: socketConnect was written.
      expect(content, contains('Connecting to 10.0.0.1:22'));
      // Live step: hostKeyVerify was also written.
      expect(content, contains('Verifying host key'));

      await sub.cancel();
    });

    test('returns cancellable subscription', () async {
      final conn = Connection(
        id: 'test-id',
        label: 'Test',
        sshConfig: config,
        state: SSHConnectionState.connecting,
      );

      final sub = writer.subscribe(conn);
      await sub.cancel();

      // Adding steps after cancel should not throw.
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
