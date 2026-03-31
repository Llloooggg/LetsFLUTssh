import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

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

/// Shows a custom context menu at [position] with the given [items].
///
/// Returns a `Future` that completes when the menu is dismissed.
/// The caller does not need to handle the return value — each item's
/// [ContextMenuItem.onTap] is invoked when selected.
Future<void> showAppContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;

  final completer = Completer<void>();

  entry = OverlayEntry(
    builder: (ctx) => _ContextMenuOverlay(
      position: position,
      items: items,
      onDismiss: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
    ),
  );

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
        _keyIndex = _actionableIndices[delta > 0 ? 0 : _actionableIndices.length - 1];
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Barrier — dismiss on tap outside.
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            onSecondaryTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Menu itself.
        CustomSingleChildLayout(
          delegate: _MenuPositionDelegate(widget.position),
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: (event) {
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
            },
            child: Container(
              constraints: const BoxConstraints(minWidth: 200),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bg1,
                border: Border.all(color: AppTheme.borderLight),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 24,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < widget.items.length; i++)
                      widget.items[i].divider
                          ? const Divider(
                              height: 1,
                              thickness: 1,
                              indent: 8,
                              endIndent: 8,
                              color: AppTheme.border,
                            )
                          : _buildItem(i),
                  ],
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
    final color = item.color ?? AppTheme.fg;
    final iconColor = item.color ?? AppTheme.fgDim;

    return MouseRegion(
      onEnter: (_) => setState(() {
        _hoveredIndex = index;
        _keyIndex = null;
      }),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: GestureDetector(
        onTap: () => _activate(index),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: isActive ? AppTheme.selection : Colors.transparent,
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 13, color: iconColor),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label ?? '',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: color,
                  ),
                ),
              ),
              if (item.shortcut != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  color: AppTheme.bg3,
                  child: Text(
                    item.shortcut!,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 9,
                      color: AppTheme.fgFaint,
                    ),
                  ),
                ),
              ],
            ],
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
