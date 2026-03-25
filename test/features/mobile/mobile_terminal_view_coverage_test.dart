import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm/xterm.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_terminal_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

void main() {
  group('MobileTerminalView — error states', () {
    testWidgets('error text shows specific error message', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Connection refused'));

      final conn = Connection(
        id: 'test-err',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Connection refused'), findsOneWidget);
    });

    testWidgets('error text has disconnected color', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('fail'));

      final conn = Connection(
        id: 'test-color',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      final errorText = tester.widget<Text>(find.textContaining('fail'));
      expect(errorText.style?.color, AppTheme.disconnected);
    });

    testWidgets('null SSH connection shows error', (tester) async {
      final conn = Connection(
        id: 'test-null',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('error icon has size 48', (tester) async {
      final conn = Connection(
        id: 'test-size',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.size, 48);
      expect(icon.color, AppTheme.disconnected);
    });
  });

  group('MobileTerminalView — successful shell connection', () {
    testWidgets('TerminalView renders after shell connection', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test-ok',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Should show terminal (no error, no loading)
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);

      // Keyboard bar should be shown
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('session done shows Session closed error', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test-done',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Complete the done future to simulate session close
      doneCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('Session closed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('GestureDetector present for pinch zoom and long press',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test-gesture',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GestureDetector), findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('widget disposes without errors', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test-dispose',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Replace widget to trigger dispose
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('MobileTerminalView — loading state', () {
    testWidgets('shows loading while shell is opening (slow)', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'test-loading',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('MobileTerminalView — Column layout with keyboard bar', () {
    testWidgets('Column layout has Expanded terminal and keyboard bar',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      when(mockSsh.isConnected).thenReturn(true);

      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'test-layout',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: MobileTerminalView(connection: conn)),
        ),
      );
      await tester.pumpAndSettle();

      // Column layout present
      expect(find.byType(Column), findsWidgets);

      // Ctrl key for keyboard bar
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('Alt'), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });
}
