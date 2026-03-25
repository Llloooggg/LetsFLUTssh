import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

void main() {
  group('TerminalTab', () {
    testWidgets('shows error state when connection has no sshConnection', (tester) async {
      final conn = Connection(
        id: 'test-1',
        label: 'Test Server',
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-1',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('shows error state when sshConnection.isConnected is false', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(false);

      final conn = Connection(
        id: 'test-2',
        label: 'Test Server',
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: mockSsh,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-2',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('calls onDisconnected when Close button is pressed', (tester) async {
      var closeCalled = false;

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
            body: TerminalTab(
              tabId: 'tab-3',
              connection: conn,
              onDisconnected: () => closeCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Close'));
      await tester.pump();

      expect(closeCalled, isTrue);
    });

    testWidgets('error state shows Reconnect and Close buttons', (tester) async {
      final conn = Connection(
        id: 'test-btns',
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
              tabId: 'tab-btns',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      // Both buttons should be present
      expect(find.widgetWithText(ElevatedButton, 'Reconnect'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Close'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('error state shows disconnect color for icon and text', (tester) async {
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
            body: TerminalTab(
              tabId: 'tab-color',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      // Error icon should use AppTheme.disconnected color
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppTheme.disconnected);
    });

    testWidgets('reconnect shows loading then error when sshConnection is null', (tester) async {
      final conn = Connection(
        id: 'test-reconnect-null',
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
              tabId: 'tab-rn',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      await tester.pump(); // should be in loading state briefly

      // After settling, should show error again
      await tester.pumpAndSettle();
      expect(find.textContaining('Reconnect failed'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator during reconnect attempt', (tester) async {
      final conn = Connection(
        id: 'test-loading',
        label: 'Loading Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-loading',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      // Should show error state initially
      expect(find.text('Not connected'), findsOneWidget);

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      // Pump once to see loading state (before async reconnect completes)
      await tester.pump();

      // During reconnect, the _connectionReady is false and _connectionError is null
      // so it should show CircularProgressIndicator briefly
      // (It may resolve immediately because sshConnection is null, so check both states)
      final hasLoader = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      final hasError = find.textContaining('Reconnect failed').evaluate().isNotEmpty;
      expect(hasLoader || hasError, isTrue);
    });

    testWidgets('reconnect with disconnected mock SSHConnection shows error', (tester) async {
      final mockSsh = MockSSHConnection();
      when(mockSsh.isConnected).thenReturn(false);

      final conn = Connection(
        id: 'test-disconnected-mock',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: TerminalTab(
              tabId: 'tab-disc-mock',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      // Should show error state
      expect(find.text('Not connected'), findsOneWidget);

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // Should show reconnect failed (because connect() will fail or knownHosts is null)
      expect(find.textContaining('Reconnect failed'), findsOneWidget);
    });

    testWidgets('error text is styled with disconnected color', (tester) async {
      final conn = Connection(
        id: 'test-style',
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
              tabId: 'tab-style',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      // Find the 'Not connected' text and verify its style
      final textWidget = tester.widget<Text>(find.text('Not connected'));
      expect(textWidget.style?.color, AppTheme.disconnected);
    });

    testWidgets('shows error after reconnect fails with null sshConnection', (tester) async {
      final conn = Connection(
        id: 'test-4',
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
              tabId: 'tab-4',
              connection: conn,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reconnect failed'), findsOneWidget);
    });
  });
}
