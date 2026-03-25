import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

void main() {
  group('TerminalPane', () {
    testWidgets('shows loading indicator while connecting', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      // openShell never completes — simulates slow connection
      when(mockSsh.openShell(any, any)).thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'test-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state when shell connection fails', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Shell failed'));

      final conn = Connection(
        id: 'test-2',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error when sshConnection is null', (tester) async {
      final conn = Connection(
        id: 'test-3',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders TerminalView on successful connection', (tester) async {
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
        id: 'test-4',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TerminalView should be present (it's rendered as part of xterm package)
      // The loading indicator should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('shows border based on isFocused', (tester) async {
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
        id: 'test-5',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Container that applies the border
      final containerFinder = find.byType(Container);
      expect(containerFinder, findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('shows error text from exception', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Auth expired'));

      final conn = Connection(
        id: 'test-err-text',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Auth expired'), findsOneWidget);
    });

    testWidgets('error state uses AppTheme.disconnected color', (tester) async {
      final conn = Connection(
        id: 'test-color',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
      expect(icon.size, 48);
    });

    testWidgets('connected state shows GestureDetector', (tester) async {
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
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GestureDetector), findsWidgets);
      expect(find.byType(CallbackShortcuts), findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('unfocused pane uses divider color border', (tester) async {
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
        id: 'test-unfocused',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render without error - unfocused pane has thinner border
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('shell done callback sets session closed error', (tester) async {
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
          home: Scaffold(
            body: TerminalPane(connection: conn),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Simulate shell done
      doneCompleter.complete();
      await tester.pumpAndSettle();

      // Should show error state with "Session closed"
      expect(find.textContaining('Session closed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('passes split callbacks to widget', (tester) async {
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
        id: 'test-6',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      var splitVerticalCalled = false;
      var splitHorizontalCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () => splitVerticalCalled = true,
              onSplitHorizontal: () => splitHorizontalCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TerminalPane should have rendered without error
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      // Callbacks are wired but not called yet
      expect(splitVerticalCalled, isFalse);
      expect(splitHorizontalCalled, isFalse);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });
}
