import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/shortcut_registry.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_divider.dart';

/// A single context menu item — either a normal item or a divider.
class ContextMenuItem {
  final String? label;
  final IconData? icon;
  final Color? color;
  final String? shortcut;
  final bool divider;
  final VoidCallback? onTap;

  const ContextMenuItem({
    this.label,
    this.icon,
    this.color,
    this.shortcut,
    this.divider = false,
    this.onTap,
  });

  const ContextMenuItem.divider()
    : label = null,
      icon = null,
      color = null,
      shortcut = null,
      divider = true,
      onTap = null;
}

/// Catalogue of every action that appears in the app's right-click menus.
///
/// One enum value per distinct action — label, icon, and optional accent
/// colour live alongside it so a menu site only supplies the side-effect
/// (onTap) and, when applicable, the [AppShortcut] whose label should be
/// shown. The same [paste] entry therefore reads `Ctrl+V` in the session
/// panel and `Ctrl+Shift+V` in the terminal, because each site binds a
/// different [AppShortcut] — the shortcut string is formatted from the
/// live [AppShortcutRegistry] binding, never hardcoded.
///
/// This is the whole "context menu vocabulary" — adding a new action
/// means adding a value here, which guarantees the same icon / accent /
/// translated label everywhere the action is reused.
enum StandardMenuAction {
  copy,
  paste,
  delete,
  rename,
  duplicate,
  refresh,
  open,
  transfer,
  snippets,
  terminal,
  files,
  editConnection,
  newConnection,
  newFolder,
  renameFolder,
  editTags,
  deleteFolder,
  close,
  closeOthers,
  closeTabsToTheLeft,
  closeTabsToTheRight,
  closeAll,
  maximize,
  restore;

  /// Build a [ContextMenuItem] for this action.
  ///
  /// - [shortcut] — when supplied, its live binding is rendered as the
  ///   trailing hint (e.g. `Ctrl+Shift+V` for [AppShortcut.terminalPaste]).
  /// - [labelOverride] — overrides the default translation when the
  ///   caller needs a dynamic label (e.g. `Delete 3 items`).
  ContextMenuItem item(
    BuildContext context, {
    required VoidCallback onTap,
    AppShortcut? shortcut,
    String? labelOverride,
  }) {
    final spec = _specFor(this);
    return ContextMenuItem(
      label: labelOverride ?? spec.label(S.of(context)),
      icon: spec.icon,
      color: spec.color,
      shortcut: shortcut == null
          ? null
          : AppShortcutRegistry.instance.shortcutLabel(shortcut),
      onTap: onTap,
    );
  }
}

/// Static definition of label / icon / colour for a [StandardMenuAction].
class _MenuActionSpec {
  final String Function(S l10n) label;
  final IconData icon;
  final Color? color;
  const _MenuActionSpec({required this.label, required this.icon, this.color});
}

_MenuActionSpec _specFor(StandardMenuAction a) {
  switch (a) {
    case StandardMenuAction.copy:
      return _MenuActionSpec(label: (l) => l.copy, icon: Icons.copy);
    case StandardMenuAction.paste:
      return _MenuActionSpec(label: (l) => l.paste, icon: Icons.paste);
    case StandardMenuAction.delete:
      return _MenuActionSpec(
        label: (l) => l.delete,
        icon: Icons.delete,
        color: AppTheme.red,
      );
    case StandardMenuAction.rename:
      return _MenuActionSpec(label: (l) => l.rename, icon: Icons.edit);
    case StandardMenuAction.duplicate:
      return _MenuActionSpec(label: (l) => l.duplicate, icon: Icons.copy);
    case StandardMenuAction.refresh:
      return _MenuActionSpec(label: (l) => l.refresh, icon: Icons.refresh);
    case StandardMenuAction.open:
      return _MenuActionSpec(label: (l) => l.open, icon: Icons.folder_open);
    case StandardMenuAction.transfer:
      return _MenuActionSpec(label: (l) => l.transfer, icon: Icons.swap_horiz);
    case StandardMenuAction.snippets:
      return _MenuActionSpec(label: (l) => l.snippets, icon: Icons.code);
    case StandardMenuAction.terminal:
      return _MenuActionSpec(
        label: (l) => l.terminal,
        icon: Icons.terminal,
        color: AppTheme.blue,
      );
    case StandardMenuAction.files:
      return _MenuActionSpec(
        label: (l) => l.files,
        icon: Icons.folder,
        color: AppTheme.yellow,
      );
    case StandardMenuAction.editConnection:
      return _MenuActionSpec(
        label: (l) => l.editConnection,
        icon: Icons.settings,
      );
    case StandardMenuAction.newConnection:
      return _MenuActionSpec(label: (l) => l.newConnection, icon: Icons.add);
    case StandardMenuAction.newFolder:
      return _MenuActionSpec(
        label: (l) => l.newFolder,
        icon: Icons.create_new_folder,
      );
    case StandardMenuAction.renameFolder:
      return _MenuActionSpec(
        label: (l) => l.renameFolder,
        icon: Icons.drive_file_rename_outline,
      );
    case StandardMenuAction.editTags:
      return _MenuActionSpec(
        label: (l) => l.editTags,
        icon: Icons.label_outline,
      );
    case StandardMenuAction.deleteFolder:
      return _MenuActionSpec(
        label: (l) => l.deleteFolder,
        icon: Icons.delete,
        color: AppTheme.red,
      );
    case StandardMenuAction.close:
      return _MenuActionSpec(label: (l) => l.close, icon: Icons.close);
    case StandardMenuAction.closeOthers:
      return _MenuActionSpec(
        label: (l) => l.closeOthers,
        icon: Icons.tab_unselected,
      );
    case StandardMenuAction.closeTabsToTheLeft:
      return _MenuActionSpec(
        label: (l) => l.closeTabsToTheLeft,
        icon: Icons.first_page,
      );
    case StandardMenuAction.closeTabsToTheRight:
      return _MenuActionSpec(
        label: (l) => l.closeTabsToTheRight,
        icon: Icons.last_page,
      );
    case StandardMenuAction.closeAll:
      return _MenuActionSpec(
        label: (l) => l.closeAll,
        icon: Icons.close_fullscreen,
        color: AppTheme.red,
      );
    case StandardMenuAction.maximize:
      return _MenuActionSpec(
        label: (l) => l.maximize,
        icon: Icons.open_in_full,
      );
    case StandardMenuAction.restore:
      return _MenuActionSpec(
        label: (l) => l.restore,
        icon: Icons.close_fullscreen,
      );
  }
}

// Active menu state — allows re-entrant right-click to dismiss + reopen.
OverlayEntry? _activeEntry;
Completer<void>? _activeCompleter;

void _dismissActive() {
  _activeEntry?.remove();
  _activeEntry = null;
  if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
    _activeCompleter!.complete();
  }
  _activeCompleter = null;
}

/// Shows a custom context menu at [position] with the given [items].
///
/// Returns a `Future` that completes when the menu is dismissed.
/// The caller does not need to handle the return value — each item's
/// [ContextMenuItem.onTap] is invoked when selected.
///
/// If a menu is already open, it is dismissed first.
Future<void> showAppContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
}) {
  _dismissActive();

  final overlay = Overlay.of(context);
  final completer = Completer<void>();
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _ContextMenuOverlay(
      position: position,
      items: items,
      onDismiss: () {
        if (_activeEntry == entry) {
          _dismissActive();
        }
      },
    ),
  );

  _activeEntry = entry;
  _activeCompleter = completer;
  overlay.insert(entry);
  return completer.future;
}

class _ContextMenuOverlay extends StatefulWidget {
  final Offset position;
  final List<ContextMenuItem> items;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({
    required this.position,
    required this.items,
    required this.onDismiss,
  });

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> {
  int? _hoveredIndex;
  int? _keyIndex;
  late final FocusNode _focusNode;

  // Non-divider item indices for keyboard navigation.
  late final List<int> _actionableIndices;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _actionableIndices = [
      for (int i = 0; i < widget.items.length; i++)
        if (!widget.items[i].divider) i,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _moveKey(int delta) {
    if (_actionableIndices.isEmpty) return;
    setState(() {
      if (_keyIndex == null) {
        _keyIndex =
            _actionableIndices[delta > 0 ? 0 : _actionableIndices.length - 1];
      } else {
        final cur = _actionableIndices.indexOf(_keyIndex!);
        final next = (cur + delta) % _actionableIndices.length;
        _keyIndex = _actionableIndices[next];
      }
      _hoveredIndex = null;
    });
  }

  void _activate(int index) {
    widget.items[index].onTap?.call();
    widget.onDismiss();
  }

  int? get _activeIndex => _keyIndex ?? _hoveredIndex;

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveKey(1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveKey(-1);
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_activeIndex != null) _activate(_activeIndex!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Barrier — dismiss on any click outside the menu.
        // Translucent so right-clicks reach widgets below and re-open a menu.
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) => widget.onDismiss(),
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        // Menu itself.
        CustomSingleChildLayout(
          delegate: _MenuPositionDelegate(widget.position),
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(minWidth: 200),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bg1,
                  border: Border.all(color: AppTheme.borderLight),
                  borderRadius: AppTheme.radiusSm,
                ),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < widget.items.length; i++)
                        widget.items[i].divider
                            ? const AppDivider.indented()
                            : _buildItem(i),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(int index) {
    final item = widget.items[index];
    final isActive = _activeIndex == index;
    final fgColor = item.color ?? AppTheme.fg;
    final iconColor = item.color ?? AppTheme.fgDim;
    final shortcutBg = AppTheme.bg3;
    final shortcutFg = AppTheme.fgFaint;
    final hoverBg = AppTheme.selection;

    return Semantics(
      button: true,
      label: item.label,
      child: MouseRegion(
        onEnter: (_) => setState(() {
          _hoveredIndex = index;
          _keyIndex = null;
        }),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTap: () => _activate(index),
          child: Container(
            height: AppTheme.controlHeightSm,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: isActive ? hoverBg : Colors.transparent,
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 13, color: iconColor),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    item.label ?? '',
                    style: AppFonts.inter(
                      fontSize: AppFonts.sm,
                      color: fgColor,
                    ),
                  ),
                ),
                if (item.shortcut != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    color: shortcutBg,
                    child: Text(
                      item.shortcut!,
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: AppFonts.xxs,
                        color: shortcutFg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Positions the menu near [position], adjusting to stay within screen bounds.
class _MenuPositionDelegate extends SingleChildLayoutDelegate {
  final Offset position;

  _MenuPositionDelegate(this.position);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = position.dx;
    double y = position.dy;

    if (x + childSize.width > size.width) {
      x = size.width - childSize.width;
    }
    if (y + childSize.height > size.height) {
      y = size.height - childSize.height;
    }
    return Offset(x.clamp(0, size.width), y.clamp(0, size.height));
  }

  @override
  bool shouldRelayout(_MenuPositionDelegate oldDelegate) =>
      position != oldDelegate.position;
}
