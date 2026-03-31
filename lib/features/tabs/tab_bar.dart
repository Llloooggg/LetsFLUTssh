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
class AppTabBar extends ConsumerWidget {
  final VoidCallback onNewSession;

  const AppTabBar({super.key, required this.onNewSession});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabProvider);
    // Watch connection state changes so tab indicators update.
    ref.watch(connectionsProvider);
    final tabs = tabState.tabs;

    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppTheme.bg1,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          if (tabs.isNotEmpty)
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tabs.length,
                itemBuilder: (context, index) {
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
                            ? const BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: AppTheme.accent,
                                    width: 2,
                                  ),
                                ),
                              )
                            : null,
                        child: _TabItem(
                          tab: tab,
                          isActive: isActive,
                          onSelect: () =>
                              ref.read(tabProvider.notifier).selectTab(index),
                          onClose: () =>
                              ref.read(tabProvider.notifier).closeTab(tab.id),
                          onContextMenu: (offset) => _showContextMenu(
                            context, ref, tab, index, tabState, offset,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            )
          else
            const Spacer(),
          _PlusButton(onPressed: onNewSession),
        ],
      ),
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
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(Offset position) onContextMenu;

  const _TabItem({
    required this.tab,
    required this.isActive,
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
      height: 32,
      child: Stack(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: widget.isActive ? AppTheme.bg2 : Colors.transparent,
              border: const Border(
                right: BorderSide(color: AppTheme.border),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _dotColor(),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  widget.tab.kind == TabKind.terminal
                      ? Icons.terminal
                      : Icons.folder,
                  size: 12,
                  color: _iconColor(),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
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
                if (widget.tab.kind == TabKind.sftp) ...[
                  const SizedBox(width: 4),
                  const Text(
                    'SFTP',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      color: AppTheme.fgFaint,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Opacity(
                  opacity: showClose ? 1.0 : 0.0,
                  child: GestureDetector(
                    onTap: showClose ? widget.onClose : null,
                    child: const SizedBox(
                      width: 16,
                      height: 16,
                      child: Icon(Icons.close, size: 10, color: AppTheme.fgDim),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.isActive)
            const Positioned(
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
          child: const Icon(Icons.add, size: 12, color: AppTheme.fgFaint),
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
      decoration: const BoxDecoration(
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
            style: const TextStyle(
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
