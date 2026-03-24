import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import 'tab_controller.dart';
import 'tab_model.dart';

/// Custom tab bar with drag-to-reorder, close buttons, context menu,
/// and connection state indicators.
class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabProvider);
    final tabs = tabState.tabs;

    if (tabs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        clipBehavior: Clip.none,
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 4,
            color: Colors.transparent,
            borderOnForeground: false,
            child: child,
          );
        },
        onReorder: (oldIndex, newIndex) {
          ref.read(tabProvider.notifier).reorderTabs(oldIndex, newIndex);
        },
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = index == tabState.activeIndex;
          return ReorderableDragStartListener(
            key: ValueKey(tab.id),
            index: index,
            child: _TabItem(
              tab: tab,
              isActive: isActive,
              onSelect: () => ref.read(tabProvider.notifier).selectTab(index),
              onClose: () => ref.read(tabProvider.notifier).closeTab(tab.id),
              onContextMenu: (offset) => _showContextMenu(
                context, ref, tab, index, tabState, offset,
              ),
            ),
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
        if (tabState.tabs.length > 1)
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
        case 'close_right':
          notifier.closeToTheRight(index);
      }
    });
  }
}

class _TabItem extends StatelessWidget {
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

  Color _stateColor() {
    switch (tab.connection.state) {
      case SSHConnectionState.connected:
        return Colors.green;
      case SSHConnectionState.connecting:
        return Colors.orange;
      case SSHConnectionState.disconnected:
        return Colors.red;
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
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onSelect,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
      ),
    );
  }
}
