import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  const WorkspaceView({super.key, this.crossMarquee});

  @override
  ConsumerState<WorkspaceView> createState() => WorkspaceViewState();
}

class WorkspaceViewState extends ConsumerState<WorkspaceView> {
  final Map<String, GlobalKey<TerminalTabState>> _terminalKeys = {};

  GlobalKey<TerminalTabState> _keyForTab(String tabId) =>
      _terminalKeys.putIfAbsent(tabId, () => GlobalKey<TerminalTabState>());

  /// Returns the [TerminalTabState] for the given tab id (if it exists).
  TerminalTabState? terminalStateFor(String tabId) =>
      _terminalKeys[tabId]?.currentState;

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceProvider);
    // Watch connection state changes so status dots update.
    ref.watch(connectionsProvider);

    // Clean up stale terminal keys.
    final allTabIds = collectAllTabs(ws.root).map((t) => t.id).toSet();
    _terminalKeys.removeWhere((id, _) => !allTabIds.contains(id));

    if (!ws.hasTabs) return const WelcomeScreen();

    return _buildNode(ws.root, ws.focusedPanelId);
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
        final totalSize =
            isHorizontal ? constraints.maxWidth : constraints.maxHeight;
        final content =
            _buildSplitLayout(node, isHorizontal, totalSize, focusedPanelId);

        // Add edge drop zones on the cross-axis edges so that a tab can be
        // docked beside the *entire* branch (not just one child panel).
        // E.g. when the branch splits vertically (top/bottom), we show
        // left and right edge zones spanning the full height.
        return _BranchEdgeDropTarget(
          branchId: node.id,
          direction: node.direction,
          onEdgeDrop: (data, zone) =>
              _handleBranchEdgeDrop(data, node.id, zone),
          child: content,
        );
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

    final layout = isHorizontal
        ? Row(children: [firstChild, secondChild])
        : Column(children: [firstChild, secondChild]);

    return Stack(
      children: [
        layout,
        Positioned(
          left: isHorizontal ? firstSize - 3 : 0,
          top: isHorizontal ? 0 : firstSize - 3,
          right: isHorizontal ? null : 0,
          bottom: isHorizontal ? 0 : null,
          child: _buildDivider(node, isHorizontal, totalSize),
        ),
      ],
    );
  }

  Widget _buildDivider(
    WorkspaceBranch node,
    bool isHorizontal,
    double totalSize,
  ) {
    const hitSize = 6.0;
    const minPanelSize = 120.0;

    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final delta = isHorizontal ? details.delta.dx : details.delta.dy;
          final newRatio = (node.ratio + delta / totalSize).clamp(
            minPanelSize / totalSize,
            1.0 - minPanelSize / totalSize,
          );
          if (newRatio != node.ratio) {
            ref.read(workspaceProvider.notifier).updateRatio(node.id, newRatio);
          }
        },
        child: SizedBox(
          width: isHorizontal ? hitSize : double.infinity,
          height: isHorizontal ? double.infinity : hitSize,
          child: Center(
            child: Container(
              width: isHorizontal ? 1 : double.infinity,
              height: isHorizontal ? double.infinity : 1,
              color: AppTheme.border,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Panel rendering
  // ---------------------------------------------------------------------------

  Widget _buildPanel(PanelLeaf panel, String focusedPanelId) {
    final isFocused = panel.id == focusedPanelId;
    final notifier = ref.read(workspaceProvider.notifier);

    final content = GestureDetector(
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
                            key: ValueKey(tab.id),
                            connection: tab.connection,
                            crossMarquee: widget.crossMarquee,
                          ),
                      };
                    }).toList(),
                  ),
          ),
        ],
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
    final notifier = ref.read(workspaceProvider.notifier);
    switch (zone) {
      case DropZone.center:
        if (data.sourcePanelId == targetPanelId) return;
        notifier.moveTab(data.sourcePanelId, data.tab.id, targetPanelId);
      case DropZone.left:
        notifier.splitPanel(
          targetPanelId,
          Axis.horizontal,
          data.tab,
          insertBefore: true,
        );
        if (data.sourcePanelId != targetPanelId) {
          notifier.closeTab(data.sourcePanelId, data.tab.id);
        }
      case DropZone.right:
        notifier.splitPanel(
          targetPanelId,
          Axis.horizontal,
          data.tab,
        );
        if (data.sourcePanelId != targetPanelId) {
          notifier.closeTab(data.sourcePanelId, data.tab.id);
        }
      case DropZone.top:
        notifier.splitPanel(
          targetPanelId,
          Axis.vertical,
          data.tab,
          insertBefore: true,
        );
        if (data.sourcePanelId != targetPanelId) {
          notifier.closeTab(data.sourcePanelId, data.tab.id);
        }
      case DropZone.bottom:
        notifier.splitPanel(
          targetPanelId,
          Axis.vertical,
          data.tab,
        );
        if (data.sourcePanelId != targetPanelId) {
          notifier.closeTab(data.sourcePanelId, data.tab.id);
        }
    }
  }

  void _handleBranchEdgeDrop(
    TabDragData data,
    String branchId,
    DropZone zone,
  ) {
    final notifier = ref.read(workspaceProvider.notifier);
    final direction = zone == DropZone.left || zone == DropZone.right
        ? Axis.horizontal
        : Axis.vertical;
    final insertBefore = zone == DropZone.left || zone == DropZone.top;

    notifier.splitAroundNode(
      branchId,
      direction,
      data.tab,
      insertBefore: insertBefore,
    );
    // Remove the tab from its source panel if it came from a different panel.
    // splitAroundNode doesn't touch the source panel.
    final sourcePanel = findPanel(
      ref.read(workspaceProvider).root,
      data.sourcePanelId,
    );
    if (sourcePanel != null) {
      final stillThere =
          sourcePanel.tabs.any((t) => t.id == data.tab.id);
      if (stillThere) {
        notifier.closeTab(data.sourcePanelId, data.tab.id);
      }
    }
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
          label: 'Close',
          icon: Icons.close,
          onTap: () => notifier.closeTab(panel.id, tabId),
        ),
        if (panel.tabs.length > 1)
          ContextMenuItem(
            label: 'Close Others',
            icon: Icons.tab_unselected,
            onTap: () => notifier.closeOthers(panel.id, tabId),
          ),
        if (index > 0)
          ContextMenuItem(
            label: 'Close Tabs to the Left',
            onTap: () => notifier.closeToTheLeft(panel.id, index),
          ),
        if (index < panel.tabs.length - 1)
          ContextMenuItem(
            label: 'Close Tabs to the Right',
            onTap: () => notifier.closeToTheRight(panel.id, index),
          ),
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

  const _PanelConnectionBar({
    required this.activeTab,
    required this.panelId,
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
              TextSpan(children: [
                TextSpan(
                  text: conn.isConnected ? 'Connected' : 'Disconnected',
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
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conn.isConnected)
            _companionButton(isTerminal, ref, scheme),
        ],
      ),
    );
  }

  Widget _companionButton(
    bool isTerminal,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final btnColor = isTerminal ? AppTheme.yellow : scheme.primary;
    final label = isTerminal ? 'Files' : 'Terminal';
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
}

// ---------------------------------------------------------------------------
// Branch-level edge drop zones
// ---------------------------------------------------------------------------

/// Adds thin drop zones on the cross-axis edges of a [WorkspaceBranch].
///
/// When a branch splits vertically (top/bottom), this adds left and right
/// edge zones spanning the full height. When horizontal (left/right), it adds
/// top and bottom edge zones. This lets users dock a tab beside the *entire*
/// branch rather than only beside one child panel.
class _BranchEdgeDropTarget extends StatefulWidget {
  final String branchId;
  final Axis direction;
  final Widget child;
  final void Function(TabDragData data, DropZone zone) onEdgeDrop;

  const _BranchEdgeDropTarget({
    required this.branchId,
    required this.direction,
    required this.child,
    required this.onEdgeDrop,
  });

  @override
  State<_BranchEdgeDropTarget> createState() => _BranchEdgeDropTargetState();
}

class _BranchEdgeDropTargetState extends State<_BranchEdgeDropTarget> {
  DropZone? _activeZone;
  final _key = GlobalKey();

  /// Width/height of the edge hit zone in logical pixels.
  static const _edgeSize = 32.0;

  DropZone? _zoneFromPosition(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final local = box.globalToLocal(global);
    final size = box.size;

    // Only expose the cross-axis edges.
    if (widget.direction == Axis.vertical) {
      // Branch is top/bottom — show left/right edge zones.
      if (local.dx < _edgeSize) return DropZone.left;
      if (local.dx > size.width - _edgeSize) return DropZone.right;
    } else {
      // Branch is left/right — show top/bottom edge zones.
      if (local.dy < _edgeSize) return DropZone.top;
      if (local.dy > size.height - _edgeSize) return DropZone.bottom;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final zone = _activeZone;
        setState(() => _activeZone = null);
        if (zone != null) {
          widget.onEdgeDrop(d.data, zone);
        }
      },
      onMove: (d) {
        final zone = _zoneFromPosition(d.offset);
        if (zone != _activeZone) {
          setState(() => _activeZone = zone);
        }
      },
      onLeave: (_) {
        if (_activeZone != null) {
          setState(() => _activeZone = null);
        }
      },
      builder: (context, candidates, _) {
        final showOverlay = candidates.isNotEmpty && _activeZone != null;
        return Stack(
          key: _key,
          children: [
            widget.child,
            if (showOverlay) _buildEdgeOverlay(_activeZone!),
          ],
        );
      },
    );
  }

  Widget _buildEdgeOverlay(DropZone zone) {
    final color = AppTheme.accent.withValues(alpha: 0.15);
    final border = Border.all(color: AppTheme.accent, width: 2);

    Alignment alignment;
    double widthFactor;
    double heightFactor;

    switch (zone) {
      case DropZone.left:
        alignment = Alignment.centerLeft;
        widthFactor = 0.5;
        heightFactor = 1.0;
      case DropZone.right:
        alignment = Alignment.centerRight;
        widthFactor = 0.5;
        heightFactor = 1.0;
      case DropZone.top:
        alignment = Alignment.topCenter;
        widthFactor = 1.0;
        heightFactor = 0.5;
      case DropZone.bottom:
        alignment = Alignment.bottomCenter;
        widthFactor = 1.0;
        heightFactor = 0.5;
      case DropZone.center:
        return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            child: Container(
              decoration: BoxDecoration(color: color, border: border),
            ),
          ),
        ),
      ),
    );
  }
}
