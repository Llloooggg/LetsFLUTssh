import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HardwareKeyboard, LogicalKeyboardKey

/// Lightweight hover detector that rebuilds child with hover state.
///
/// Replaces the pattern of `MouseRegion` + `GestureDetector` + manual
/// `_hovered` state scattered across the codebase. Provides a single
/// consistent hover behavior everywhere.
///
/// Usage:
/// ```dart
/// HoverRegion(
///   onTap: () => doSomething(),
///   builder: (hovered) => Container(
///     color: hovered ? AppTheme.hover : Colors.transparent,
///     child: Text('Hello'),
///   ),
/// )
/// ```
class HoverRegion extends StatefulWidget {
  final Widget Function(bool hovered) builder;
  final VoidCallback? onTap;

  /// Called instead of [onTap] when Ctrl is held during click.
  /// When set, taps auto-detect Ctrl and route to the right callback.
  final VoidCallback? onCtrlTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final MouseCursor cursor;

  const HoverRegion({
    super.key,
    required this.builder,
    this.onTap,
    this.onCtrlTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.onLongPressStart,
    this.cursor = SystemMouseCursors.basic,
  });

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;

  static bool get _isCtrlHeld {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  void _handleTap() {
    if (widget.onCtrlTap != null && _isCtrlHeld) {
      widget.onCtrlTap!();
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGesture =
        widget.onTap != null ||
        widget.onCtrlTap != null ||
        widget.onDoubleTap != null ||
        widget.onSecondaryTapUp != null ||
        widget.onLongPressStart != null;

    Widget child = widget.builder(_hovered);

    if (hasGesture) {
      final effectiveTap = widget.onCtrlTap != null ? _handleTap : widget.onTap;
      child = GestureDetector(
        onTap: effectiveTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        onLongPressStart: widget.onLongPressStart,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: child,
    );
  }
}
