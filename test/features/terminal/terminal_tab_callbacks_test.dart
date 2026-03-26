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

/// Builds a Connection with mocked SSH that will successfully "connect"
/// when TerminalPane calls openShell.
Connection _makeConnected(MockSSHConnection mockSsh, MockSSHSession mockSession, String id) {
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final stderrCtrl = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<void>();

  when(mockSsh.isConnected).thenReturn(true);
  when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
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

void main() {
  group('TerminalTab — _splitPane (lines 59-72)', () {
    testWidgets('split vertical creates a second pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'split-v');

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

      // Should have one TerminalPane initially
      expect(find.byType(TerminalPane), findsOneWidget);

      // Get the TerminalPane widget and invoke its onSplitVertical callback
      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onSplitVertical, isNotNull);
      pane.onSplitVertical!();
      await tester.pumpAndSettle();

      // Now should have two TerminalPane widgets (split happened)
      expect(find.byType(TerminalPane), findsNWidgets(2));
    });

    testWidgets('split horizontal creates a second pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'split-h');

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

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onSplitHorizontal, isNotNull);
      pane.onSplitHorizontal!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));
    });
  });

  group('TerminalTab — _closePane (lines 74-85)', () {
    testWidgets('close pane reduces two panes to one', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'close-p');

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

      // Split first to get two panes
      final pane1 = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      expect(find.byType(TerminalPane), findsNWidgets(2));

      // Now close one pane — find a pane with onClose != null
      final panes = tester.widgetList<TerminalPane>(find.byType(TerminalPane)).toList();
      final closable = panes.firstWhere((p) => p.onClose != null);
      closable.onClose!();
      await tester.pumpAndSettle();

      // Should be back to one pane
      expect(find.byType(TerminalPane), findsOneWidget);
    });

    testWidgets('close pane on root leaf does nothing', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'close-root');

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

      // Single pane should have onClose == null (can't close the only pane)
      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onClose, isNull);
    });
  });

  group('TerminalTab — _onTreeChanged (lines 87-88)', () {
    testWidgets('divider drag triggers onTreeChanged and updates root', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'tree-change');

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

      // Split to create a branch node with a divider
      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitVertical!();
      await tester.pumpAndSettle();

      // Find the divider (MouseRegion with resizeColumn cursor)
      final divider = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(divider, findsOneWidget);

      // Drag the divider to trigger onTreeChanged → _onTreeChanged
      await tester.drag(divider, const Offset(50, 0));
      await tester.pumpAndSettle();

      // Tree should still have two panes (root was updated with new ratio)
      expect(find.byType(TerminalPane), findsNWidgets(2));
    });
  });

  group('TerminalTab — onPaneFocused (line 142)', () {
    testWidgets('tapping a non-focused pane changes focus', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'focus-tap');

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

      // Split to get two panes
      final pane1 = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane1.onSplitVertical!();
      await tester.pumpAndSettle();

      // Find the two panes
      final panes = tester.widgetList<TerminalPane>(find.byType(TerminalPane)).toList();
      expect(panes.length, 2);

      // One should be focused, one not
      final unfocused = panes.firstWhere((p) => !p.isFocused);
      expect(unfocused.onFocused, isNotNull);

      // Invoke onFocused callback to trigger line 142
      unfocused.onFocused!();
      await tester.pumpAndSettle();

      // After focus change, the previously unfocused pane should now be focused
      final panesAfter = tester.widgetList<TerminalPane>(find.byType(TerminalPane)).toList();
      // Exactly one should be focused
      final focusedCount = panesAfter.where((p) => p.isFocused).length;
      expect(focusedCount, 1);
    });
  });

  group('TerminalTab — reconnect via factory success (lines 108-109 equivalent)', () {
    testWidgets('successful reconnect resets tree and shows TilingView', (tester) async {
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
                  // Simulate reconnect: set up mock SSH
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
        ),
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();

      // After reconnect, should render TilingView with TerminalPane
      expect(find.text('Not connected'), findsNothing);
      expect(find.byType(TilingView), findsOneWidget);
    });
  });
}
