import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clipped_row.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../../widgets/hover_region.dart';
import '../file_browser/file_browser_tab.dart';
import '../tabs/tab_model.dart';
import '../tabs/welcome_screen.dart';
import '../terminal/terminal_tab.dart';
import 'drop_zone_overlay.dart';
import 'panel_tab_bar.dart';
import 'workspace_controller.dart';
import 'workspace_node.dart';

/// Recursively renders the [WorkspaceNode] tree as tiled panels,
/// each with its own tab bar and content.
class WorkspaceView extends ConsumerStatefulWidget {
  final CrossMarqueeController? crossMarquee;

  /// Called when any workspace panel receives a pointer down.
  /// Used to clear sidebar selection.
  final VoidCallback? onActivated;

  /// Reverse cross-marquee: file pane → session panel.
  final CrossMarqueeController? reverseCrossMarquee;

  /// Notifier incremented when the sidebar is activated — file browser
  /// tabs listen and clear their selection.
  final ValueNotifier<int>? sidebarActivated;

  const WorkspaceView({
    super.key,
    this.crossMarquee,
    this.reverseCrossMarquee,
    this.onActivated,
    this.sidebarActivated,
  });

  @override
  ConsumerState<WorkspaceView> createState() => WorkspaceViewState();
}

class WorkspaceViewState extends ConsumerState<WorkspaceView> {
  final Map<String, GlobalKey<TerminalTabState>> _terminalKeys = {};
  final Map<String, GlobalKey> _fileBrowserKeys = {};

  GlobalKey<TerminalTabState> _keyForTab(String tabId) =>
      _terminalKeys.putIfAbsent(tabId, () => GlobalKey<TerminalTabState>());

  GlobalKey _keyForFileBrowser(String tabId) =>
      _fileBrowserKeys.putIfAbsent(tabId, () => GlobalKey());

  /// Returns the [TerminalTabState] for the given tab id (if it exists).
  TerminalTabState? terminalStateFor(String tabId) =>
      _terminalKeys[tabId]?.currentState;

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceProvider);
    // Watch connection state changes so status dots update.
    ref.watch(connectionsProvider);

    // Clean up stale keys.
    final allTabIds = collectAllTabs(ws.root).map((t) => t.id).toSet();
    _terminalKeys.removeWhere((id, _) => !allTabIds.contains(id));
    _fileBrowserKeys.removeWhere((id, _) => !allTabIds.contains(id));

    if (!ws.hasTabs) return const WelcomeScreen();

    // When a panel is maximized, render only that panel full-screen.
    // The workspace tree is preserved — only rendering changes.
    final Widget content;
    if (ws.isMaximized) {
      final panel = findPanel(ws.root, ws.maximizedPanelId!);
      if (panel != null) {
        content = DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: _buildPanel(panel, ws.focusedPanelId),
        );
      } else {
        content = _buildNode(ws.root, ws.focusedPanelId);
      }
    } else {
      content = _buildNode(ws.root, ws.focusedPanelId);
    }

    // When maximized, disable edge drop targets (splits don't apply).
    if (ws.isMaximized) return content;

    // Single workspace-level edge drop target: dragging a tab to the very
    // edge of the workspace area docks it beside ALL existing panels.
    return _WorkspaceEdgeDropTarget(
      onEdgeDrop: (data, zone) => _handleRootEdgeDrop(data, zone),
      child: content,
    );
  }

  Widget _buildNode(WorkspaceNode node, String focusedPanelId) {
    return switch (node) {
      PanelLeaf() => _buildPanel(node, focusedPanelId),
      WorkspaceBranch() => _buildBranch(node, focusedPanelId),
    };
  }

  // ---------------------------------------------------------------------------
  // Branch rendering
  // ---------------------------------------------------------------------------

  Widget _buildBranch(WorkspaceBranch node, String focusedPanelId) {
    final isHorizontal = node.direction == Axis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSize = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        return _buildSplitLayout(node, isHorizontal, totalSize, focusedPanelId);
      },
    );
  }

  Widget _buildSplitLayout(
    WorkspaceBranch node,
    bool isHorizontal,
    double totalSize,
    String focusedPanelId,
  ) {
    final firstSize = totalSize * node.ratio;
    final secondSize = totalSize * (1 - node.ratio);

    final firstChild = SizedBox(
      width: isHorizontal ? firstSize : null,
      height: isHorizontal ? null : firstSize,
      child: _buildNode(node.first, focusedPanelId),
    );
    final secondChild = SizedBox(
      width: isHorizontal ? secondSize : null,
      height: isHorizontal ? null : secondSize,
      child: _buildNode(node.second, focusedPanelId),
    );

    final layout = ClipRect(
      child: isHorizontal
          ? Row(children: [firstChild, secondChild])
          : Column(children: [firstChild, secondChild]),
    );

    return _WorkspaceDividerLayout(
      node: node,
      isHorizontal: isHorizontal,
      firstSize: firstSize,
      layout: layout,
      onRatioChanged: (ratio) {
        ref.read(workspaceProvider.notifier).updateRatio(node.id, ratio);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Panel rendering
  // ---------------------------------------------------------------------------

  Widget _buildPanel(PanelLeaf panel, String focusedPanelId) {
    final isFocused = panel.id == focusedPanelId;
    final notifier = ref.read(workspaceProvider.notifier);

    final content = ClipRect(
      child: Listener(
        onPointerDown: widget.onActivated != null
            ? (_) => widget.onActivated!()
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => notifier.setFocusedPanel(panel.id),
          child: Column(
            children: [
              // Tab bar.
              Container(
                height: AppTheme.barHeightSm,
                color: AppTheme.bg1,
                child: PanelTabBar(
                  panelId: panel.id,
                  tabs: panel.tabs,
                  activeIndex: panel.activeTabIndex,
                  isFocusedPanel: isFocused,
                  onSelect: (idx) => notifier.selectTab(panel.id, idx),
                  onClose: (tabId) => notifier.closeTab(panel.id, tabId),
                  onReorder: (oldIdx, newIdx) =>
                      notifier.reorderTabs(panel.id, oldIdx, newIdx),
                  onAcceptCrossPanel: (data, idx) {
                    notifier.moveTab(
                      data.sourcePanelId,
                      data.tab.id,
                      panel.id,
                      index: idx,
                    );
                  },
                  onContextMenu: (tabId, index, offset) =>
                      _showTabContextMenu(context, panel, tabId, index, offset),
                ),
              ),
              // Connection bar.
              if (panel.activeTab != null)
                _PanelConnectionBar(
                  activeTab: panel.activeTab!,
                  panelId: panel.id,
                  onRetry: _retryCallback(panel),
                ),
              // Tab content.
              Expanded(
                child: panel.tabs.isEmpty
                    ? const SizedBox.shrink()
                    : IndexedStack(
                        index: panel.activeTabIndex,
                        children: panel.tabs.map((tab) {
                          return switch (tab.kind) {
                            TabKind.terminal => TerminalTab(
                              key: _keyForTab(tab.id),
                              tabId: tab.id,
                              connection: tab.connection,
                            ),
                            TabKind.sftp => FileBrowserTab(
                              key: _keyForFileBrowser(tab.id),
                              connection: tab.connection,
                              crossMarquee: widget.crossMarquee,
                              reverseCrossMarquee: widget.reverseCrossMarquee,
                              sidebarActivated: widget.sidebarActivated,
                            ),
                          };
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    // Wrap with drop zone overlay for cross-panel docking.
    return PanelDropTarget(
      panelId: panel.id,
      onDrop: (data, zone) => _handleDrop(data, panel.id, zone),
      child: content,
    );
  }

  void _handleDrop(TabDragData data, String targetPanelId, DropZone zone) {
    if (zone == DropZone.center) return; // Inert — tab bar handles insertion.
    final notifier = ref.read(workspaceProvider.notifier);
    final axis = zone == DropZone.left || zone == DropZone.right
        ? Axis.horizontal
        : Axis.vertical;
    final insertBefore = zone == DropZone.left || zone == DropZone.top;
    notifier.splitPanel(
      targetPanelId,
      axis,
      data.tab,
      insertBefore: insertBefore,
    );
    if (data.sourcePanelId != targetPanelId) {
      notifier.closeTab(data.sourcePanelId, data.tab.id);
    }
  }

  /// Handles drops on the outermost workspace edges — splits the entire root.
  void _handleRootEdgeDrop(TabDragData data, DropZone zone) {
    final notifier = ref.read(workspaceProvider.notifier);
    final rootId = ref.read(workspaceProvider).root.id;
    final direction = zone == DropZone.left || zone == DropZone.right
        ? Axis.horizontal
        : Axis.vertical;
    final insertBefore = zone == DropZone.left || zone == DropZone.top;

    notifier.splitAroundNode(
      rootId,
      direction,
      data.tab,
      insertBefore: insertBefore,
    );
    // Remove the tab from its source panel if still present.
    final sourcePanel = findPanel(
      ref.read(workspaceProvider).root,
      data.sourcePanelId,
    );
    if (sourcePanel != null &&
        sourcePanel.tabs.any((t) => t.id == data.tab.id)) {
      notifier.closeTab(data.sourcePanelId, data.tab.id);
    }
  }

  VoidCallback? _retryCallback(PanelLeaf panel) {
    final tab = panel.activeTab;
    if (tab == null) return null;
    if (tab.kind == TabKind.terminal) {
      final state = _terminalKeys[tab.id]?.currentState;
      if (state == null) return null;
      return () => state.reconnect();
    }
    // SFTP tab — reconnect SSH via ConnectionManager, then close + re-open
    // the SFTP tab so FileBrowserTab re-runs _initSftp on the fresh connection.
    return () {
      final manager = ref.read(connectionManagerProvider);
      manager.reconnect(tab.connection.id);
      final notifier = ref.read(workspaceProvider.notifier);
      notifier.closeTab(panel.id, tab.id);
      notifier.addSftpTab(tab.connection, panelId: panel.id);
    };
  }

  void _showTabContextMenu(
    BuildContext context,
    PanelLeaf panel,
    String tabId,
    int index,
    Offset position,
  ) {
    final notifier = ref.read(workspaceProvider.notifier);
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: S.of(context).close,
          icon: Icons.close,
          onTap: () => notifier.closeTab(panel.id, tabId),
        ),
        if (panel.tabs.length > 1)
          ContextMenuItem(
            label: S.of(context).closeOthers,
            icon: Icons.tab_unselected,
            onTap: () => notifier.closeOthers(panel.id, tabId),
          ),
        if (index > 0)
          ContextMenuItem(
            label: S.of(context).closeTabsToTheLeft,
            icon: Icons.first_page,
            onTap: () => notifier.closeToTheLeft(panel.id, index),
          ),
        if (index < panel.tabs.length - 1)
          ContextMenuItem(
            label: S.of(context).closeTabsToTheRight,
            icon: Icons.last_page,
            onTap: () => notifier.closeToTheRight(panel.id, index),
          ),
        if (panel.tabs.length > 1) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: S.of(context).closeAll,
            icon: Icons.close_fullscreen,
            color: AppTheme.red,
            onTap: () => notifier.closeAll(panel.id),
          ),
        ],
        // Maximize / restore toggle — only when multiple panels exist.
        if (ref.read(workspaceProvider).root is WorkspaceBranch ||
            ref.read(workspaceProvider).isMaximized) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: ref.read(workspaceProvider).maximizedPanelId == panel.id
                ? S.of(context).restore
                : S.of(context).maximize,
            icon: ref.read(workspaceProvider).maximizedPanelId == panel.id
                ? Icons.close_fullscreen
                : Icons.open_in_full,
            onTap: () => notifier.toggleMaximizePanel(panel.id),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-panel connection bar
// ---------------------------------------------------------------------------

class _PanelConnectionBar extends ConsumerWidget {
  final TabEntry activeTab;
  final String panelId;
  final VoidCallback? onRetry;

  const _PanelConnectionBar({
    required this.activeTab,
    required this.panelId,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = activeTab.connection;
    final cfg = conn.sshConfig;
    final isTerminal = activeTab.kind == TabKind.terminal;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dimColor = scheme.onSurface.withValues(alpha: 0.6);
    final faintColor = scheme.onSurface.withValues(alpha: 0.45);

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.surfaceContainerHigh,
      child: ClippedRow(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: conn.isConnected ? AppTheme.green : faintColor,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: conn.isConnected
                        ? S.of(context).connected
                        : S.of(context).disconnected,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppFonts.xs,
                      color: dimColor,
                    ),
                  ),
                  TextSpan(
                    text: ' · ',
                    style: TextStyle(fontSize: AppFonts.xs, color: faintColor),
                  ),
                  TextSpan(
                    text: '${cfg.user}@${cfg.host}:${cfg.effectivePort}',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: AppFonts.xs,
                      color: dimColor,
                    ),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!conn.isConnected &&
              conn.connectionError != null &&
              onRetry != null) ...[
            _retryButton(context, scheme),
            const SizedBox(width: 4),
          ],
          _companionButton(context, isTerminal, ref, scheme),
          _maximizeButton(context, ref, scheme),
        ],
      ),
    );
  }

  Widget _maximizeButton(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final ws = ref.watch(workspaceProvider);
    // Only show when multiple panels exist.
    if (ws.root is! WorkspaceBranch && !ws.isMaximized) {
      return const SizedBox.shrink();
    }
    final isMaximized = ws.maximizedPanelId == panelId;
    final s = S.of(context);
    final label = isMaximized ? s.restore : s.maximize;
    final icon = isMaximized ? Icons.close_fullscreen : Icons.open_in_full;
    final btnColor = isMaximized
        ? AppTheme.accent
        : scheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: label,
        child: HoverRegion(
          onTap: () {
            ref.read(workspaceProvider.notifier).toggleMaximizePanel(panelId);
          },
          builder: (hovered) => Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: btnColor.withValues(
                alpha: isMaximized
                    ? (hovered ? 0x30 / 255.0 : 0x18 / 255.0)
                    : (hovered ? 0x20 / 255.0 : 0x00 / 255.0),
              ),
              borderRadius: AppTheme.radiusSm,
            ),
            child: Icon(icon, size: 11, color: btnColor),
          ),
        ),
      ),
    );
  }

  Widget _companionButton(
    BuildContext context,
    bool isTerminal,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final s = S.of(context);
    final btnColor = isTerminal ? AppTheme.yellow : scheme.primary;
    final label = isTerminal ? s.files : s.terminal;
    final icon = isTerminal ? Icons.folder_open : Icons.terminal;
    return Tooltip(
      message: label,
      child: HoverRegion(
        onTap: () {
          final notifier = ref.read(workspaceProvider.notifier);
          if (isTerminal) {
            notifier.addSftpTab(activeTab.connection, panelId: panelId);
          } else {
            notifier.addTerminalTab(activeTab.connection, panelId: panelId);
          }
        },
        builder: (hovered) => Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: btnColor.withValues(
              alpha: hovered ? 0x25 / 255.0 : 0x18 / 255.0,
            ),
            border: Border.all(
              color: btnColor.withValues(
                alpha: hovered ? 0x60 / 255.0 : 0x40 / 255.0,
              ),
            ),
            borderRadius: AppTheme.radiusSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: btnColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.xs,
                  fontWeight: FontWeight.w500,
                  color: btnColor,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _retryButton(BuildContext context, ColorScheme scheme) {
    final btnColor = AppTheme.red;
    return Tooltip(
      message: S.of(context).reconnect,
      child: HoverRegion(
        onTap: onRetry!,
        builder: (hovered) => Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: btnColor.withValues(
              alpha: hovered ? 0x25 / 255.0 : 0x18 / 255.0,
            ),
            border: Border.all(
              color: btnColor.withValues(
                alpha: hovered ? 0x60 / 255.0 : 0x40 / 255.0,
              ),
            ),
            borderRadius: AppTheme.radiusSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.refresh, size: 11, color: btnColor),
              const SizedBox(width: 4),
              Text(
                S.of(context).reconnect,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.xs,
                  fontWeight: FontWeight.w500,
                  color: btnColor,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Divider with absolute-position tracking
// ---------------------------------------------------------------------------

/// Renders the split layout with a draggable divider that tracks the mouse
/// via absolute position (not deltas), preventing drift during rebuilds.
class _WorkspaceDividerLayout extends StatefulWidget {
  final WorkspaceBranch node;
  final bool isHorizontal;
  final double firstSize;
  final Widget layout;
  final ValueChanged<double> onRatioChanged;

  const _WorkspaceDividerLayout({
    required this.node,
    required this.isHorizontal,
    required this.firstSize,
    required this.layout,
    required this.onRatioChanged,
  });

  @override
  State<_WorkspaceDividerLayout> createState() =>
      _WorkspaceDividerLayoutState();
}

class _WorkspaceDividerLayoutState extends State<_WorkspaceDividerLayout> {
  final _stackKey = GlobalKey();

  static const _hitSize = 6.0;
  static const _minPanelSize = 120.0;

  void _onPanUpdate(DragUpdateDetails details) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.globalPosition);
    final totalSize = widget.isHorizontal ? box.size.width : box.size.height;
    final pos = widget.isHorizontal ? local.dx : local.dy;
    final newRatio = (pos / totalSize).clamp(
      _minPanelSize / totalSize,
      1.0 - _minPanelSize / totalSize,
    );
    if (newRatio != widget.node.ratio) {
      widget.onRatioChanged(newRatio);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _stackKey,
      children: [
        widget.layout,
        Positioned(
          left: widget.isHorizontal ? widget.firstSize - 3 : 0,
          top: widget.isHorizontal ? 0 : widget.firstSize - 3,
          right: widget.isHorizontal ? null : 0,
          bottom: widget.isHorizontal ? 0 : null,
          child: MouseRegion(
            cursor: widget.isHorizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: _onPanUpdate,
              child: SizedBox(
                width: widget.isHorizontal ? _hitSize : double.infinity,
                height: widget.isHorizontal ? double.infinity : _hitSize,
                child: Center(
                  child: Container(
                    width: widget.isHorizontal ? 1 : double.infinity,
                    height: widget.isHorizontal ? double.infinity : 1,
                    color: AppTheme.border,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace-level edge drop zones
// ---------------------------------------------------------------------------

/// Wraps the entire workspace and adds thin drop zones on all four edges.
///
/// When a tab is dragged to the very edge of the workspace, it splits the
/// root node so the new panel spans the full width/height — regardless of
/// how the workspace is already subdivided.
class _WorkspaceEdgeDropTarget extends StatefulWidget {
  final Widget child;
  final void Function(TabDragData data, DropZone zone) onEdgeDrop;

  const _WorkspaceEdgeDropTarget({
    required this.child,
    required this.onEdgeDrop,
  });

  @override
  State<_WorkspaceEdgeDropTarget> createState() =>
      _WorkspaceEdgeDropTargetState();
}

class _WorkspaceEdgeDropTargetState extends State<_WorkspaceEdgeDropTarget> {
  DropZone? _activeZone;
  final _key = GlobalKey();

  /// Width/height of the edge hit zone in logical pixels.
  static const _edgeSize = 36.0;

  @override
  Widget build(BuildContext context) {
    // This DragTarget sits *above* all panel DragTargets via a Stack overlay.
    // We use Listener on four positioned edge regions to detect the cursor
    // without stealing hits from the panels underneath.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          key: _key,
          children: [
            widget.child,
            // Four edge hit-test regions — only active during a drag.
            ..._buildEdgeListeners(constraints),
            if (_activeZone != null) _buildEdgeOverlay(_activeZone!),
          ],
        );
      },
    );
  }

  /// Offset edge zones below the tab bar so they don't intercept tab drags.
  static const _tabBarOffset = AppTheme.barHeightSm;

  List<Widget> _buildEdgeListeners(BoxConstraints constraints) {
    return [
      // Left edge — starts below tab bar
      Positioned(
        left: 0,
        top: _tabBarOffset,
        bottom: 0,
        child: SizedBox(
          width: _edgeSize,
          child: DragTarget<TabDragData>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (d) {
              setState(() => _activeZone = null);
              widget.onEdgeDrop(d.data, DropZone.left);
            },
            onMove: (_) {
              if (_activeZone != DropZone.left) {
                setState(() => _activeZone = DropZone.left);
              }
            },
            onLeave: (_) => _clearZone(DropZone.left),
            builder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
      // Right edge — starts below tab bar
      Positioned(
        right: 0,
        top: _tabBarOffset,
        bottom: 0,
        child: SizedBox(
          width: _edgeSize,
          child: DragTarget<TabDragData>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (d) {
              setState(() => _activeZone = null);
              widget.onEdgeDrop(d.data, DropZone.right);
            },
            onMove: (_) {
              if (_activeZone != DropZone.right) {
                setState(() => _activeZone = DropZone.right);
              }
            },
            onLeave: (_) => _clearZone(DropZone.right),
            builder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
      // Top edge — starts below tab bar
      Positioned(
        left: _edgeSize,
        right: _edgeSize,
        top: _tabBarOffset,
        child: SizedBox(
          height: _edgeSize,
          child: DragTarget<TabDragData>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (d) {
              setState(() => _activeZone = null);
              widget.onEdgeDrop(d.data, DropZone.top);
            },
            onMove: (_) {
              if (_activeZone != DropZone.top) {
                setState(() => _activeZone = DropZone.top);
              }
            },
            onLeave: (_) => _clearZone(DropZone.top),
            builder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
      // Bottom edge
      Positioned(
        left: _edgeSize,
        right: _edgeSize,
        bottom: 0,
        child: SizedBox(
          height: _edgeSize,
          child: DragTarget<TabDragData>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (d) {
              setState(() => _activeZone = null);
              widget.onEdgeDrop(d.data, DropZone.bottom);
            },
            onMove: (_) {
              if (_activeZone != DropZone.bottom) {
                setState(() => _activeZone = DropZone.bottom);
              }
            },
            onLeave: (_) => _clearZone(DropZone.bottom),
            builder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
    ];
  }

  void _clearZone(DropZone zone) {
    if (_activeZone == zone) {
      setState(() => _activeZone = null);
    }
  }

  Widget _buildEdgeOverlay(DropZone zone) => buildDropZoneOverlay(zone);
}
