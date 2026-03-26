import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/terminal_tab.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
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

  group('TerminalTab — reconnectFactory', () {
    testWidgets('reconnect success via reconnectFactory resets to connected state', (tester) async {
      final conn = Connection(
        id: 'rf-ok',
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
              tabId: 'tab-rf-ok',
              connection: conn,
              reconnectFactory: (_) async {
                // Simulate successful reconnect — no-op
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Should show error state initially (no sshConnection)
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);

      // Tap Reconnect
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // After successful reconnect, should show TilingView (connected state)
      // TilingView renders TerminalPane(s) — so no error, no spinner
      expect(find.text('Not connected'), findsNothing);
      expect(find.textContaining('Reconnect failed'), findsNothing);
    });

    testWidgets('reconnect failure via reconnectFactory shows error', (tester) async {
      final conn = Connection(
        id: 'rf-fail',
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
              tabId: 'tab-rf-fail',
              connection: conn,
              reconnectFactory: (_) async {
                throw Exception('Auth failed');
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

      // Should show reconnect error
      expect(find.textContaining('Reconnect failed'), findsOneWidget);
      expect(find.textContaining('Auth failed'), findsOneWidget);
    });

    testWidgets('reconnect shows loading spinner briefly', (tester) async {
      final completer = Completer<void>();
      final conn = Connection(
        id: 'rf-load',
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
              tabId: 'tab-rf-load',
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

      // Should show loading spinner while reconnect is in progress
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Reconnect'), findsNothing);

      // Complete the reconnect
      completer.complete();
      await tester.pumpAndSettle();

      // Should be in connected state now
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Reconnect failed'), findsNothing);
    });

    testWidgets('double reconnect: fail then succeed', (tester) async {
      var callCount = 0;
      final conn = Connection(
        id: 'rf-retry',
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
              tabId: 'tab-rf-retry',
              connection: conn,
              reconnectFactory: (_) async {
                callCount++;
                if (callCount == 1) {
                  throw Exception('First attempt failed');
                }
                // Second attempt succeeds
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // First reconnect — fails
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('First attempt failed'), findsOneWidget);

      // Second reconnect — succeeds
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reconnect failed'), findsNothing);
      expect(callCount, 2);
    });
  });

  group('TerminalTab — tiling split and close', () {
    Connection makeConnected(
        MockSSHConnection mockSsh, MockSSHSession mockSession, String id) {
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      return Connection(
        id: id,
        label: 'Test $id',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );
    }

    testWidgets('split vertical creates a second pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'split-v');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-split-v',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsOneWidget);

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onSplitVertical, isNotNull);
      pane.onSplitVertical!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('split horizontal creates a second pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'split-h');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-split-h',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onSplitHorizontal, isNotNull);
      pane.onSplitHorizontal!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('close pane reduces two panes to one', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'close-p');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-close-p',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane1 =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));

      final panes = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      final closable = panes.firstWhere((p) => p.onClose != null);
      closable.onClose!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsOneWidget);
    });

    testWidgets('close pane on root leaf does nothing', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'close-root');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-close-root',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onClose, isNull);
    });

    testWidgets('divider drag triggers onTreeChanged and updates root',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'tree-change');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-tree-change',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitVertical!();
      await tester.pumpAndSettle();

      final divider = find.byWidgetPredicate(
        (w) =>
            w is MouseRegion &&
            w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(divider, findsOneWidget);

      await tester.drag(divider, const Offset(50, 0));
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('tapping a non-focused pane changes focus', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = makeConnected(mockSsh, mockSession, 'focus-tap');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-focus',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane1 =
          tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      final panes = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      expect(panes.length, 2);

      final unfocused = panes.firstWhere((p) => !p.isFocused);
      expect(unfocused.onFocused, isNotNull);

      unfocused.onFocused!();
      await tester.pumpAndSettle();

      final panesAfter = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      final focusedCount = panesAfter.where((p) => p.isFocused).length;
      expect(focusedCount, 1);
    });

    testWidgets('successful reconnect resets tree and shows TilingView',
        (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();

      final conn = Connection(
        id: 'reconn-success',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-reconn-ok',
                connection: conn,
                reconnectFactory: (c) async {
                  final stdoutCtrl =
                      StreamController<Uint8List>.broadcast();
                  final stderrCtrl =
                      StreamController<Uint8List>.broadcast();
                  final doneCompleter = Completer<void>();

                  when(mockSsh.isConnected).thenReturn(true);
                  when(mockSsh.openShell(any, any))
                      .thenAnswer((_) async => mockSession);
                  when(mockSession.stdout)
                      .thenAnswer((_) => stdoutCtrl.stream);
                  when(mockSession.stderr)
                      .thenAnswer((_) => stderrCtrl.stream);
                  when(mockSession.done)
                      .thenAnswer((_) => doneCompleter.future);

                  c.sshConnection = mockSsh;
                  c.state = SSHConnectionState.connected;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      expect(find.text('Not connected'), findsNothing);
      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TerminalTab — error state details', () {
    testWidgets('Close button with null onDisconnected does nothing',
        (tester) async {
      final conn = Connection(
        id: 'no-cb',
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
              tabId: 'tab-no-cb',
              connection: conn,
              onDisconnected: null,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Close'));
      await tester.pump();

      // No crash - null callback is handled
      expect(find.text('Not connected'), findsOneWidget);
    });

    testWidgets('renders TilingView when connected', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final stdoutCtrl = StreamController<Uint8List>.broadcast();
      final stderrCtrl = StreamController<Uint8List>.broadcast();
      final doneCompleter = Completer<void>();

      when(mockSsh.isConnected).thenReturn(true);
      when(mockSsh.openShell(any, any))
          .thenAnswer((_) async => mockSession);
      when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
      when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
      when(mockSession.done).thenAnswer((_) => doneCompleter.future);

      final conn = Connection(
        id: 'connected',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: mockSsh,
        state: SSHConnectionState.connected,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TerminalTab(
                tabId: 'tab-connected',
                connection: conn,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TilingView), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
    });
  });
}
