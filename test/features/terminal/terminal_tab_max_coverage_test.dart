import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

void main() {
  Connection makeConnectedConn(MockSSHConnection mockSsh, MockSSHSession mockSession) {
    final stdoutCtrl = StreamController<Uint8List>.broadcast();
    final stderrCtrl = StreamController<Uint8List>.broadcast();
    final doneCompleter = Completer<void>();

    when(mockSsh.isConnected).thenReturn(true);
    when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
    when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
    when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
    when(mockSession.done).thenAnswer((_) => doneCompleter.future);

    return Connection(
      id: 'conn-max',
      label: 'MaxCovServer',
      sshConfig: const SSHConfig(host: 'h', user: 'u'),
      sshConnection: mockSsh,
      state: SSHConnectionState.connected,
    );
  }

  group('TerminalTab — onDisconnected callback from error state', () {
    testWidgets('Close button fires onDisconnected callback', (tester) async {
      var disconnected = false;
      final conn = Connection(
        id: 'cb-disc',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-cb-disc',
              connection: conn,
              onDisconnected: () => disconnected = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();

      expect(disconnected, isTrue);
    });
  });

  group('TerminalTab — reconnect factory success clears panes', () {
    testWidgets('successful reconnect resets to single pane and shows tiling', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();

      // Start disconnected
      final conn = Connection(
        id: 'reconn-reset',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      // After reconnect, provide a connected mock
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-reconn-reset',
              connection: conn,
              reconnectFactory: (c) async {
                // Setup mock SSH connection
                final stdoutCtrl = StreamController<Uint8List>.broadcast();
                final stderrCtrl = StreamController<Uint8List>.broadcast();
                final doneCompleter = Completer<void>();

                when(mockSsh.isConnected).thenReturn(true);
                when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
                when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
                when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
                when(mockSession.done).thenAnswer((_) => doneCompleter.future);

                c.sshConnection = mockSsh;
                c.state = SSHConnectionState.connected;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Should be in error state
      expect(find.text('Not connected'), findsOneWidget);

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // Should no longer show error
      expect(find.text('Not connected'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — reconnect failure shows error message', () {
    testWidgets('reconnect exception displays error with message', (tester) async {
      final conn = Connection(
        id: 'reconn-fail',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-reconn-fail',
              connection: conn,
              reconnectFactory: (_) async {
                throw Exception('connection refused');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reconnect failed'), findsOneWidget);
      expect(find.textContaining('connection refused'), findsOneWidget);
    });
  });

  group('TerminalTab — connected state builds TilingView', () {
    testWidgets('connected terminal renders without error or spinner', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-connected-tv',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — loading state shows spinner during async reconnect', () {
    testWidgets('spinner shown while reconnect factory is running', (tester) async {
      final completer = Completer<void>();
      final conn = Connection(
        id: 'spinner',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-spinner',
              connection: conn,
              reconnectFactory: (_) => completer.future,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap reconnect, spinner should appear
      await tester.tap(find.text('Reconnect'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete and verify spinner gone
      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — error text styling', () {
    testWidgets('error text has disconnected color', (tester) async {
      final conn = Connection(
        id: 'err-style',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(tabId: 'tab-err-style', connection: conn),
          ),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text('Not connected'));
      expect(text.style?.color, AppTheme.disconnected);
    });
  });

  group('TerminalTab — reconnect without factory (null sshConnection)', () {
    testWidgets('reconnect without factory and null sshConnection shows error', (tester) async {
      final conn = Connection(
        id: 'no-factory',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-no-factory',
              connection: conn,
              // No reconnectFactory — uses real reconnect path
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap reconnect — will fail because sshConnection is null
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // Should show reconnect failed error
      expect(find.textContaining('Reconnect failed'), findsOneWidget);
    });
  });
}
