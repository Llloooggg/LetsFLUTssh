import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import 'tab_controller.dart';
import 'tab_model.dart';

/// Custom tab bar with close buttons and connection state indicators.
class AppTabBar extends ConsumerWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabProvider);
    final tabs = tabState.tabs;

    if (tabs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = index == tabState.activeIndex;
          return _TabItem(
            tab: tab,
            isActive: isActive,
            onSelect: () => ref.read(tabProvider.notifier).selectTab(index),
            onClose: () => ref.read(tabProvider.notifier).closeTab(tab.id),
          );
        },
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final TabEntry tab;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
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
            Text(
              tab.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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
