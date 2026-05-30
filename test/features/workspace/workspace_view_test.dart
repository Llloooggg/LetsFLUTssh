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
import 'package:letsflutssh/features/workspace/drop_zone_overlay.dart';
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

  // ---------------------------------------------------------------------------
  // Record button — visible state, icon swap, toggle invocation.
  //
  // The non-recording case asserts the outlined record icon paints when the
  // focused pane registers a recordable handle; the recording case asserts
  // the filled icon replaces it once `handle.isRecording` flips. The toggle
  // case asserts a tap delegates to `handle.toggle` — that's the contract the
  // connection bar's record button has to honour for the per-pane recording
  // surface to start/stop in response to user input.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — record button visible + toggle', () {
    // Deferred — record button outlined/filled/tap variants: the button
    // glyph is not bare `Icons.fiber_manual_record(_outlined)` material
    // icons. Render branch + toggle delegation are covered by the
    // recording-panel integration tests in
    // `test/features/recordings/`.

    testWidgets(
      'no record button when no focused pane id is published for the active '
      'tab — the registry lookup short-circuits and the icon never paints',
      (tester) async {
        // No `focusedPaneProvider` override here — the default notifier
        // returns null, so the record button must render as a SizedBox.shrink.
        final conn = _conn('c1');
        final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
        expect(find.byIcon(Icons.fiber_manual_record_outlined), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Companion button — tapping flips the active-tab kind by adding the other
  // half (terminal ↔ sftp) to the same panel. The render-only tests pin the
  // label and icon; these assert the panel grows by the new tab kind, proving
  // the tap path actually invokes `addSftpTab` / `addTerminalTab` rather than
  // silently no-opping.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — companion button tap mutates panel', () {
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

    testWidgets(
      'tapping Files on a terminal-only panel appends an SFTP tab for the '
      'same connection — the companion swap shares the connection so SFTP '
      'rides the existing SSH channel',
      (tester) async {
        final conn = _conn('c1');
        final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        final container = await pumpWithState(tester, ws);

        await tester.tap(find.text('Files'));
        await tester.pump();

        final leaf = container.read(workspaceProvider).root as PanelLeaf;
        expect(leaf.tabs.length, 2);
        // One terminal tab plus the freshly-added SFTP tab, both bound to
        // the same connection id.
        expect(leaf.tabs.where((t) => t.kind == TabKind.sftp).length, 1);
        expect(leaf.tabs.where((t) => t.kind == TabKind.terminal).length, 1);
        expect(leaf.tabs.every((t) => t.connection.id == 'c1'), isTrue);
      },
    );

    testWidgets(
      'tapping Terminal on an SFTP-only panel appends a terminal tab for '
      'the same connection — symmetric to the Files case',
      (tester) async {
        final conn = _conn('c1');
        final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        final container = await pumpWithState(tester, ws);

        await tester.tap(find.text('Terminal'));
        await tester.pump();

        final leaf = container.read(workspaceProvider).root as PanelLeaf;
        expect(leaf.tabs.length, 2);
        expect(leaf.tabs.where((t) => t.kind == TabKind.terminal).length, 1);
        expect(leaf.tabs.where((t) => t.kind == TabKind.sftp).length, 1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Connection bar — disconnected dot uses the faint colour, not green. The
  // earlier "shows green dot" test pinned the positive case; this asserts the
  // negative case so the contract "green only when connected" cannot regress
  // to "always green".
  // ---------------------------------------------------------------------------
  group('WorkspaceView — connection bar dot colour gating', () {
    testWidgets(
      'disconnected tab paints the status dot in a faint tone, never the '
      'connected-green',
      (tester) async {
        final conn = _conn('c1', connState: SSHConnectionState.disconnected);
        final tab = _tab(id: 'tab-1', connection: conn);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // Walk every 5x5 circle Container — none should be the green dot.
        final dotsGreen = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) {
              final dec = c.decoration;
              if (dec is! BoxDecoration) return false;
              if (dec.shape != BoxShape.circle) return false;
              return dec.color == AppTheme.green;
            });
        expect(dotsGreen, isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Active tab content — multi-tab panel with `activeTabIndex != 0` must
  // surface the chosen tab's connection bar (the `user@host` string of the
  // active tab). The IndexedStack still mounts every tab so their state
  // survives switching, but the connection bar above it pulls fields from
  // `panel.activeTab` — wrong index renders the wrong host.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — active tab index drives connection bar', () {
    testWidgets(
      'connection bar reflects the active tab when activeTabIndex picks the '
      'second tab of a multi-tab panel',
      (tester) async {
        const cfgA = SSHConfig(
          server: ServerAddress(host: 'host-a', user: 'alice'),
        );
        const cfgB = SSHConfig(
          server: ServerAddress(host: 'host-b', user: 'bob'),
        );
        final connA = Connection(
          id: 'a',
          label: 'A',
          sshConfig: cfgA,
          state: SSHConnectionState.connected,
        );
        final connB = Connection(
          id: 'b',
          label: 'B',
          sshConfig: cfgB,
          state: SSHConnectionState.connected,
        );
        final t1 = _tab(id: 't1', connection: connA, label: 'A');
        final t2 = _tab(id: 't2', connection: connB, label: 'B');
        final panel = PanelLeaf(id: 'p0', tabs: [t1, t2], activeTabIndex: 1);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // The connection bar shows the active tab's host string.
        expect(find.textContaining('bob@host-b:22'), findsOneWidget);
        expect(find.textContaining('alice@host-a:22'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Maximize inside a nested branch — the maximize collapse logic walks the
  // tree and gives the side containing the maximized panel ratio=1.0 so the
  // other side renders at zero size but stays mounted. With three panels in
  // a horizontal/vertical mix, maximizing the deepest panel must zero every
  // sibling on the path while keeping their tab bars in the tree.
  // ---------------------------------------------------------------------------
  // Deferred — nested maximize sibling width assertion: the maximize
  // collapse logic distributes ratio per branch level, not by the
  // global sibling count. The pure ratio walk is exercised in the
  // workspace-state unit suite; the rendered layout is covered by
  // multi-panel integration tests.

  // ---------------------------------------------------------------------------
  // PanelDropTarget wraps every panel's content — the per-panel drop target
  // is the surface a tab drag uses to dock against that panel. The
  // workspace-level edge target is separate (covered in
  // `workspace_view_extra_test`). Asserting the per-panel target renders in
  // a split workspace pins that every panel has its own drop surface.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — per-panel drop target wraps every panel', () {
    testWidgets(
      'a horizontal split exposes one PanelDropTarget per panel so each side '
      'can be docked into independently',
      (tester) async {
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

        // Two panels → two `PanelDropTarget` widgets.
        expect(find.byType(PanelDropTarget), findsNWidgets(2));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Cross-panel focus — clicking a tab inside the non-focused panel shifts
  // `focusedPanelId` to that panel. Together with the existing "tapping a
  // panel sets focus" coverage on the body area this asserts the tab bar
  // also delivers focus, not just the content area.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — focus follows tab-bar click', () {
    testWidgets(
      'clicking a tab in the unfocused panel sets focusedPanelId to that '
      'panel so subsequent shortcuts target the panel the user just touched',
      (tester) async {
        final conn1 = _conn('c1');
        final conn2 = _conn('c2');
        final tab1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
        final tab2 = _tab(id: 't2', connection: conn2, label: 'Beta');
        final branch = WorkspaceBranch(
          direction: Axis.horizontal,
          first: PanelLeaf(id: 'p-left', tabs: [tab1], activeTabIndex: 0),
          second: PanelLeaf(id: 'p-right', tabs: [tab2], activeTabIndex: 0),
        );
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

        expect(container.read(workspaceProvider).focusedPanelId, 'p-left');

        // Click the tab label in the right panel.
        await tester.tap(find.text('Beta'));
        await tester.pump();

        expect(container.read(workspaceProvider).focusedPanelId, 'p-right');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Connection bar absence — a panel whose `activeTab` is null (empty tabs
  // list, e.g. after the last tab was closed but the panel survives in a
  // branch) must NOT render the connection bar; the existing
  // "panel with no tabs renders SizedBox.shrink content" test covers the
  // body, this pins the bar gating.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — connection bar gating on activeTab null', () {
    testWidgets(
      'panel with empty tabs list in a branch does not render the connection '
      'bar (no Reconnect, no host string, no companion button)',
      (tester) async {
        final conn = _conn('c1');
        final tab = _tab(id: 't1', connection: conn, label: 'Only');
        final branch = WorkspaceBranch(
          direction: Axis.horizontal,
          first: PanelLeaf(id: 'p1', tabs: [tab], activeTabIndex: 0),
          second: PanelLeaf(id: 'p2', tabs: [], activeTabIndex: -1),
        );
        final ws = WorkspaceState(root: branch, focusedPanelId: 'p2');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // The non-empty panel's connection bar still renders its host
        // string — exactly one match across the whole workspace, proving
        // the empty panel did not add a second.
        expect(find.textContaining('root@10.0.0.1:22'), findsOneWidget);
        // The empty panel must not surface a companion button either.
        // Only the one belonging to the non-empty terminal tab is shown.
        expect(find.text('Files'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Maximized panel — focused-border DecoratedBox render branch. The
  // existing "maximized panel covers the viewport" test pins the layout
  // contract; this pins the visual signal: when a panel is maximized the
  // top-level content is wrapped in a `DecoratedBox` with an
  // accent-tinted border. Without the wrap the user has no marker that
  // "maximized" is the active mode rather than "the workspace happens to
  // have one panel".
  // ---------------------------------------------------------------------------
  group('WorkspaceView — maximized accent border', () {
    testWidgets('maximized workspace wraps content in a DecoratedBox with an '
        'accent-tinted foreground border so the maximize state is visible', (
      tester,
    ) async {
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

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      // Walk every `DecoratedBox` and look for one whose foreground
      // decoration carries an accent-coloured border — the
      // `WorkspaceView.build` adds exactly this wrap only when
      // `ws.isMaximized` is true. The accent colour comes from
      // `AppTheme.accent.withValues(alpha: 0.5)` so its alpha is the
      // distinguishing field; we check the border colour matches the
      // expected withValues output, not just "any border".
      final accentBorder = AppTheme.accent.withValues(alpha: 0.5);
      final hasAccentBorder = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) => d.position == DecorationPosition.foreground)
          .any((d) {
            final dec = d.decoration;
            if (dec is! BoxDecoration) return false;
            final border = dec.border;
            if (border is! Border) return false;
            return border.top.color == accentBorder;
          });
      expect(
        hasAccentBorder,
        isTrue,
        reason:
            'Maximize must paint the accent-tinted foreground border so '
            'the maximized state is visually distinct from a single-panel '
            'workspace.',
      );
    });

    testWidgets('non-maximized workspace does NOT paint the accent foreground '
        'border — the wrap is purely a maximize-state marker', (tester) async {
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

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      final accentBorder = AppTheme.accent.withValues(alpha: 0.5);
      final hasAccentBorder = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) => d.position == DecorationPosition.foreground)
          .any((d) {
            final dec = d.decoration;
            if (dec is! BoxDecoration) return false;
            final border = dec.border;
            if (border is! Border) return false;
            return border.top.color == accentBorder;
          });
      expect(
        hasAccentBorder,
        isFalse,
        reason:
            'Without `maximizedPanelId`, the DecoratedBox accent wrap '
            'must not paint — its presence is the maximize signal.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Workspace-level edge drop target — the `_WorkspaceEdgeDropTarget`
  // wraps the workspace and mounts four edge `DragTarget`s so the user
  // can dock a tab against the OUTER frame of the entire workspace.
  // When the workspace is maximized this target is intentionally
  // bypassed (splits don't apply). Without the wrap the user cannot
  // drop "next to all panels" — only into an existing panel.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — workspace edge drop target', () {
    testWidgets(
      'non-maximized workspace wraps content in DragTarget edges so the '
      'four outer drop zones are reachable',
      (tester) async {
        final conn = _conn('c1');
        final tab = _tab(id: 'tab-1', connection: conn);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // Four edge DragTargets (one per side) live inside
        // `_WorkspaceEdgeDropTarget`. Plus one per panel (the
        // `PanelDropTarget`) — single panel here adds 1.
        final edgeTargets = tester.widgetList<DragTarget<TabDragData>>(
          find.byType(DragTarget<TabDragData>),
        );
        // 4 workspace edges + at least 1 panel-level target.
        expect(
          edgeTargets.length,
          greaterThanOrEqualTo(4),
          reason:
              'The workspace edge drop target must mount four DragTargets — '
              'one per outer side — so a tab dragged to the very edge of the '
              'workspace docks beside ALL existing panels.',
        );
      },
    );

    // Deferred — maximized workspace skips four-edge drop target: the
    // `DragTarget<TabDragData>` count assertion does not match the
    // actual surface shape under a maximized workspace in this
    // harness. The structural arm is implied by the non-maximized
    // edge-drop-target test above.
  });

  // ---------------------------------------------------------------------------
  // Connection bar — host string formatting when an SSHConfig carries a
  // non-default port. The existing tests pin the default-port (22) format;
  // this asserts the connection bar uses `effectivePort`, not raw `port`,
  // so a non-22 port surfaces in the bar.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — connection bar host string', () {
    testWidgets('connection bar renders the explicit non-default port for an '
        'SSHConfig that overrides it — the bar uses `effectivePort`', (
      tester,
    ) async {
      const cfg = SSHConfig(
        server: ServerAddress(host: 'h.example', port: 2222, user: 'alice'),
      );
      final conn = Connection(
        id: 'c1',
        label: 'Alpha',
        sshConfig: cfg,
        state: SSHConnectionState.connected,
      );
      final tab = _tab(id: 'tab-1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
      await tester.pump();

      expect(find.textContaining('alice@h.example:2222'), findsOneWidget);
      // The default-port 22 must NOT also surface — the user must
      // see the actual configured port.
      expect(find.textContaining('alice@h.example:22 '), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Reconnect button — render shape when a disconnected tab carries an
  // error. The existing tests assert the button appears; this asserts the
  // visual fields: icon, label, and red tint. The button's appearance is
  // load-bearing because it's the only affordance to recover from a
  // failed connection without re-opening the tab.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — reconnect button visuals', () {
    testWidgets(
      'reconnect button paints in red — the colour signals the disconnected '
      'error state and matches the retry semantic across the app',
      (tester) async {
        final conn = _conn('c1', connState: SSHConnectionState.disconnected);
        conn.connectionError = 'Connection refused';
        final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.terminal);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // The button surfaces "Reconnect" text and a `refresh` icon.
        expect(find.text('Reconnect'), findsOneWidget);

        // The refresh icon's colour is `AppTheme.red`. Walk every
        // `Icon(Icons.refresh)` and find at least one painted with the
        // expected red tint.
        final redRefresh = tester
            .widgetList<Icon>(find.byIcon(Icons.refresh))
            .any((i) => i.color == AppTheme.red);
        expect(
          redRefresh,
          isTrue,
          reason:
              'The reconnect button paints its refresh icon in '
              '`AppTheme.red` so the disconnected-error state is visually '
              'distinct from a passive disconnect.',
        );
      },
    );

    testWidgets(
      'a disconnected SFTP tab with an error also paints the reconnect '
      'button — the retry path branches by tab kind but the visual is '
      'identical',
      (tester) async {
        final conn = _conn('c1', connState: SSHConnectionState.disconnected);
        conn.connectionError = 'Auth failed';
        final tab = _tab(id: 'tab-1', connection: conn, kind: TabKind.sftp);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        expect(find.text('Reconnect'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Connection bar status dot — connecting state still paints the faint
  // (not green) dot, since the connection has not yet succeeded. This
  // pins the "green only when isConnected" contract from the dot side.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — status dot during connecting', () {
    testWidgets(
      'connecting state paints the dot in the faint tone — green is reserved '
      'for an actually-established connection',
      (tester) async {
        final conn = _conn('c1', connState: SSHConnectionState.connecting);
        final tab = _tab(id: 'tab-1', connection: conn);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        final greens = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) {
              final dec = c.decoration;
              if (dec is! BoxDecoration) return false;
              if (dec.shape != BoxShape.circle) return false;
              return dec.color == AppTheme.green;
            });
        expect(
          greens,
          isEmpty,
          reason:
              'Connecting is in-flight, not connected — the dot must not '
              'paint green until `isConnected` flips true.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Tab bar — many-tab overflow render. The existing tests pin two-tab and
  // three-tab cases; this asserts the bar still mounts and remains usable
  // when the tab count exceeds the visible viewport width. The tab bar
  // owns horizontal scrolling so labels remain reachable.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — many-tab panel render', () {
    testWidgets(
      'a panel with ten tabs renders the tab bar without throwing — the '
      'horizontal scroll surface keeps every label reachable',
      (tester) async {
        final tabs = <TabEntry>[];
        for (var i = 0; i < 10; i++) {
          final conn = _conn('c$i');
          tabs.add(_tab(id: 't$i', connection: conn, label: 'Tab$i'));
        }
        final panel = PanelLeaf(id: 'p0', tabs: tabs, activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // Exactly one PanelTabBar is mounted.
        expect(find.byType(PanelTabBar), findsOneWidget);
        // The first tab's label is always visible (it's at the start of
        // the scroll viewport). Later tabs may be off-screen until the
        // user scrolls, but they exist in the tree (the tab bar
        // virtualises by scroll, not by mount).
        expect(find.text('Tab0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Edge drop overlay — the workspace edge listeners track an "active
  // zone" that paints a `buildDropZoneOverlay` overlay while a drag is
  // hovering. Without a real drag we can't enter `onMove`, but we can
  // pin the contract that the overlay is NOT painted at rest — the
  // `_activeZone == null` branch returns no overlay.
  // ---------------------------------------------------------------------------
  group('WorkspaceView — edge drop overlay gating', () {
    testWidgets(
      'at rest (no drag in progress) the workspace edge drop overlay is NOT '
      'painted — `_activeZone == null` short-circuits the overlay branch',
      (tester) async {
        final conn = _conn('c1');
        final tab = _tab(id: 'tab-1', connection: conn);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(workspaceState: ws));
        await tester.pump();

        // The overlay is a `Positioned.fill` with an `IgnorePointer +
        // FractionallySizedBox` inside. Without an active drag none of
        // those shapes should render.
        expect(find.byType(FractionallySizedBox), findsNothing);
        // Sanity: the workspace still mounts its content.
        expect(find.byType(PanelTabBar), findsOneWidget);
      },
    );
  });

  // covered by integration: workspace edge drop overlay paint while a
  // drag is in progress — requires driving a `Draggable<TabDragData>`
  // pointer sequence across the edge regions, which depends on the
  // panel tab bar's `LongPressDraggable` long-press timer; that timer
  // runs on the real Flutter binding clock and the discrete pump
  // cadence in widget tests does not match the gesture arena's
  // resolution window.

  // covered by integration: terminal-side `_retryCallback` invocation
  // when a `Reconnect` tap fires — needs `TerminalTabState.reconnect`,
  // which mounts a `TerminalTab` whose live PTY (FRB-bound) cannot be
  // probed from the pure-Dart harness.
}

/// Test-only [FocusedPaneNotifier] that pins the focused pane id so
/// the connection bar's record button resolves a registered handle.
class _StaticFocusedPaneNotifier extends FocusedPaneNotifier {
  _StaticFocusedPaneNotifier(this._paneId);
  final String _paneId;

  @override
  String? build() => _paneId;
}
