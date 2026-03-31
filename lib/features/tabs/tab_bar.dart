import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/context_menu.dart';
import 'tab_controller.dart';
import 'tab_model.dart';

/// Custom tab bar with drag-to-reorder.
///
/// Drag any tab to reorder. Click to select, right-click for context menu.
/// Tabs shrink when space is tight and scroll with the mouse wheel when they
/// reach their minimum width.
class AppTabBar extends ConsumerStatefulWidget {
  final VoidCallback onNewSession;

  const AppTabBar({super.key, required this.onNewSession});

  @override
  ConsumerState<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends ConsumerState<AppTabBar> {
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
    final tabState = ref.watch(tabProvider);
    // Watch connection state changes so tab indicators update.
    ref.watch(connectionsProvider);
    final tabs = tabState.tabs;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          if (tabs.isNotEmpty)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const maxTabW = 180.0;
                  const minTabW = 80.0;
                  final natural = constraints.maxWidth / tabs.length;
                  final tabW = natural.clamp(minTabW, maxTabW);

                  return Listener(
                    onPointerSignal: _onPointerSignal,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (int index = 0; index < tabs.length; index++)
                            _buildDragTarget(tabs, index, tabState, tabW),
                          // Drop zone at the end — allows dragging to last position
                          DragTarget<TabEntry>(
                            onWillAcceptWithDetails: (_) => true,
                            onAcceptWithDetails: (d) {
                              final oldIdx =
                                  tabs.indexWhere((t) => t.id == d.data.id);
                              final lastIdx = tabs.length - 1;
                              if (oldIdx >= 0 && oldIdx != lastIdx) {
                                ref
                                    .read(tabProvider.notifier)
                                    .swapTabs(oldIdx, lastIdx);
                              }
                            },
                            builder: (context, candidates, _) => Container(
                              width: 24,
                              height: 32,
                              decoration: candidates.isNotEmpty
                                  ? BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                            color: AppTheme.accent, width: 2),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const Spacer(),
          _PlusButton(onPressed: widget.onNewSession),
        ],
      ),
    );
  }

  Widget _buildDragTarget(
    List<TabEntry> tabs, int index, TabState tabState, double tabWidth,
  ) {
    final tab = tabs[index];
    final isActive = index == tabState.activeIndex;

    return DragTarget<TabEntry>(
      key: ValueKey('drop_${tab.id}'),
      onWillAcceptWithDetails: (d) => d.data.id != tab.id,
      onAcceptWithDetails: (d) {
        final oldIdx = tabs.indexWhere((t) => t.id == d.data.id);
        if (oldIdx >= 0 && oldIdx != index) {
          ref.read(tabProvider.notifier).swapTabs(oldIdx, index);
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
          child: _TabItem(
            tab: tab,
            isActive: isActive,
            width: tabWidth,
            onSelect: () => ref.read(tabProvider.notifier).selectTab(index),
            onClose: () => ref.read(tabProvider.notifier).closeTab(tab.id),
            onContextMenu: (offset) => _showContextMenu(
              context, ref, tab, index, tabState, offset,
            ),
          ),
        );
      },
    );
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    TabEntry tab,
    int index,
    TabState tabState,
    Offset position,
  ) {
    final notifier = ref.read(tabProvider.notifier);
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: 'Close',
          icon: Icons.close,
          onTap: () => notifier.closeTab(tab.id),
        ),
        if (tabState.tabs.length > 1)
          ContextMenuItem(
            label: 'Close Others',
            icon: Icons.tab_unselected,
            onTap: () => notifier.closeOthers(tab.id),
          ),
        if (index > 0)
          ContextMenuItem(
            label: 'Close Tabs to the Left',
            onTap: () => notifier.closeToTheLeft(index),
          ),
        if (index < tabState.tabs.length - 1)
          ContextMenuItem(
            label: 'Close Tabs to the Right',
            onTap: () => notifier.closeToTheRight(index),
          ),
      ],
    );
  }
}

class _TabItem extends StatefulWidget {
  final TabEntry tab;
  final bool isActive;
  final double width;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(Offset position) onContextMenu;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.width,
    required this.onSelect,
    required this.onClose,
    required this.onContextMenu,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hovered = false;

  Color _dotColor() {
    return widget.tab.connection.state == SSHConnectionState.connected
        ? AppTheme.green
        : AppTheme.fgFaint;
  }

  Color _iconColor() {
    if (!widget.isActive) return AppTheme.fgFaint;
    return widget.tab.kind == TabKind.terminal ? AppTheme.blue : AppTheme.yellow;
  }

  @override
  Widget build(BuildContext context) {
    final showClose = _hovered || widget.isActive;

    final tabContent = SizedBox(
      width: widget.width,
      height: 32,
      child: Stack(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: widget.isActive ? AppTheme.bg2 : Colors.transparent,
              border: Border(
                right: BorderSide(color: AppTheme.border),
              ),
            ),
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
                      fontSize: 11,
                      color: widget.isActive ? AppTheme.fg : AppTheme.fgDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Opacity(
                    opacity: showClose ? 1.0 : 0.0,
                    child: _CloseButton(
                      onTap: showClose ? widget.onClose : null,
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
              child: SizedBox(height: 2, child: ColoredBox(color: AppTheme.accent)),
            ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Draggable<TabEntry>(
        data: widget.tab,
        feedback: Material(
          elevation: 4,
          color: Colors.transparent,
          child: Opacity(opacity: 0.85, child: _DragChip(tab: widget.tab)),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tabContent),
        child: GestureDetector(
          onTap: widget.onSelect,
          onSecondaryTapUp: (d) => widget.onContextMenu(d.globalPosition),
          child: tabContent,
        ),
      ),
    );
  }
}

class _PlusButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _PlusButton({required this.onPressed});

  @override
  State<_PlusButton> createState() => _PlusButtonState();
}

class _PlusButtonState extends State<_PlusButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 32,
          height: 32,
          color: _hovered ? AppTheme.hover : Colors.transparent,
          child: Icon(Icons.add, size: 12, color: AppTheme.fgFaint),
        ),
      ),
    );
  }
}

/// Close button with hover highlight for tab items.
class _CloseButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _CloseButton({this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.red.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.close,
            size: 12,
            color: _hovered ? AppTheme.red : AppTheme.fgDim,
          ),
        ),
      ),
    );
  }
}

/// Drag feedback chip shown while dragging a tab.
class _DragChip extends StatelessWidget {
  final TabEntry tab;

  const _DragChip({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
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
              fontSize: 11,
              color: AppTheme.fg,
            ),
          ),
        ],
      ),
    );
  }
}
