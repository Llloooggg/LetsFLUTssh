import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_selection_area.dart';
import 'hover_region.dart';
import 'shortcut_registry.dart';

/// One entry in a [SidebarNavDialog]'s navigation rail: a nav-rail label and
/// the panel it reveals. The panel is built lazily on first selection and
/// kept alive afterwards — see [SidebarNavDialog].
@immutable
class SidebarNavEntry {
  final IconData icon;
  final String title;
  final Widget Function() builder;

  const SidebarNavEntry({
    required this.icon,
    required this.title,
    required this.builder,
  });
}

/// Full-screen desktop modal with a fixed-width navigation rail on the left
/// and a content pane on the right (VS Code style). Shared shell for the
/// Tools and Settings dialogs so the chrome — inset, selection scope,
/// dismiss shortcut, header, rail styling — has a single definition.
///
/// The content pane is a lazy `IndexedStack`: each entry's panel builds on
/// first selection and then stays mounted, so re-selecting a panel is a
/// cheap index flip rather than a teardown + re-run of its `initState` load
/// (key fetch, filesystem scan, stream subscribe). Without keep-alive the
/// selected-row highlight repaints in the same frame as that rebuild, so
/// rapid nav clicks feel dropped until the load finishes.
class SidebarNavDialog extends StatefulWidget {
  /// Title shown in the dialog header.
  final String title;

  /// Nav-rail entries, top to bottom. The first entry is selected initially.
  final List<SidebarNavEntry> entries;

  /// Optional control pinned below the nav list (e.g. a Reset button).
  final Widget? sidebarFooter;

  /// Optional wrapper applied to each built panel — e.g. Settings scrolls
  /// each section in a `ListView`; Tools' panels fill the pane directly.
  final Widget Function(Widget panel)? panelBuilder;

  const SidebarNavDialog({
    super.key,
    required this.title,
    required this.entries,
    this.sidebarFooter,
    this.panelBuilder,
  });

  @override
  State<SidebarNavDialog> createState() => _SidebarNavDialogState();
}

class _SidebarNavDialogState extends State<SidebarNavDialog> {
  int _selectedIndex = 0;

  // Indices whose panel has been built at least once. Unvisited slots stay
  // an empty box; visited ones keep their mounted panel across switches.
  final Set<int> _visited = {0};

  void _select(int index) => setState(() {
    _selectedIndex = index;
    _visited.add(index);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;

    return Dialog(
      // Shared formula keeps every full-screen desktop modal at the same
      // symmetric gutter so they read as siblings.
      insetPadding: AppTheme.desktopModalInsetPadding(viewportWidth),
      backgroundColor: AppTheme.bg1,
      // The root `SelectionArea` lives below this modal in the Overlay
      // stack, so dialog Text needs its own scope to stay selectable.
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
                  title: widget.title,
                  onClose: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Row(
                    children: [
                      _buildSidebar(theme),
                      VerticalDivider(width: 1, color: theme.dividerColor),
                      Expanded(child: _buildContent()),
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

  Widget _buildSidebar(ThemeData theme) {
    final list = ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        return _SidebarNavItem(
          icon: entry.icon,
          label: entry.title,
          selected: index == _selectedIndex,
          onTap: () => _select(index),
        );
      },
    );
    // The rail is chrome, not copyable body text — opt the whole subtree out
    // of the ambient `AppSelectionArea` so labels show no I-beam cursor and
    // never hijack `Ctrl+C` from a selection in the content pane.
    return SizedBox(
      width: 200,
      child: SelectionContainer.disabled(
        child: Container(
          color: theme.colorScheme.surfaceContainerLow,
          child: widget.sidebarFooter == null
              ? list
              : Column(
                  children: [
                    Expanded(child: list),
                    widget.sidebarFooter!,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return IndexedStack(
      index: _selectedIndex,
      // Tight fill so each panel lays out exactly as it would in a plain
      // `Expanded` content slot.
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < widget.entries.length; i++)
          if (_visited.contains(i))
            _wrap(widget.entries[i].builder())
          else
            const SizedBox.shrink(),
      ],
    );
  }

  Widget _wrap(Widget panel) => widget.panelBuilder?.call(panel) ?? panel;
}

/// A single item in the navigation rail. Stateless — `HoverRegion` owns the
/// hover state and the selection auto-opt-out.
class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarNavItem({
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
              const SizedBox(width: AppSpacing.sm),
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
