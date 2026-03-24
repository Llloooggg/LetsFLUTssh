import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm/xterm.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/shell_helper.dart';
import 'package:letsflutssh/core/ssh/ssh_client.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

@GenerateNiceMocks([MockSpec<SSHConnection>(), MockSpec<SSHSession>()])
import 'shell_helper_test.mocks.dart';

void main() {
  group('ShellHelper.openShell', () {
    test('throws StateError when sshConnection is null', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      expect(
        () => ShellHelper.openShell(connection: conn, terminal: Terminal()),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when sshConnection.isConnected is false', () async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(false);

      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: mockSsh,
        state: SSHConnectionState.disconnected,
      );

      expect(
        () => ShellHelper.openShell(connection: conn, terminal: Terminal()),
        throwsA(isA<StateError>()),
      );
    });

    test('opens shell and wires streams on success', () async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>();
      final stderrCtrl = StreamController<Uint8List>();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      final terminal = Terminal();
      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: terminal,
      );

      expect(result, isNotNull);
      expect(result.shell, mockSession);

      // Verify stdout wiring — send data through mock stdout
      stdoutCtrl.add(Uint8List.fromList('hello'.codeUnits));
      await Future.delayed(Duration.zero);

      // Cleanup
      result.close();
      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    test('retries on failure and succeeds on later attempt', () async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      var attempts = 0;
      when(mockSsh.openShell(any, any)).thenAnswer((_) async {
        attempts++;
        if (attempts < 3) throw Exception('Channel rejected');
        return mockSession;
      });

      final stdoutCtrl = StreamController<Uint8List>();
      final stderrCtrl = StreamController<Uint8List>();
      final doneCompleter = Completer<void>();

      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: Terminal(),
      );

      expect(attempts, 3);
      expect(result.shell, mockSession);

      result.close();
      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    test('throws after maxAttempts exhausted', () async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('always fails'));

      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      expect(
        () => ShellHelper.openShell(
          connection: conn,
          terminal: Terminal(),
          maxAttempts: 2,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('calls onDone when shell session closes', () async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>();
      final stderrCtrl = StreamController<Uint8List>();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      var doneCalled = false;
      await ShellHelper.openShell(
        connection: conn,
        terminal: Terminal(),
        onDone: () => doneCalled = true,
      );

      // Simulate shell closing
      doneCompleter.complete();
      await Future.delayed(Duration.zero);

      expect(doneCalled, isTrue);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    test('terminal.onOutput writes to shell stdin', () async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>();
      final stderrCtrl = StreamController<Uint8List>();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      final terminal = Terminal();
      final result = await ShellHelper.openShell(
        connection: conn,
        terminal: terminal,
      );

      // Simulate terminal output (user typing)
      terminal.onOutput?.call('ls\n');
      verify(mockSession.write(Uint8List.fromList('ls\n'.codeUnits))).called(1);

      result.close();
      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('ShellConnection', () {
    test('close cancels subscriptions and closes shell', () async {
      final mockSession = MockSSHSession();
      final stdoutCtrl = StreamController<Uint8List>();
      final stderrCtrl = StreamController<Uint8List>();

      final stdoutSub = stdoutCtrl.stream.listen((_) {});
      final stderrSub = stderrCtrl.stream.listen((_) {});

      final shellConn = ShellConnection(
        shell: mockSession,
        stdoutSub: stdoutSub,
        stderrSub: stderrSub,
      );

      shellConn.close();

      // Verify shell was closed
      verify(mockSession.close()).called(1);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });
}
