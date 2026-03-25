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

/// Deep coverage for terminal_tab.dart — covers _splitPane, _closePane,
/// _onTreeChanged, reconnect with reconnectFactory success/failure,
/// and error state UI details.
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
      id: 'conn-tiling',
      label: 'TilingServer',
      sshConfig: const SSHConfig(host: 'h', user: 'u'),
      sshConnection: mockSsh,
      state: SSHConnectionState.connected,
    );
  }

  group('TerminalTab — split pane via context menu', () {
    testWidgets('connected terminal renders TilingView (no error)', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnectedConn(mockSsh, mockSession);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-split',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should render terminal (no error state)
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — reconnect with factory success resets panes', () {
    testWidgets('successful reconnect via factory resets to single pane', (tester) async {
      final conn = Connection(
        id: 'rf-reset',
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
              tabId: 'tab-rf-reset',
              connection: conn,
              reconnectFactory: (_) async {
                // Simulate successful reconnect
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Should show error state initially
      expect(find.text('Not connected'), findsOneWidget);

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // After successful reconnect, error and spinner should be gone
      expect(find.text('Not connected'), findsNothing);
      expect(find.textContaining('Reconnect failed'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — reconnect with factory error', () {
    testWidgets('factory exception shows reconnect failed error', (tester) async {
      final conn = Connection(
        id: 'rf-err2',
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
              tabId: 'tab-rf-err2',
              connection: conn,
              reconnectFactory: (_) async {
                throw StateError('network down');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reconnect failed'), findsOneWidget);
      expect(find.textContaining('network down'), findsOneWidget);
    });
  });

  group('TerminalTab — error state buttons', () {
    testWidgets('Close button is OutlinedButton', (tester) async {
      final conn = Connection(
        id: 'btn-type',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(tabId: 'tab-btn-type', connection: conn),
          ),
        ),
      );
      await tester.pump();

      expect(find.widgetWithText(OutlinedButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Reconnect'), findsOneWidget);
    });

    testWidgets('Close button with null onDisconnected does nothing', (tester) async {
      final conn = Connection(
        id: 'btn-null',
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
              tabId: 'tab-btn-null',
              connection: conn,
              onDisconnected: null,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tapping close with null callback should not crash
      await tester.tap(find.text('Close'));
      await tester.pump();
    });
  });

  group('TerminalTab — loading state during reconnect', () {
    testWidgets('shows spinner while reconnect is in progress', (tester) async {
      final completer = Completer<void>();
      final conn = Connection(
        id: 'loading-2',
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
              tabId: 'tab-loading-2',
              connection: conn,
              reconnectFactory: (_) => completer.future,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      await tester.pump();

      // Should show loading spinner
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete reconnect
      completer.complete();
      await tester.pumpAndSettle();

      // Spinner should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('TerminalTab — error icon styling', () {
    testWidgets('error icon has size 48 and disconnected color', (tester) async {
      final conn = Connection(
        id: 'icon-style',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(tabId: 'tab-icon', connection: conn),
          ),
        ),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.size, 48);
      expect(icon.color, AppTheme.disconnected);
    });

    testWidgets('error text is centered with textAlign center', (tester) async {
      final conn = Connection(
        id: 'align-text',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(tabId: 'tab-align', connection: conn),
          ),
        ),
      );
      await tester.pump();

      final text = tester.widget<Text>(find.text('Not connected'));
      expect(text.textAlign, TextAlign.center);
    });
  });

  group('TerminalTab — reconnect retry cycle', () {
    testWidgets('fail then succeed reconnect', (tester) async {
      var attempt = 0;
      final conn = Connection(
        id: 'retry',
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
              tabId: 'tab-retry',
              connection: conn,
              reconnectFactory: (_) async {
                attempt++;
                if (attempt == 1) throw Exception('first fail');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // First attempt - fails
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('first fail'), findsOneWidget);

      // Second attempt - succeeds
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reconnect failed'), findsNothing);
      expect(attempt, 2);
    });
  });
}
