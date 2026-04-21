import 'package:flutter/material.dart';

import '../../core/shortcut_registry.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_selection_area.dart';
import '../../widgets/hover_region.dart';
import '../key_manager/key_manager_dialog.dart';
import '../settings/known_hosts_manager.dart';
import '../snippets/snippet_manager_dialog.dart';
import '../tags/tag_manager_dialog.dart';

/// Entry in the Tools navigation sidebar.
class _ToolEntry {
  final String title;
  final IconData icon;
  final Widget Function() builder;

  const _ToolEntry({
    required this.title,
    required this.icon,
    required this.builder,
  });
}

/// Full-screen Tools dialog (VS Code style) — SSH Keys, Snippets, Tags.
///
/// Desktop only. Mobile uses the settings screen with inline tiles.
class ToolsDialog extends StatefulWidget {
  const ToolsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const ToolsDialog(),
    );
  }

  @override
  State<ToolsDialog> createState() => _ToolsDialogState();
}

class _ToolsDialogState extends State<ToolsDialog> {
  int _selectedIndex = 0;

  List<_ToolEntry> _buildEntries(BuildContext context) => [
    _ToolEntry(
      title: S.of(context).sshKeys,
      icon: Icons.vpn_key,
      builder: KeyManagerPanel.new,
    ),
    _ToolEntry(
      title: S.of(context).snippets,
      icon: Icons.code,
      builder: SnippetManagerPanel.new,
    ),
    _ToolEntry(
      title: S.of(context).tags,
      icon: Icons.label_outline,
      builder: TagManagerPanel.new,
    ),
    _ToolEntry(
      title: S.of(context).knownHosts,
      icon: Icons.verified_user,
      builder: KnownHostsManagerPanel.new,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries(context);
    final theme = Theme.of(context);

    final viewportWidth = MediaQuery.sizeOf(context).width;
    return Dialog(
      // Match the Settings modal gutter exactly so the two VS-Code-style
      // desktop dialogs line up visually — shared formula owned by
      // AppTheme.desktopModalInsetPadding.
      insetPadding: AppTheme.desktopModalInsetPadding(viewportWidth),
      backgroundColor: AppTheme.bg1,
      // `SelectionArea` scoped to the dialog — the root one at
      // MainScreen sits below this modal in the Overlay stack, so
      // drag-to-select would not reach Text widgets inside the
      // dialog without an inner wrapper.
      child: AppSelectionArea(
        child: CallbackShortcuts(
          bindings: AppShortcutRegistry.instance.buildCallbackMap({
            AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
          }),
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                AppDialogHeader(
                  title: S.of(context).tools,
                  onClose: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Row(
                    children: [
                      // Sidebar
                      SizedBox(
                        width: 200,
                        child: Container(
                          color: theme.colorScheme.surfaceContainerLow,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return _NavItem(
                                icon: entry.icon,
                                label: entry.title,
                                selected: index == _selectedIndex,
                                onTap: () =>
                                    setState(() => _selectedIndex = index),
                              );
                            },
                          ),
                        ),
                      ),
                      VerticalDivider(width: 1, color: theme.dividerColor),
                      // Content
                      Expanded(
                        child: KeyedSubtree(
                          key: ValueKey(_selectedIndex),
                          child: entries[_selectedIndex].builder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Navigation item — matches settings sidebar style.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (hovered) {
        final Color bg;
        if (selected) {
          bg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
        } else if (hovered) {
          bg = AppTheme.hover;
        } else {
          bg = Colors.transparent;
        }
        return Container(
          height: AppTheme.controlHeightMd,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: bg,
          child: Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? AppTheme.fg : AppTheme.fgDim,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    color: selected ? AppTheme.fg : AppTheme.fgDim,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
