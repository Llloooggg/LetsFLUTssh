import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../theme/app_theme.dart';
import 'tab_controller.dart';
import 'tab_model.dart';

/// Custom tab bar with drag-to-reorder.
///
/// Drag any tab to reorder. Click to select, right-click for context menu.
class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabProvider);
    final tabs = tabState.tabs;

    if (tabs.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = index == tabState.activeIndex;

          // DragTarget for reorder: accepts drops from other tabs' grip handles.
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
              final isDropHover = candidates.isNotEmpty;

              return Container(
                decoration: isDropHover
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      )
                    : null,
                child: _TabItem(
                  tab: tab,
                  isActive: isActive,
                  theme: theme,
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
    showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'close',
          child: Text('Close'),
        ),
        if (tabState.tabs.length > 1)
          const PopupMenuItem(
            value: 'close_others',
            child: Text('Close Others'),
          ),
        if (index > 0)
          const PopupMenuItem(
            value: 'close_left',
            child: Text('Close Tabs to the Left'),
          ),
        if (index < tabState.tabs.length - 1)
          const PopupMenuItem(
            value: 'close_right',
            child: Text('Close Tabs to the Right'),
          ),
      ],
    ).then((value) {
      if (value == null) return;
      final notifier = ref.read(tabProvider.notifier);
      switch (value) {
        case 'close':
          notifier.closeTab(tab.id);
        case 'close_others':
          notifier.closeOthers(tab.id);
        case 'close_left':
          notifier.closeToTheLeft(index);
        case 'close_right':
          notifier.closeToTheRight(index);
      }
    });
  }
}

class _TabItem extends StatelessWidget {
  final TabEntry tab;
  final bool isActive;
  final ThemeData theme;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(Offset position) onContextMenu;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.theme,
    required this.onSelect,
    required this.onClose,
    required this.onContextMenu,
  });

  Color _stateColor() {
    final brightness = theme.brightness;
    switch (tab.connection.state) {
      case SSHConnectionState.connected:
        return AppTheme.connectedColor(brightness);
      case SSHConnectionState.connecting:
        return AppTheme.connectingColor(brightness);
      case SSHConnectionState.disconnected:
        return AppTheme.disconnectedColor(brightness);
    }
  }

  IconData _kindIcon() {
    switch (tab.kind) {
      case TabKind.terminal:
        return Icons.terminal;
      case TabKind.sftp:
        return Icons.folder;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _stateColor(),
            ),
          ),
          const SizedBox(width: 6),
          Icon(_kindIcon(), size: 14),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              tab.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14),
            ),
          ),
        ],
      ),
    );

    return Draggable<TabEntry>(
      data: tab,
      feedback: Material(
        elevation: 4,
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: _DragChip(tab: tab, theme: theme),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: tabContent,
      ),
      child: GestureDetector(
        onTap: onSelect,
        onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
        child: tabContent,
      ),
    );
  }
}

/// Drag feedback chip shown while dragging a tab.
class _DragChip extends StatelessWidget {
  final TabEntry tab;
  final ThemeData theme;

  const _DragChip({required this.tab, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.primary, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tab.kind == TabKind.terminal ? Icons.terminal : Icons.folder,
            size: 14,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Text(tab.label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
