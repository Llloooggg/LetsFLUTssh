import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// Shared selection-mode action bar for mobile screens.
///
/// Used by both the file browser and the session panel to display
/// a consistent bar with: close, count, select/deselect all,
/// custom action buttons, and delete.
class MobileSelectionBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback? onDelete;
  final List<Widget> actions;

  const MobileSelectionBar({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onDelete,
    this.actions = const [],
  });

  bool get _allSelected => totalCount > 0 && selectedCount >= totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = S.of(context);
    return Container(
      height: AppTheme.barHeightLg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.close,
            size: 20,
            boxSize: 36,
            onTap: onCancel,
            tooltip: loc.cancelSelection,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              loc.nSelectedCount(selectedCount),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppFonts.lg),
            ),
          ),
          if (_allSelected)
            AppIconButton(
              icon: Icons.deselect,
              size: 20,
              boxSize: 36,
              onTap: onDeselectAll,
              tooltip: loc.deselectAll,
            )
          else
            AppIconButton(
              icon: Icons.select_all,
              size: 20,
              boxSize: 36,
              onTap: onSelectAll,
              tooltip: loc.selectAll,
            ),
          ...actions,
          AppIconButton(
            icon: Icons.delete,
            size: 20,
            boxSize: 36,
            color: selectedCount > 0 ? AppTheme.disconnected : null,
            onTap: onDelete,
            tooltip: loc.delete,
          ),
        ],
      ),
    );
  }
}
