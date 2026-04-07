import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/connection/connection.dart';
import '../../theme/app_theme.dart';
import '../../utils/platform.dart' as plat;
import '../../widgets/app_icon_button.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/threshold_draggable.dart';
import '../tabs/tab_model.dart';

/// Data carried during a tab drag operation.
class TabDragData {
  final TabEntry tab;
  final String sourcePanelId;

  const TabDragData({required this.tab, required this.sourcePanelId});
}

/// Per-panel tab bar with drag-to-reorder and cross-panel drag support.
///
/// Unlike the old [AppTabBar] this widget does not read providers directly —
/// all data and callbacks are passed via constructor, making it reusable
/// across multiple panels.
class PanelTabBar extends StatefulWidget {
  final String panelId;
  final List<TabEntry> tabs;
  final int activeIndex;
  final bool isFocusedPanel;
  final ValueChanged<int> onSelect;
  final ValueChanged<String> onClose;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(TabDragData data, int index) onAcceptCrossPanel;
  final void Function(String tabId, int index, Offset position) onContextMenu;

  const PanelTabBar({
    super.key,
    required this.panelId,
    required this.tabs,
    required this.activeIndex,
    required this.isFocusedPanel,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
    required this.onAcceptCrossPanel,
    required this.onContextMenu,
  });

  @override
  State<PanelTabBar> createState() => _PanelTabBarState();
}

class _PanelTabBarState extends State<PanelTabBar> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _scrollController.hasClients) {
      final pos = _scrollController.position;
      _scrollController.jumpTo(
        (pos.pixels + event.scrollDelta.dy).clamp(0, pos.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;

    return LayoutBuilder(
      builder: (context, constraints) {
        const maxTabW = 180.0;
        const minTabW = 80.0;
        final natural = tabs.isEmpty
            ? maxTabW
            : constraints.maxWidth / tabs.length;
        final tabW = natural.clamp(minTabW, maxTabW);

        final tabsWidth = tabW * tabs.length;
        final endZoneW = (constraints.maxWidth - tabsWidth).clamp(
          24.0,
          double.infinity,
        );

        return Listener(
          onPointerSignal: _onPointerSignal,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int index = 0; index < tabs.length; index++)
                  _buildDragTarget(tabs, index, tabW),
                _buildTrailingDropZone(tabs, endZoneW),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrailingDropZone(List<TabEntry> tabs, double width) {
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        if (d.data.sourcePanelId == widget.panelId) {
          final oldIdx = tabs.indexWhere((t) => t.id == d.data.tab.id);
          if (oldIdx >= 0 && oldIdx != tabs.length - 1) {
            widget.onReorder(oldIdx, tabs.length);
          }
        } else {
          widget.onAcceptCrossPanel(d.data, tabs.length);
        }
      },
      builder: (context, candidates, _) => Container(
        width: width,
        height: AppTheme.barHeightSm,
        decoration: candidates.isNotEmpty
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppTheme.accent, width: 2),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildDragTarget(List<TabEntry> tabs, int index, double tabWidth) {
    final tab = tabs[index];
    final isActive = index == widget.activeIndex;

    return DragTarget<TabDragData>(
      key: ValueKey('drop_${tab.id}'),
      onWillAcceptWithDetails: (d) => d.data.tab.id != tab.id,
      onAcceptWithDetails: (d) {
        if (d.data.sourcePanelId == widget.panelId) {
          final oldIdx = tabs.indexWhere((t) => t.id == d.data.tab.id);
          if (oldIdx >= 0 && oldIdx != index) {
            widget.onReorder(oldIdx, index);
          }
        } else {
          widget.onAcceptCrossPanel(d.data, index);
        }
      },
      builder: (context, candidates, rejected) {
        return Container(
          decoration: candidates.isNotEmpty
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: AppTheme.accent, width: 2),
                  ),
                )
              : null,
          child: _PanelTabItem(
            tab: tab,
            isActive: isActive,
            width: tabWidth,
            panelId: widget.panelId,
            onSelect: () => widget.onSelect(index),
            onClose: () => widget.onClose(tab.id),
            onContextMenu: (offset) =>
                widget.onContextMenu(tab.id, index, offset),
          ),
        );
      },
    );
  }
}

class _PanelTabItem extends StatefulWidget {
  final TabEntry tab;
  final bool isActive;
  final double width;
  final String panelId;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(Offset position) onContextMenu;

  const _PanelTabItem({
    required this.tab,
    required this.isActive,
    required this.width,
    required this.panelId,
    required this.onSelect,
    required this.onClose,
    required this.onContextMenu,
  });

  @override
  State<_PanelTabItem> createState() => _PanelTabItemState();
}

class _PanelTabItemState extends State<_PanelTabItem> {
  static final bool _mobile = plat.isMobilePlatform;
  static final double _closeBoxSize = _mobile ? 32 : 20;
  static final double _closeIconSize = _mobile ? 16 : 12;

  Color _dotColor() {
    switch (widget.tab.connection.state) {
      case SSHConnectionState.connected:
        return AppTheme.connectedColor(Theme.of(context).brightness);
      case SSHConnectionState.connecting:
        return AppTheme.connectingColor(Theme.of(context).brightness);
      case SSHConnectionState.disconnected:
        return AppTheme.fgFaint;
    }
  }

  Color _iconColor() {
    if (!widget.isActive) return AppTheme.fgFaint;
    return widget.tab.kind == TabKind.terminal
        ? AppTheme.blue
        : AppTheme.yellow;
  }

  Widget _buildContent(bool showClose) {
    return SizedBox(
      width: widget.width,
      height: AppTheme.barHeightSm,
      child: Stack(
        children: [
          Container(
            height: AppTheme.barHeightSm,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: widget.isActive ? AppTheme.bg2 : AppTheme.bg1,
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor(),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  widget.tab.kind == TabKind.terminal
                      ? Icons.terminal
                      : Icons.folder,
                  size: 12,
                  color: _iconColor(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.tab.label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppFonts.sm,
                      color: widget.isActive ? AppTheme.fg : AppTheme.fgDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: _closeBoxSize,
                  height: _closeBoxSize,
                  child: Opacity(
                    opacity: showClose ? 1.0 : 0.0,
                    child: AppIconButton(
                      icon: Icons.close,
                      onTap: showClose ? widget.onClose : null,
                      size: _closeIconSize,
                      boxSize: _closeBoxSize,
                      hoverColor: AppTheme.red.withValues(alpha: 0.2),
                      borderRadius: AppTheme.radiusMd,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.isActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 2,
                child: ColoredBox(color: AppTheme.accent),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: widget.onSelect,
      onSecondaryTapUp: (d) => widget.onContextMenu(d.globalPosition),
      builder: (hovered) {
        final showClose = hovered || widget.isActive;
        final content = _buildContent(showClose);
        return ThresholdDraggable<TabDragData>(
          data: TabDragData(tab: widget.tab, sourcePanelId: widget.panelId),
          feedback: Material(
            elevation: 4,
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: _TabDragChip(tab: widget.tab)),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: content),
          child: content,
        );
      },
    );
  }
}

/// Drag feedback chip shown while dragging a tab.
class _TabDragChip extends StatelessWidget {
  final TabEntry tab;

  const _TabDragChip({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        border: Border.fromBorderSide(BorderSide(color: AppTheme.accent)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tab.kind == TabKind.terminal ? Icons.terminal : Icons.folder,
            size: 12,
            color: AppTheme.fgDim,
          ),
          const SizedBox(width: 6),
          Text(
            tab.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.sm,
              color: AppTheme.fg,
            ),
          ),
        ],
      ),
    );
  }
}
