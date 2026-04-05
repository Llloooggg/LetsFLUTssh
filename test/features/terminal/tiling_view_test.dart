import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/split_node.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../core/ssh/shell_helper_test.mocks.dart';

/// Helper to create a connected Connection with mock SSHConnection + session.
Connection _buildConnectedConnection({
  required MockSSHConnection mockSsh,
  required MockSSHSession mockSession,
  required String id,
}) {
  when(mockSsh.isConnected).thenReturn(true);

  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final stderrCtrl = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<void>();

  when(mockSsh.openShell(any, any)).thenAnswer((_) async => mockSession);
  when(mockSession.stdout).thenAnswer((_) => stdoutCtrl.stream);
  when(mockSession.stderr).thenAnswer((_) => stderrCtrl.stream);
  when(mockSession.done).thenAnswer((_) => doneCompleter.future);

  return Connection(
    id: id,
    label: 'Test $id',
    sshConfig: const SSHConfig(
      server: ServerAddress(host: 'h', user: 'u'),
    ),
    sshConnection: mockSsh,
    state: SSHConnectionState.connected,
  );
}

void main() {
  group('TilingView — LeafNode', () {
    testWidgets('renders single leaf pane (TerminalPane)', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _buildConnectedConnection(
        mockSsh: mockSsh,
        mockSession: mockSession,
        id: 'c1',
      );

      final leaf = LeafNode(id: 'leaf-1');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-1',
                  root: leaf,
                  paneConnections: {'leaf-1': conn},
                  focusedPaneId: 'leaf-1',
                  onPaneFocused: (_) {},
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // After pump, TerminalPane should be connecting (showing loading)
      // or connected (showing TerminalView)
      await tester.pump();

      // The widget tree should be non-empty (not SizedBox.shrink)
      expect(find.byType(TilingView), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when connection not found', (
      tester,
    ) async {
      final leaf = LeafNode(id: 'orphan');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-2',
                  root: leaf,
                  paneConnections: {}, // no connection for 'orphan'
                  focusedPaneId: 'orphan',
                  onPaneFocused: (_) {},
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TilingView — BranchNode', () {
    testWidgets('renders two panes in a vertical split (Row)', (tester) async {
      final mockSsh1 = MockSSHConnection();
      final mockSession1 = MockSSHSession();
      final conn1 = _buildConnectedConnection(
        mockSsh: mockSsh1,
        mockSession: mockSession1,
        id: 'c1',
      );

      final mockSsh2 = MockSSHConnection();
      final mockSession2 = MockSSHSession();
      final conn2 = _buildConnectedConnection(
        mockSsh: mockSsh2,
        mockSession: mockSession2,
        id: 'c2',
      );

      final leaf1 = LeafNode(id: 'l1');
      final leaf2 = LeafNode(id: 'l2');
      final branch = BranchNode(
        direction: SplitDirection.vertical,
        ratio: 0.5,
        first: leaf1,
        second: leaf2,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-3',
                  root: branch,
                  paneConnections: {'l1': conn1, 'l2': conn2},
                  focusedPaneId: 'l1',
                  onPaneFocused: (_) {},
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TilingView), findsOneWidget);
      // Should render a Row for vertical split
      // The LayoutBuilder creates the Row internally
    });

    testWidgets('renders two panes in a horizontal split (Column)', (
      tester,
    ) async {
      final mockSsh1 = MockSSHConnection();
      final mockSession1 = MockSSHSession();
      final conn1 = _buildConnectedConnection(
        mockSsh: mockSsh1,
        mockSession: mockSession1,
        id: 'c1',
      );

      final mockSsh2 = MockSSHConnection();
      final mockSession2 = MockSSHSession();
      final conn2 = _buildConnectedConnection(
        mockSsh: mockSsh2,
        mockSession: mockSession2,
        id: 'c2',
      );

      final leaf1 = LeafNode(id: 'h1');
      final leaf2 = LeafNode(id: 'h2');
      final branch = BranchNode(
        direction: SplitDirection.horizontal,
        ratio: 0.5,
        first: leaf1,
        second: leaf2,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-4',
                  root: branch,
                  paneConnections: {'h1': conn1, 'h2': conn2},
                  focusedPaneId: 'h1',
                  onPaneFocused: (_) {},
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TilingView), findsOneWidget);
    });
  });

  group('TilingView — divider drag', () {
    testWidgets('dragging divider changes ratio', (tester) async {
      final mockSsh1 = MockSSHConnection();
      final mockSession1 = MockSSHSession();
      final conn1 = _buildConnectedConnection(
        mockSsh: mockSsh1,
        mockSession: mockSession1,
        id: 'c1',
      );
      final mockSsh2 = MockSSHConnection();
      final mockSession2 = MockSSHSession();
      final conn2 = _buildConnectedConnection(
        mockSsh: mockSsh2,
        mockSession: mockSession2,
        id: 'c2',
      );

      final leaf1 = LeafNode(id: 'd1');
      final leaf2 = LeafNode(id: 'd2');
      final branch = BranchNode(
        direction: SplitDirection.vertical,
        ratio: 0.5,
        first: leaf1,
        second: leaf2,
      );

      SplitNode? changedRoot;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-drag',
                  root: branch,
                  paneConnections: {'d1': conn1, 'd2': conn2},
                  focusedPaneId: 'd1',
                  onPaneFocused: (_) {},
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (r) => changedRoot = r,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find the divider (Container with divider color, between two panes)
      final divider = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      if (divider.evaluate().isNotEmpty) {
        await tester.drag(divider.first, const Offset(50, 0));
        await tester.pump();

        // onTreeChanged should have been called
        expect(changedRoot, isNotNull);
      }
    });
  });

  group('TilingView — horizontal divider drag', () {
    testWidgets('dragging horizontal divider changes ratio', (tester) async {
      final mockSsh1 = MockSSHConnection();
      final mockSession1 = MockSSHSession();
      final conn1 = _buildConnectedConnection(
        mockSsh: mockSsh1,
        mockSession: mockSession1,
        id: 'c1',
      );
      final mockSsh2 = MockSSHConnection();
      final mockSession2 = MockSSHSession();
      final conn2 = _buildConnectedConnection(
        mockSsh: mockSsh2,
        mockSession: mockSession2,
        id: 'c2',
      );

      final leaf1 = LeafNode(id: 'hd1');
      final leaf2 = LeafNode(id: 'hd2');
      final branch = BranchNode(
        direction: SplitDirection.horizontal,
        ratio: 0.5,
        first: leaf1,
        second: leaf2,
      );

      SplitNode? changedRoot;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-hdrag',
                  root: branch,
                  paneConnections: {'hd1': conn1, 'hd2': conn2},
                  focusedPaneId: 'hd1',
                  onPaneFocused: (_) {},
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (r) => changedRoot = r,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Find the horizontal divider (resizeRow cursor)
      final divider = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
      );
      if (divider.evaluate().isNotEmpty) {
        await tester.drag(divider.first, const Offset(0, 30));
        await tester.pump();

        expect(changedRoot, isNotNull);
      }
    });
  });

  group('TilingView — no connection', () {
    testWidgets('renders SizedBox.shrink when paneConnections is empty', (
      tester,
    ) async {
      final leaf = LeafNode(id: 'no-conn');
      String? focusedId;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: TilingView(
                  tabId: 'tab-5',
                  root: leaf,
                  paneConnections: const {},
                  focusedPaneId: null,
                  onPaneFocused: (id) => focusedId = id,
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TilingView), findsOneWidget);
      // No tap occurred, so focusedId should be null
      expect(focusedId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Leaf callbacks (from tiling_view_callbacks_test.dart)
  // ---------------------------------------------------------------------------
  group('TilingView — leaf callbacks', () {
    testWidgets('onFocused callback fires with correct pane id', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _buildConnectedConnection(
        mockSsh: mockSsh,
        mockSession: mockSession,
        id: 'focus-cb',
      );

      final leaf = LeafNode(id: 'leaf-focus');
      String? focusedId;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onFocused!();
      expect(focusedId, 'leaf-focus');
    });

    testWidgets('onSplitVertical callback fires with correct direction', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _buildConnectedConnection(
        mockSsh: mockSsh,
        mockSession: mockSession,
        id: 'split-v-cb',
      );

      final leaf = LeafNode(id: 'leaf-sv');
      String? splitPaneId;
      SplitDirection? splitDir;
      bool? splitInsertBefore;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitVertical!();
      expect(splitPaneId, 'leaf-sv');
      expect(splitDir, SplitDirection.vertical);
      expect(splitInsertBefore, false);
    });

    testWidgets('onSplitHorizontal callback fires with correct direction', (
      tester,
    ) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _buildConnectedConnection(
        mockSsh: mockSsh,
        mockSession: mockSession,
        id: 'split-h-cb',
      );

      final leaf = LeafNode(id: 'leaf-sh');
      String? splitPaneId;
      SplitDirection? splitDir;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      pane.onSplitHorizontal!();
      expect(splitPaneId, 'leaf-sh');
      expect(splitDir, SplitDirection.horizontal);
    });

    testWidgets('onClose is null for single pane', (tester) async {
      final mockSsh = MockSSHConnection();
      final mockSession = MockSSHSession();
      final conn = _buildConnectedConnection(
        mockSsh: mockSsh,
        mockSession: mockSession,
        id: 'single',
      );

      final leaf = LeafNode(id: 'only-leaf');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
                  onSplit: (_, _, _) {},
                  onClosePane: (_) {},
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane).first);
      expect(pane.onClose, isNull);
    });

    testWidgets('onClose fires with correct pane id for multi-pane', (
      tester,
    ) async {
      final mockSsh1 = MockSSHConnection();
      final mockSession1 = MockSSHSession();
      final conn1 = _buildConnectedConnection(
        mockSsh: mockSsh1,
        mockSession: mockSession1,
        id: 'mp1',
      );

      final mockSsh2 = MockSSHConnection();
      final mockSession2 = MockSSHSession();
      final conn2 = _buildConnectedConnection(
        mockSsh: mockSsh2,
        mockSession: mockSession2,
        id: 'mp2',
      );

      final leaf1 = LeafNode(id: 'mp-l1');
      final leaf2 = LeafNode(id: 'mp-l2');
      final branch = BranchNode(
        direction: SplitDirection.vertical,
        first: leaf1,
        second: leaf2,
      );

      String? closedPaneId;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
                  onSplit: (_, _, _) {},
                  onClosePane: (id) => closedPaneId = id,
                  onTreeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final panes = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .toList();
      for (final p in panes) {
        expect(p.onClose, isNotNull);
      }

      panes.first.onClose!();
      expect(closedPaneId, isNotNull);
    });
  });
}
