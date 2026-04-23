import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icon_button.dart';

/// Top toolbar above the workspace panels.
///
/// Pure StatelessWidget — every affordance (sidebar toggle, Tools,
/// Settings, duplicate-tab, duplicate-down) comes in through a
/// constructor callback. Rendered by `_MainScreenState._buildToolbar`
/// in main.dart; moved out of main.dart so the MainScreen class stays
/// focused on app-lifecycle orchestration instead of carrying a
/// ~65-LOC toolbar widget inline.
class AppToolbar extends StatelessWidget {
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final bool showMenuButton;
  final bool isTerminalTab;
  final VoidCallback? onDuplicateTab;
  final VoidCallback? onDuplicateDown;
  final VoidCallback onTools;
  final VoidCallback onSettings;

  const AppToolbar({
    super.key,
    required this.sidebarOpen,
    required this.onToggleSidebar,
    this.showMenuButton = false,
    this.isTerminalTab = false,
    this.onDuplicateTab,
    this.onDuplicateDown,
    required this.onTools,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 2),
        if (showMenuButton)
          AppIconButton(
            icon: Icons.menu,
            onTap: () => Scaffold.of(context).openDrawer(),
            tooltip: S.of(context).sessions,
            color: AppTheme.fgDim,
          )
        else
          AppIconButton(
            icon: sidebarOpen ? Icons.chevron_left : Icons.chevron_right,
            onTap: onToggleSidebar,
            tooltip: sidebarOpen
                ? S.of(context).hideSidebar
                : S.of(context).showSidebar,
          ),
        AppButton(label: S.of(context).tools, onTap: onTools, dense: true),
        AppButton(
          label: S.of(context).settings,
          onTap: onSettings,
          dense: true,
        ),
        const Spacer(),
        if (isTerminalTab) ...[
          AppIconButton(
            icon: Icons.content_copy,
            onTap: onDuplicateTab,
            tooltip: S.of(context).duplicateTabShortcut,
          ),
          AppIconButton(
            icon: Icons.horizontal_split,
            onTap: onDuplicateDown,
            tooltip: S.of(context).duplicateDownShortcut,
          ),
        ],
        const SizedBox(width: 2),
      ],
    );
  }
}
