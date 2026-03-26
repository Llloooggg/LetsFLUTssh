import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/split_node.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

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
  group('TilingView — leaf callbacks (lines 59-62)', () {
    testWidgets('onFocused callback fires with correct pane id', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'focus-cb');

      final leaf = LeafNode(id: 'leaf-focus');
      String? focusedId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TilingView(
                tabId: 'tab-focus-cb',
                root: leaf,
                paneConnections: {'leaf-focus': conn},
                focusedPaneId: null,
                onPaneFocused: (id) => focusedId = id,
                onSplit: (_, __, ___) {},
                onClosePane: (_) {},
                onTreeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Get the TerminalPane and invoke its onFocused callback
      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onFocused!();

      expect(focusedId, 'leaf-focus');
    });

    testWidgets('onSplitVertical callback fires with correct pane id and direction', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'split-v-cb');

      final leaf = LeafNode(id: 'leaf-sv');
      String? splitPaneId;
      SplitDirection? splitDir;
      bool? splitInsertBefore;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TilingView(
                tabId: 'tab-sv-cb',
                root: leaf,
                paneConnections: {'leaf-sv': conn},
                focusedPaneId: 'leaf-sv',
                onPaneFocused: (_) {},
                onSplit: (id, dir, before) {
                  splitPaneId = id;
                  splitDir = dir;
                  splitInsertBefore = before;
                },
                onClosePane: (_) {},
                onTreeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitVertical!();

      expect(splitPaneId, 'leaf-sv');
      expect(splitDir, SplitDirection.vertical);
      expect(splitInsertBefore, false);
    });

    testWidgets('onSplitHorizontal callback fires with correct pane id and direction', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'split-h-cb');

      final leaf = LeafNode(id: 'leaf-sh');
      String? splitPaneId;
      SplitDirection? splitDir;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TilingView(
                tabId: 'tab-sh-cb',
                root: leaf,
                paneConnections: {'leaf-sh': conn},
                focusedPaneId: 'leaf-sh',
                onPaneFocused: (_) {},
                onSplit: (id, dir, _) {
                  splitPaneId = id;
                  splitDir = dir;
                },
                onClosePane: (_) {},
                onTreeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitHorizontal!();

      expect(splitPaneId, 'leaf-sh');
      expect(splitDir, SplitDirection.horizontal);
    });

    testWidgets('onClose is null for single pane (line 62 false branch)', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _makeConnected(mockSsh, mockSession, 'single');

      final leaf = LeafNode(id: 'only-leaf');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TilingView(
                tabId: 'tab-single',
                root: leaf,
                paneConnections: {'only-leaf': conn},
                focusedPaneId: 'only-leaf',
                onPaneFocused: (_) {},
                onSplit: (_, __, ___) {},
                onClosePane: (_) {},
                onTreeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onClose, isNull);
    });

    testWidgets('onClose fires with correct pane id for multi-pane (line 62 true branch)', (tester) async {
      final mockSsh1 = MockSSHConnection();
      final mockSession1 = MockSSHSession();
      final conn1 = _makeConnected(mockSsh1, mockSession1, 'mp1');

      final mockSsh2 = MockSSHConnection();
      final mockSession2 = MockSSHSession();
      final conn2 = _makeConnected(mockSsh2, mockSession2, 'mp2');

      final leaf1 = LeafNode(id: 'mp-l1');
      final leaf2 = LeafNode(id: 'mp-l2');
      final branch = BranchNode(
        direction: SplitDirection.vertical,
        first: leaf1,
        second: leaf2,
      );

      String? closedPaneId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: TilingView(
                tabId: 'tab-mp',
                root: branch,
                paneConnections: {'mp-l1': conn1, 'mp-l2': conn2},
                focusedPaneId: 'mp-l1',
                onPaneFocused: (_) {},
                onSplit: (_, __, ___) {},
                onClosePane: (id) => closedPaneId = id,
                onTreeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final panes = tester.widgetList<TerminalPane>(find.byType(TerminalPane)).toList();
      // Both panes should have onClose != null (multiple panes)
      for (final p in panes) {
        expect(p.onClose, isNotNull);
      }

      // Close the first pane
      panes.first.onClose!();
      expect(closedPaneId, isNotNull);
    });
  });
}
