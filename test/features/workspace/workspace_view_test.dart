import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/config_store.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/tabs/welcome_screen.dart';
import 'package:letsflutssh/features/workspace/panel_tab_bar.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';
import 'package:letsflutssh/features/workspace/workspace_view.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

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
  Widget buildWorkspaceView({
    WorkspaceState? workspaceState,
    VoidCallback? onActivated,
    double width = 800,
    double height = 600,
  }) {
    return ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(SessionStore()),
        sessionProvider.overrideWith(SessionNotifier.new),
            sessionsLoadingProvider.overrideWith(IdleSessionsLoadingNotifier.new),
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
        connectionManagerProvider.overrideWithValue(
          ConnectionManager(knownHosts: KnownHostsManager()),
        ),
        connectionsProvider.overrideWith((ref) => Stream.value(<Connection>[])),
        configStoreProvider.overrideWithValue(ConfigStore()),
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
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            sessionsLoadingProvider.overrideWith(IdleSessionsLoadingNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            connectionsProvider.overrideWith(
              (ref) => Stream.value(<Connection>[]),
            ),
            configStoreProvider.overrideWithValue(ConfigStore()),
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
}
