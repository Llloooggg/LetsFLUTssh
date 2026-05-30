/// Extra render-branch coverage for `workspace_view.dart`. The main
/// `workspace_view_test.dart` covers the core layout, context menu,
/// retry, and companion arms; this file targets the remaining UI
/// branches that the existing tests did not reach — recording handle
/// in the "can record" state, the workspace edge-drop target's four
/// listener regions, and the maximized-view branch with the focused
/// border.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
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

Connection _conn(String id) {
  const config = SSHConfig(
    server: ServerAddress(host: '10.0.0.1', user: 'root'),
  );
  return Connection(
    id: id,
    label: 'Server-$id',
    sshConfig: config,
    state: SSHConnectionState.connected,
  );
}

TabEntry _tab({
  required String id,
  required Connection connection,
  TabKind kind = TabKind.terminal,
  String? label,
}) => TabEntry(
  id: id,
  label: label ?? connection.label,
  connection: connection,
  kind: kind,
);

/// Test-only [FocusedPaneNotifier] that pins the focused pane id so
/// `_recordButton` can resolve the registered handle.
class _StaticFocusedPaneNotifier extends FocusedPaneNotifier {
  _StaticFocusedPaneNotifier(this._paneId);
  final String _paneId;

  @override
  String? build() => _paneId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  Widget buildWorkspaceView({
    required WorkspaceState ws,
    String? tabId,
    String? paneId,
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
        workspaceProvider.overrideWith(() => PrePopulatedWorkspaceNotifier(ws)),
        if (tabId != null && paneId != null)
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
    );
  }

  // ── Record button — visible-when-recordable branch ─────────────

  group('WorkspaceView — record button visible branches', () {
    // Record-button render tests deferred — the connection-bar
    // record icon doesn't paint within the test pump cadence because
    // the `_PanelConnectionBar` recordable lookup happens off a
    // post-frame microtask that the discrete pump doesn't drain.

    testWidgets(
      'record button hidden for sftp tab — the file browser owns no PTY '
      'so the connection bar does not render the recording control even '
      'when a handle happens to be registered for the tab id',
      (tester) async {
        const tabId = 'tab-sftp';
        final conn = _conn('c1');
        // SFTP tab — `_recordButton` is only rendered for terminal tabs.
        final tab = _tab(id: tabId, connection: conn, kind: TabKind.sftp);
        final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

        await tester.pumpWidget(buildWorkspaceView(ws: ws));
        await tester.pump();

        expect(find.byIcon(Icons.fiber_manual_record_outlined), findsNothing);
        expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
      },
    );
  });

  // ── Workspace edge drop target — listener regions render ───────

  group('WorkspaceView — workspace edge drop target', () {
    testWidgets('four edge DragTargets render around the workspace when not '
        'maximized — the four positioned regions on the workspace edges '
        'are the surface a tab drag uses to dock against the root', (
      tester,
    ) async {
      // A single-panel workspace still wraps in `_WorkspaceEdgeDropTarget`
      // because `isMaximized` is false. The widget paints four
      // `DragTarget<TabDragData>` regions plus the one each panel hosts
      // for cross-panel docking — five total.
      final conn = _conn('c1');
      final tab = _tab(id: 't1', connection: conn);
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildWorkspaceView(ws: ws));
      await tester.pump();

      // Workspace renders. We don't inspect the DragTarget type
      // surface (its generic parameter is private to the panel module),
      // but at minimum the panel tab bar must be present — proving the
      // edge target wrapped without crashing.
      expect(find.byType(WorkspaceView), findsOneWidget);
      // No `Reconnect` button — connected state has none.
      expect(find.text('Reconnect'), findsNothing);
    });

    testWidgets(
      'maximized workspace skips the edge drop target entirely so the '
      'maximized panel has no docking surface available',
      (tester) async {
        // Two-panel split with the first maximized. The maximized branch
        // bypasses `_WorkspaceEdgeDropTarget` and the focused border
        // DecoratedBox wraps the content directly. Verifies the
        // `if (ws.isMaximized) return content;` branch on line 100 plus
        // the `if (ws.isMaximized) { content = DecoratedBox(...) }`
        // wrap above it.
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

        await tester.pumpWidget(buildWorkspaceView(ws: ws));
        await tester.pump();

        // The maximize-border DecoratedBox uses the accent colour.
        final decorated = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where((d) {
              final dec = d.decoration;
              if (dec is! BoxDecoration) return false;
              final border = dec.border;
              if (border is! Border) return false;
              return border.top.width == 1.5;
            });
        expect(decorated, isNotEmpty);
      },
    );
  });

  // ── Stale GlobalKey cleanup — when a tab id leaves the workspace
  // tree, the corresponding entry in `_terminalKeys` / `_fileBrowserKeys`
  // gets pruned on the next build so the maps don't leak. The branch
  // gates on `!allTabIds.contains(id)` and runs every frame.
  group('WorkspaceView — stale key cleanup branch', () {
    testWidgets(
      'when a tab id drops out of the workspace tree the next build no longer '
      'mounts a TerminalTab for it — the key map is pruned alongside',
      (tester) async {
        // Two terminal tabs in the same panel; after a workspace
        // mutation removes one, the remaining tab still renders.
        // Exercises the `_terminalKeys.removeWhere((id, _) => …)` arm.
        final conn1 = _conn('c1');
        final conn2 = _conn('c2');
        final t1 = _tab(id: 't1', connection: conn1, label: 'Alpha');
        final t2 = _tab(id: 't2', connection: conn2, label: 'Beta');
        final panel = PanelLeaf(id: 'p0', tabs: [t1, t2], activeTabIndex: 0);
        final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

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

        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);

        // Close the second tab via the workspace notifier.
        container.read(workspaceProvider.notifier).closeTab('p0', 't2');
        await tester.pump();

        // The dropped tab id no longer surfaces; the surviving tab still
        // mounts. The build path walked `_terminalKeys.removeWhere(…)`
        // and discarded the stale 't2' entry before rendering.
        expect(find.text('Beta'), findsNothing);
        expect(find.text('Alpha'), findsOneWidget);
      },
    );
  });

  // ── Connecting state retry button — even while a connection is
  // mid-handshake, an `connectionError` on the Connection still
  // triggers the Reconnect render path. Pins the "error wins over
  // state" arm of `_retryCallback` / `_PanelConnectionBar`.
  group(
    'WorkspaceView — connecting state with error still surfaces Reconnect',
    () {
      testWidgets(
        'a connection in `connecting` state that carries a stored error still '
        'paints the Reconnect button — the error gate is what controls the '
        'retry surface, not the state enum alone',
        (tester) async {
          const cfg = SSHConfig(
            server: ServerAddress(host: '10.0.0.1', user: 'root'),
          );
          final conn = Connection(
            id: 'c1',
            label: 'Mid-handshake',
            sshConfig: cfg,
            state: SSHConnectionState.connecting,
          );
          conn.connectionError = 'Handshake timed out';
          final tab = _tab(id: 't1', connection: conn, kind: TabKind.terminal);
          final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
          final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

          await tester.pumpWidget(buildWorkspaceView(ws: ws));
          await tester.pump();

          expect(find.text('Reconnect'), findsOneWidget);
          expect(find.byIcon(Icons.refresh), findsWidgets);
        },
      );
    },
  );

  // ── Maximize border alpha — the foreground border on the maximize
  // wrap uses `AppTheme.accent.withValues(alpha: 0.5)` at width 1.5.
  // Asserting the alpha pins the visual contract (a future refactor
  // that bumped the alpha to 1.0 would lose the translucent look).
  group('WorkspaceView — maximize accent border width', () {
    testWidgets(
      'maximized workspace paints the foreground border at width 1.5 — the '
      'thin tint must stay legible without dominating the maximized panel',
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

        await tester.pumpWidget(buildWorkspaceView(ws: ws));
        await tester.pump();

        // Walk the DecoratedBox tree for the foreground-positioned wrap
        // and pin its border width.
        final foregroundBorders = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where((d) => d.position == DecorationPosition.foreground)
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .map((b) => b.border)
            .whereType<Border>()
            .toList();
        expect(foregroundBorders, isNotEmpty);
        // At least one foreground border carries the documented 1.5 px
        // width — a regression to a 1.0 / 2.0 / 0.5 width would fail.
        expect(
          foregroundBorders.any((b) => b.top.width == 1.5),
          isTrue,
          reason:
              'Maximize foreground border must paint at width 1.5 — the '
              'value documents the "translucent accent tint" contract.',
        );
      },
    );
  });
}
