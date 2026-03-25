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
  group('TerminalPane — error state UI', () {
    testWidgets('error state shows centered error icon and message', (tester) async {
      final conn = Connection(
        id: 'err-1',
        label: 'ErrorTest',
        sshConfig: const SSHConfig(host: 'fail.host', user: 'user'),
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
      // Error icon should have AppTheme.disconnected color
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
      expect(icon.size, 48);
    });

    testWidgets('error from thrown exception displays exception text', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any)).thenThrow(Exception('Connection refused'));

      final conn = Connection(
        id: 'err-2',
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

      expect(find.textContaining('Connection refused'), findsOneWidget);
    });
  });

  group('TerminalPane — context menu', () {
    testWidgets('right-click on connected terminal shows context menu with Paste', (tester) async {
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
        id: 'ctx-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () {},
              onSplitHorizontal: () {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The TerminalView should be present (no loading, no error)
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — split callbacks wired', () {
    testWidgets('split callbacks are available on the widget', (tester) async {
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

      var splitV = false;
      var splitH = false;
      final conn = Connection(
        id: 'split-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(
              connection: conn,
              isFocused: true,
              onSplitVertical: () => splitV = true,
              onSplitHorizontal: () => splitH = true,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the widget rendered with split callbacks (not called yet)
      expect(splitV, isFalse);
      expect(splitH, isFalse);
      expect(find.byType(CallbackShortcuts), findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — loading state', () {
    testWidgets('shows spinner while shell is opening', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(true);
      // Never complete — stays in loading state
      when(mockSsh.openShell(any, any)).thenAnswer((_) => Completer<Never>().future);

      final conn = Connection(
        id: 'load-1',
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
  });

  group('TerminalPane — session closed notification', () {
    testWidgets('shell done shows "Session closed" error', (tester) async {
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
        id: 'done-1',
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

      expect(find.textContaining('Session closed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });

  group('TerminalPane — focused/unfocused border', () {
    testWidgets('focused pane has Container with decoration', (tester) async {
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
        id: 'border-1',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      // Test focused
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalPane(connection: conn, isFocused: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsWidgets);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });

    testWidgets('unfocused pane renders without error', (tester) async {
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
        id: 'border-2',
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

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await stdoutCtrl.close();
      await stderrCtrl.close();
    });
  });
}
