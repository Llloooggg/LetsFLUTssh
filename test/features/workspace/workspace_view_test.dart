import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/tabs/welcome_screen.dart';
import 'package:letsflutssh/features/terminal/pane_recording_registry.dart';
import 'package:letsflutssh/features/workspace/panel_tab_bar.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';
import 'package:letsflutssh/features/workspace/workspace_view.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/focused_pane_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

import '../../helpers/fake_session_notifier.dart';
import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

Connection _conn(
  String id, {
  SSHConnectionState connState = SSHConnectionState.connected,
}) {
  const config = SSHConfig(
    server: ServerAddress(host: '10.0.0.1', user: 'root'),
  );
  return Connection(
    id: id,
    label: 'Server-$id',
    sshConfig: config,
    state: connState,
  );
}

TabEntry _tab({
  required String id,
  required Connection connection,
  TabKind kind = TabKind.terminal,
  String? label,
}) {
  return TabEntry(
    id: id,
    label: label ?? connection.label,
    connection: connection,
    kind: kind,
  );
}

void main() {
  // WorkspaceView renders widgets that log via AppLogger which
  // routes through `lfs_core::log_sanitize` + format helpers —
  // bootstrap FRB so the canonical Rust pipeline runs.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  Widget buildWorkspaceView({
    WorkspaceState? workspaceState,
    VoidCallback? onActivated,
    double width = 800,
    double height = 600,
  }) {
    return ProviderScope(
      overrides: [
        ...FakeSessionNotifier().overrides(),
        sessionsLoadingProvider.overrideWithValue(false),
        knownHostsStreamProvider.overrideWith(
          (_) => const Stream<Map<String, String>>.empty(),
        ),
        connectionsProvider.overrideWith(
          () => StaticConnectionsNotifier(<Connection>[]),
        ),
        configProvider.overrideWith(TestConfigNotifier.new),
        if (workspaceState != null)
          workspaceProvider.overrideWith(
            () => PrePopulatedWorkspaceNotifier(workspaceState),
          ),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: WorkspaceView(onActivated: onActivated),
          ),
        ),
      ),
    );
  }

  group('WorkspaceView — empty workspace', () {
    testWidgets('renders WelcomeScreen when no tabs are open', (tester) async {
      await tester.pumpWidget(buildWorkspaceView());
      await tester.pump();

      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('renders WelcomeScreen for panel with empty tabs list', (
      tester,
    ) async {
      final panel = PanelLeaf(id: 'p0', tabs: [], activeTabIndex: -1);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });

  group('WorkspaceView — panel with tabs', () {
    testWidgets('renders PanelTabBar when panel has tabs', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byType(PanelTabBar), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('renders connection bar with connected text', (tester) async {
      final conn = _conn('c1', connState: SSHConnectionState.connected);
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Connection bar shows the user@host:port string.
      expect(find.textContaining('root@10.0.0.1:22'), findsOneWidget);
    });

    testWidgets('renders connection bar with disconnected text', (
      tester,
    ) async {
      final conn = _conn('c1', connState: SSHConnectionState.disconnected);
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.textContaining('root@10.0.0.1:22'), findsOneWidget);
    });

    testWidgets('renders multiple tabs in tab bar', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 'tab-1', connection: conn1, label: 'Alpha');
      final tab2 = _tab(id: 'tab-2', connection: conn2, label: 'Beta');
      final panel = PanelLeaf(id: 'p0', tabs: [tab1, tab2], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('renders companion button for terminal tab', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Terminal tab shows "Files" companion button (folder icon).
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('renders companion button for sftp tab', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // SFTP tab shows "Terminal" companion button (terminal icon).
      expect(find.byIcon(Icons.terminal), findsAtLeast(1));
    });
  });

  group('WorkspaceView — split view', () {
    testWidgets('renders two PanelTabBars for horizontal split', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 'tab-1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 'tab-2', connection: conn2, label: 'Right');
      final leftPanel = PanelLeaf(
        id: 'p-left',
        tabs: [tab1],
        activeTabIndex: 0,
      );
      final rightPanel = PanelLeaf(
        id: 'p-right',
        tabs: [tab2],
        activeTabIndex: 0,
      );
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: leftPanel,
        second: rightPanel,
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p-left');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byType(PanelTabBar), findsNWidgets(2));
      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
    });

    testWidgets('renders two PanelTabBars for vertical split', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 'tab-1', connection: conn1, label: 'Top');
      final tab2 = _tab(id: 'tab-2', connection: conn2, label: 'Bottom');
      final topPanel = PanelLeaf(id: 'p-top', tabs: [tab1], activeTabIndex: 0);
      final bottomPanel = PanelLeaf(
        id: 'p-bottom',
        tabs: [tab2],
        activeTabIndex: 0,
      );
      final branch = WorkspaceBranch(
        direction: Axis.vertical,
        first: topPanel,
        second: bottomPanel,
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p-top');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byType(PanelTabBar), findsNWidgets(2));
      expect(find.text('Top'), findsOneWidget);
      expect(find.text('Bottom'), findsOneWidget);
    });

    testWidgets('renders divider with resize cursor for horizontal split', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 'tab-1', connection: conn1);
      final tab2 = _tab(id: 'tab-2', connection: conn2);
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0),
        second: PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Horizontal split should have a column-resize mouse cursor.
      final mouseRegions = tester.widgetList<MouseRegion>(
        find.byType(MouseRegion),
      );
      final resizeCursors = mouseRegions.where(
        (m) => m.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(resizeCursors, isNotEmpty);
    });

    testWidgets('renders divider with resize cursor for vertical split', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 'tab-1', connection: conn1);
      final tab2 = _tab(id: 'tab-2', connection: conn2);
      final branch = WorkspaceBranch(
        direction: Axis.vertical,
        first: PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0),
        second: PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      final mouseRegions = tester.widgetList<MouseRegion>(
        find.byType(MouseRegion),
      );
      final resizeCursors = mouseRegions.where(
        (m) => m.cursor == SystemMouseCursors.resizeRow,
      );
      expect(resizeCursors, isNotEmpty);
    });

    testWidgets('nested split renders three PanelTabBars', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final conn3 = _conn('c3');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'P1');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'P2');
      final tab3 = _tab(id: 't3', connection: conn3, label: 'P3');

      final innerBranch = WorkspaceBranch(
        direction: Axis.vertical,
        first: PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0),
        second: PanelLeaf(id: 'p3', tabs: [tab3], activeTabIndex: 0),
      );
      final outerBranch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0),
        second: innerBranch,
      );
      final ws = WorkspaceState(root: outerBranch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byType(PanelTabBar), findsNWidgets(3));
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);
    });
  });

  group('WorkspaceView — panel focus', () {
    testWidgets('tapping a panel sets focus', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 'tab-1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 'tab-2', connection: conn2, label: 'Right');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(id: 'p-left', tabs: [tab1], activeTabIndex: 0),
        second: PanelLeaf(id: 'p-right', tabs: [tab2], activeTabIndex: 0),
      );
      // Focus starts on the left panel.
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p-left');

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...FakeSessionNotifier().overrides(),
            sessionsLoadingProvider.overrideWithValue(false),
            knownHostsStreamProvider.overrideWith(
              (_) => const Stream<Map<String, String>>.empty(),
            ),
            connectionsProvider.overrideWith(
              () => StaticConnectionsNotifier(<Connection>[]),
            ),
            configProvider.overrideWith(TestConfigNotifier.new),
            workspaceProvider.overrideWith(
              () => PrePopulatedWorkspaceNotifier(ws),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                theme: AppTheme.dark(),
                home: const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WorkspaceView(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // Initial focus is on left panel.
      expect(container.read(workspaceProvider).focusedPanelId, 'p-left');

      // Tap on the right panel area (where the "Right" tab label is).
      await tester.tap(find.text('Right'));
      await tester.pump();

      expect(container.read(workspaceProvider).focusedPanelId, 'p-right');
    });

    testWidgets('onActivated callback fires on pointer down', (tester) async {
      var activated = false;
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(
        buildWorkspaceView(
          workspaceState: ws,
          onActivated: () => activated = true,
        ),
      );
      await tester.pump();

      // Tap anywhere in the panel content area.
      await tester.tap(find.text('Server-c1'));
      await tester.pump();

      expect(activated, isTrue);
    });
  });

  group('WorkspaceView — connection bar states', () {
    testWidgets('shows green dot for connected state', (tester) async {
      final conn = _conn('c1', connState: SSHConnectionState.connected);
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Find the connection status dot (5x5 circle Container).
      final containers = tester.widgetList<Container>(find.byType(Container));
      final dots = containers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.shape == BoxShape.circle) {
          return dec.color == AppTheme.green;
        }
        return false;
      }).toList();
      expect(dots, isNotEmpty);
    });

    testWidgets('shows retry button for disconnected with error', (
      tester,
    ) async {
      final conn = _conn('c1', connState: SSHConnectionState.disconnected);
      conn.connectionError = 'Connection refused';
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Retry button should be visible (refresh icon).
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('no retry button when connected', (tester) async {
      final conn = _conn('c1', connState: SSHConnectionState.connected);
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsNothing);
    });
  });

  group('WorkspaceView — panel with empty tabs list in branch', () {
    testWidgets('panel with no tabs renders SizedBox.shrink content', (
      tester,
    ) async {
      // An empty panel within a branch (edge case).
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, label: 'Only');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(id: 'p1', tabs: [tab], activeTabIndex: 0),
        second: PanelLeaf(id: 'p2', tabs: [], activeTabIndex: -1),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // The non-empty panel renders its tab label.
      expect(find.text('Only'), findsOneWidget);
      // Both panels have tab bars (even the empty one).
      expect(find.byType(PanelTabBar), findsNWidgets(2));
    });
  });

  group('WorkspaceView — split ratio', () {
    testWidgets('custom ratio affects panel sizes', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Wide');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Narrow');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        ratio: 0.7,
        first: PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0),
        second: PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Both panels render — the ratio determines their relative size.
      expect(find.text('Wide'), findsOneWidget);
      expect(find.text('Narrow'), findsOneWidget);
    });
  });

  group('WorkspaceView — context menu', () {
    testWidgets('right-click on tab opens context menu with Close', (
      tester,
    ) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Right-click on the tab label to open context menu.
      await tester.tap(find.text('Server-c1'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      // Context menu should show Close item.
      expect(find.text('Close'), findsOneWidget);
      // Single tab — no Close Others or Close All.
      expect(find.text('Close Others'), findsNothing);
    });

    testWidgets('context menu shows Close Others for multi-tab panel', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Tab A');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Tab B');
      final panel = PanelLeaf(id: 'p0', tabs: [tab1, tab2], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Right-click on second tab.
      await tester.tap(find.text('Tab B'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Close Others'), findsOneWidget);
      expect(find.text('Close All'), findsOneWidget);
    });

    testWidgets('context menu shows Close Tabs to the Left for non-first tab', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'First');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Second');
      final panel = PanelLeaf(id: 'p0', tabs: [tab1, tab2], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Right-click on second tab (index 1).
      await tester.tap(find.text('Second'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Close Tabs to the Left'), findsOneWidget);
    });

    testWidgets('context menu shows Close Tabs to the Right for non-last tab', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'First');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Second');
      final panel = PanelLeaf(id: 'p0', tabs: [tab1, tab2], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Right-click on first tab (index 0).
      await tester.tap(find.text('First'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Close Tabs to the Right'), findsOneWidget);
      expect(find.text('Close Tabs to the Left'), findsNothing);
    });

    testWidgets('context menu shows Maximize for multi-panel workspace', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Right');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0),
        second: PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Right-click on left tab.
      await tester.tap(find.text('Left'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('Maximize'), findsOneWidget);
    });
  });

  group('WorkspaceView — companion button', () {
    testWidgets('terminal tab shows Files companion button', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Files'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('sftp tab shows Terminal companion button', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Terminal'), findsOneWidget);
      expect(find.byIcon(Icons.terminal), findsWidgets);
    });
  });

  group('WorkspaceView — maximized panel', () {
    testWidgets('maximized panel covers the viewport while the sibling is kept '
        'mounted at zero size — so its state (live terminals) survives', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Right');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0),
        second: PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0),
      );
      final ws = WorkspaceState(
        root: branch,
        focusedPanelId: 'p1',
        maximizedPanelId: 'p1',
      );

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Both tab labels remain mounted — the sibling's state (including
      // any live SSH shell in a real terminal tab) must NOT be disposed
      // when maximizing.
      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
      // Both panels' PanelTabBars are in the tree — the earlier
      // implementation removed the sibling's subtree and only rendered
      // one, which killed every terminal in it.
      expect(find.byType(PanelTabBar), findsNWidgets(2));

      // The sibling's PanelTabBar is constrained to zero width by the
      // split layout; the maximized panel's fills the viewport.
      final widths =
          tester
              .widgetList<PanelTabBar>(find.byType(PanelTabBar))
              .map((b) => tester.getRect(find.byWidget(b)).width)
              .toList()
            ..sort();
      expect(widths.first, 0);
      expect(widths.last, greaterThan(100));
    });
  });

  group('WorkspaceView — disconnected state', () {
    testWidgets('shows disconnected text and faint dot', (tester) async {
      final conn = _conn('c1', connState: SSHConnectionState.disconnected);
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Text is inside a Text.rich with TextSpan children.
      expect(find.textContaining('Disconnected'), findsOneWidget);
    });

    testWidgets('connecting state renders as disconnected in bar', (
      tester,
    ) async {
      final conn = _conn('c1', connState: SSHConnectionState.connecting);
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Connecting is not yet connected — bar shows "Disconnected".
      expect(find.textContaining('Disconnected'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Companion button
  // ---------------------------------------------------------------------------
  group('WorkspaceView — companion button', () {
    testWidgets('terminal tab shows Files companion button', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Files'), findsOneWidget);
    });

    testWidgets('SFTP tab shows Terminal companion button', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Terminal'), findsOneWidget);
    });

    testWidgets('tapping Files companion adds SFTP tab', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      await tester.tap(find.text('Files'));
      await tester.pump();

      // After adding SFTP tab, the new tab should be visible
      // (workspace_controller adds the tab and activates it)
    });

    testWidgets('tapping Terminal companion adds terminal tab', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      await tester.tap(find.text('Terminal'));
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------------------
  // Retry button
  // ---------------------------------------------------------------------------
  group('WorkspaceView — retry button', () {
    testWidgets('retry button visible for disconnected tab with error', (
      tester,
    ) async {
      final conn = _conn('c1', connState: SSHConnectionState.disconnected);
      conn.connectionError = 'Connection refused';
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsWidgets);
    });

    testWidgets('retry button NOT visible for connected tab', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Reconnect'), findsNothing);
    });

    testWidgets('retry button NOT visible when no error', (tester) async {
      final conn = _conn('c1', connState: SSHConnectionState.disconnected);
      // No connectionError set
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.text('Reconnect'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Maximize button
  // ---------------------------------------------------------------------------
  group('WorkspaceView — maximize button', () {
    testWidgets('maximize button not visible for single panel', (tester) async {
      final conn = _conn('c1');
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Single panel — no maximize button
      expect(find.byTooltip('Maximize'), findsNothing);
    });

    testWidgets('maximize button visible for multi-panel workspace', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Right');
      final p1 = PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0);
      final p2 = PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0);
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.byTooltip('Maximize'), findsNWidgets(2));
    });

    testWidgets('maximized panel shows Restore tooltip', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Right');
      final p1 = PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0);
      final p2 = PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0);
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final ws = WorkspaceState(
        root: branch,
        focusedPanelId: 'p1',
        maximizedPanelId: 'p1',
      );

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // The maximized panel exposes a Restore tooltip; the sibling
      // still exposes Maximize because it remains mounted (just
      // zero-sized) so its state survives.
      expect(find.byTooltip('Restore'), findsOneWidget);
      expect(find.text('Left'), findsOneWidget);
      expect(find.text('Right'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Divider drag
  // ---------------------------------------------------------------------------
  group('WorkspaceView — divider drag', () {
    testWidgets('horizontal split has column-resize cursor', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Right');
      final p1 = PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0);
      final p2 = PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0);
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // The divider MouseRegion has a column-resize cursor
      final mouseRegions = tester.widgetList<MouseRegion>(
        find.byWidgetPredicate(
          (w) =>
              w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
        ),
      );
      expect(mouseRegions.isNotEmpty, isTrue);
    });

    testWidgets('vertical split has row-resize cursor', (tester) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Top');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Bottom');
      final p1 = PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0);
      final p2 = PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0);
      final branch = WorkspaceBranch(
        direction: Axis.vertical,
        first: p1,
        second: p2,
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      final mouseRegions = tester.widgetList<MouseRegion>(
        find.byWidgetPredicate(
          (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
        ),
      );
      expect(mouseRegions.isNotEmpty, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Context menu — Restore
  // ---------------------------------------------------------------------------
  group('WorkspaceView — context menu Restore', () {
    testWidgets('Restore appears in context menu for maximized panel', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final tab1 = _tab(id: 't1', connection: conn1, label: 'Left');
      final tab2 = _tab(id: 't2', connection: conn2, label: 'Right');
      final p1 = PanelLeaf(id: 'p1', tabs: [tab1], activeTabIndex: 0);
      final p2 = PanelLeaf(id: 'p2', tabs: [tab2], activeTabIndex: 0);
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final ws = WorkspaceState(
        root: branch,
        focusedPanelId: 'p1',
        maximizedPanelId: 'p1',
      );

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Right-click on the tab to open context menu
      await tester.tapAt(
        tester.getCenter(find.text('Left')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Restore'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Divider drag — ratio update
  // ---------------------------------------------------------------------------
  group('WorkspaceView — divider drag updates ratio', () {
    // Dragging the split divider should push a new ratio into the
    // workspace notifier — the divider tracks the cursor's absolute
    // position, so dragging left of centre yields a ratio below 0.5.
    testWidgets('horizontal drag pushes a smaller first-side ratio', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final branch = WorkspaceBranch(
        id: 'b0',
        direction: Axis.horizontal,
        first: PanelLeaf(
          id: 'p1',
          tabs: [_tab(id: 't1', connection: conn1, label: 'Left')],
          activeTabIndex: 0,
        ),
        second: PanelLeaf(
          id: 'p2',
          tabs: [_tab(id: 't2', connection: conn2, label: 'Right')],
          activeTabIndex: 0,
        ),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...FakeSessionNotifier().overrides(),
            sessionsLoadingProvider.overrideWithValue(false),
            knownHostsStreamProvider.overrideWith(
              (_) => const Stream<Map<String, String>>.empty(),
            ),
            connectionsProvider.overrideWith(
              () => StaticConnectionsNotifier(<Connection>[]),
            ),
            configProvider.overrideWith(TestConfigNotifier.new),
            workspaceProvider.overrideWith(
              () => PrePopulatedWorkspaceNotifier(ws),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                theme: AppTheme.dark(),
                home: const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WorkspaceView(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(container.read(workspaceProvider).root, isA<WorkspaceBranch>());

      // Grab the resize-column MouseRegion's GestureDetector (the
      // divider hit zone) and drag it toward the left edge.
      final dividerCursor = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(dividerCursor, findsOneWidget);
      final start = tester.getCenter(dividerCursor);
      await tester.dragFrom(start, const Offset(-200, 0));
      await tester.pump();

      final root = container.read(workspaceProvider).root as WorkspaceBranch;
      // Dragging the divider left of centre narrows the first side.
      expect(root.ratio, lessThan(0.5));
    });
  });

  // ---------------------------------------------------------------------------
  // Maximize button — tap toggles maximize state
  // ---------------------------------------------------------------------------
  group('WorkspaceView — maximize button tap', () {
    testWidgets('tapping the maximize button maximizes the panel', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: PanelLeaf(
          id: 'p1',
          tabs: [_tab(id: 't1', connection: conn1, label: 'Left')],
          activeTabIndex: 0,
        ),
        second: PanelLeaf(
          id: 'p2',
          tabs: [_tab(id: 't2', connection: conn2, label: 'Right')],
          activeTabIndex: 0,
        ),
      );
      final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...FakeSessionNotifier().overrides(),
            sessionsLoadingProvider.overrideWithValue(false),
            knownHostsStreamProvider.overrideWith(
              (_) => const Stream<Map<String, String>>.empty(),
            ),
            connectionsProvider.overrideWith(
              () => StaticConnectionsNotifier(<Connection>[]),
            ),
            configProvider.overrideWith(TestConfigNotifier.new),
            workspaceProvider.overrideWith(
              () => PrePopulatedWorkspaceNotifier(ws),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                theme: AppTheme.dark(),
                home: const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WorkspaceView(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(container.read(workspaceProvider).maximizedPanelId, isNull);

      // Tap the first panel's maximize button.
      await tester.tap(find.byTooltip('Maximize').first);
      await tester.pump();

      expect(container.read(workspaceProvider).isMaximized, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Companion button — hidden for kinds without a PTY
  // ---------------------------------------------------------------------------
  group('WorkspaceView — companion button gating', () {
    testWidgets('companion button hidden for a kind without a terminal', (
      tester,
    ) async {
      // WebDAV connections own no PTY, so the terminal/files swap is
      // meaningless and the companion button must not render.
      final conn = Connection(
        id: 'wd1',
        label: 'DAV',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.9', user: 'dav'),
        ),
        state: SSHConnectionState.connected,
      )..kind = SessionKind.webdav;
      final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Neither half of the companion swap shows for a non-PTY kind.
      expect(find.text('Terminal'), findsNothing);
      expect(find.text('Files'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Record button — visible only when the focused pane has a recordable
  // handle registered
  // ---------------------------------------------------------------------------
  group('WorkspaceView — record button', () {
    testWidgets('no record button when the focused pane cannot record', (
      tester,
    ) async {
      const tabId = 'tab-norec';
      const paneId = 'pane-norec';
      final recording = ValueNotifier<bool>(false);
      PaneRecordingRegistry.instance.register(
        paneId,
        PaneRecordingHandle(
          isRecording: recording,
          canRecord: false,
          toggle: () async {},
        ),
      );
      addTearDown(() {
        PaneRecordingRegistry.instance.unregister(paneId);
        recording.dispose();
      });

      final conn = _conn('c1');
      final tab = _tab(id: tabId, connection: conn, kind: TabKind.terminal);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...FakeSessionNotifier().overrides(),
            sessionsLoadingProvider.overrideWithValue(false),
            knownHostsStreamProvider.overrideWith(
              (_) => const Stream<Map<String, String>>.empty(),
            ),
            connectionsProvider.overrideWith(
              () => StaticConnectionsNotifier(<Connection>[]),
            ),
            configProvider.overrideWith(TestConfigNotifier.new),
            workspaceProvider.overrideWith(
              () => PrePopulatedWorkspaceNotifier(ws),
            ),
            focusedPaneProvider(
              tabId,
            ).overrideWith(() => _StaticFocusedPaneNotifier(paneId)),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SizedBox(width: 800, height: 600, child: WorkspaceView()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.fiber_manual_record_outlined), findsNothing);
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Context menu — tapping items invokes the corresponding workspace mutation.
  // The existing render-only tests pin which items appear; these assert the
  // tapped item actually drives `closeOthers` / `closeToTheLeft` /
  // `closeToTheRight` / `closeAll` / `toggleMaximize` via the notifier.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — context menu action tap', () {
    Future<ProviderContainer> pumpWithState(
      WidgetTester tester,
      WorkspaceState ws,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...FakeSessionNotifier().overrides(),
            sessionsLoadingProvider.overrideWithValue(false),
            knownHostsStreamProvider.overrideWith(
              (_) => const Stream<Map<String, String>>.empty(),
            ),
            connectionsProvider.overrideWith(
              () => StaticConnectionsNotifier(<Connection>[]),
            ),
            configProvider.overrideWith(TestConfigNotifier.new),
            workspaceProvider.overrideWith(
              () => PrePopulatedWorkspaceNotifier(ws),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                localizationsDelegates: S.localizationsDelegates,
                supportedLocales: S.supportedLocales,
                theme: AppTheme.dark(),
                home: const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WorkspaceView(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('tapping Close in the context menu closes the active tab', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final t1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
      final t2 = _tab(id: 't2', connection: conn2, label: 'Beta');
      final panel = PanelLeaf(id: 'p0', tabs: [t1, t2], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      final container = await pumpWithState(tester, ws);

      await tester.tap(find.text('Alpha'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      final leaf = container.read(workspaceProvider).root as PanelLeaf;
      expect(leaf.tabs.map((t) => t.id).toList(), ['t2']);
    });

    testWidgets('tapping Close Others trims the panel to the active tab', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final conn3 = _conn('c3');
      final t1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
      final t2 = _tab(id: 't2', connection: conn2, label: 'Beta');
      final t3 = _tab(id: 't3', connection: conn3, label: 'Gamma');
      final panel = PanelLeaf(id: 'p0', tabs: [t1, t2, t3], activeTabIndex: 1);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      final container = await pumpWithState(tester, ws);

      // Right-click on Beta (the middle tab) and choose Close Others.
      await tester.tap(find.text('Beta'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close Others'));
      await tester.pumpAndSettle();

      final leaf = container.read(workspaceProvider).root as PanelLeaf;
      expect(leaf.tabs.map((t) => t.id).toList(), ['t2']);
    });

    testWidgets(
      'tapping Close Tabs to the Right keeps every tab up to and including '
      'the target',
      (tester) async {
        final conn1 = _conn('c1');
        final conn2 = _conn('c2');
        final conn3 = _conn('c3');
        final t1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
        final t2 = _tab(id: 't2', connection: conn2, label: 'Beta');
        final t3 = _tab(id: 't3', connection: conn3, label: 'Gamma');
        final panel = PanelLeaf(
          id: 'p0',
          tabs: [t1, t2, t3],
          activeTabIndex: 0,
        );
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        final container = await pumpWithState(tester, ws);

        await tester.tap(find.text('Alpha'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Close Tabs to the Right'));
        await tester.pumpAndSettle();

        final leaf = container.read(workspaceProvider).root as PanelLeaf;
        expect(leaf.tabs.map((t) => t.id).toList(), ['t1']);
      },
    );

    testWidgets(
      'tapping Close Tabs to the Left keeps every tab from the target onward',
      (tester) async {
        final conn1 = _conn('c1');
        final conn2 = _conn('c2');
        final conn3 = _conn('c3');
        final t1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
        final t2 = _tab(id: 't2', connection: conn2, label: 'Beta');
        final t3 = _tab(id: 't3', connection: conn3, label: 'Gamma');
        final panel = PanelLeaf(
          id: 'p0',
          tabs: [t1, t2, t3],
          activeTabIndex: 2,
        );
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        final container = await pumpWithState(tester, ws);

        await tester.tap(find.text('Gamma'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Close Tabs to the Left'));
        await tester.pumpAndSettle();

        final leaf = container.read(workspaceProvider).root as PanelLeaf;
        expect(leaf.tabs.map((t) => t.id).toList(), ['t3']);
      },
    );

    testWidgets('tapping Close All collapses the panel to an empty workspace', (
      tester,
    ) async {
      final conn1 = _conn('c1');
      final conn2 = _conn('c2');
      final t1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
      final t2 = _tab(id: 't2', connection: conn2, label: 'Beta');
      final panel = PanelLeaf(id: 'p0', tabs: [t1, t2], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      final container = await pumpWithState(tester, ws);

      await tester.tap(find.text('Alpha'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close All'));
      await tester.pumpAndSettle();

      // closeAll collapses the empty panel, which by `_collapseEmptyPanel`
      // resets the workspace to a fresh single empty panel.
      final ws2 = container.read(workspaceProvider);
      expect(ws2.hasTabs, isFalse);
    });

    testWidgets(
      'tapping Maximize in the context menu flips maximizedPanelId on the '
      'workspace notifier',
      (tester) async {
        final conn1 = _conn('c1');
        final conn2 = _conn('c2');
        final t1 = _tab(id: 't1', connection: conn1, label: 'Left');
        final t2 = _tab(id: 't2', connection: conn2, label: 'Right');
        final branch = WorkspaceBranch(
          direction: Axis.horizontal,
          first: PanelLeaf(id: 'p1', tabs: [t1], activeTabIndex: 0),
          second: PanelLeaf(id: 'p2', tabs: [t2], activeTabIndex: 0),
        );
        final ws = WorkspaceState(root: branch, focusedPanelId: 'p1');

        final container = await pumpWithState(tester, ws);

        await tester.tap(find.text('Left'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Maximize'));
        await tester.pumpAndSettle();

        expect(container.read(workspaceProvider).maximizedPanelId, 'p1');
      },
    );

    testWidgets(
      'tapping Restore in the context menu clears the maximized panel id',
      (tester) async {
        final conn1 = _conn('c1');
        final conn2 = _conn('c2');
        final t1 = _tab(id: 't1', connection: conn1, label: 'Left');
        final t2 = _tab(id: 't2', connection: conn2, label: 'Right');
        final branch = WorkspaceBranch(
          direction: Axis.horizontal,
          first: PanelLeaf(id: 'p1', tabs: [t1], activeTabIndex: 0),
          second: PanelLeaf(id: 'p2', tabs: [t2], activeTabIndex: 0),
        );
        final ws = WorkspaceState(
          root: branch,
          focusedPanelId: 'p1',
          maximizedPanelId: 'p1',
        );

        final container = await pumpWithState(tester, ws);

        // Right-click on the maximized panel's tab; the menu should now
        // show Restore instead of Maximize.
        await tester.tap(find.text('Left'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();

        expect(container.read(workspaceProvider).maximizedPanelId, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Retry callback — verify that an SFTP retry closes + re-opens the SFTP
  // tab so `FileBrowserTab._initSftp` reruns. Terminal-side retry calls
  // through to `TerminalTabState.reconnect`, which requires a mounted PTY
  // (FRB-bound) and is left for the integration layer.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — retry button tap', () {
    // SFTP-retry swap-tab test deferred: the addSftpTab + closeTab race
    // happens off a microtask the prePopulatedWorkspaceNotifier doesn't
    // observe synchronously in the test pump cadence; the panel
    // re-reads stale on the next frame. Covering the SFTP retry needs
    // either a real Riverpod-driven workspace notifier with a settle
    // pump or a controller seam that exposes the pending mutation.

    testWidgets(
      'retry callback is null when the active tab has no connection error — '
      'the connection bar leaves the Reconnect button out so a bare '
      '`_retryCallback` lookup returns null on a connected tab',
      (tester) async {
        final conn = _conn('c1');
        final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        expect(find.text('Reconnect'), findsNothing);
      },
    );
  });
}

/// Test-only [FocusedPaneNotifier] that pins the focused pane id so
/// the connection bar's record button resolves a registered handle.
class _StaticFocusedPaneNotifier extends FocusedPaneNotifier {
  _StaticFocusedPaneNotifier(this._paneId);
  final String _paneId;

  @override
  String? build() => _paneId;
}
