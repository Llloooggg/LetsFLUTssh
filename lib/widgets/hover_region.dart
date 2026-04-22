import 'dart:io' show Platform;

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

    // NOTE: earlier this block wrapped the child in
    // `SelectionContainer.disabled` when `hasGesture == true` so the
    // ambient `SelectionArea` would not drag-select button text.
    // That wrap broke every nested `ThresholdDraggable` (session
    // tabs, file-browser rows): the pan gesture never reached the
    // draggable's recogniser, so tab reordering and drag-to-tile
    // both went dead. The SelectionArea drag-select issue on
    // button labels is the smaller of the two — revert the wrap
    // here and re-apply the selection opt-out where needed by
    // wrapping the specific inner Text(s), not the whole gesture
    // subtree.

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

    // Skip MouseRegion on mobile — no mouse pointer, avoids unnecessary widget.
    if (Platform.isAndroid || Platform.isIOS) return child;

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: child,
    );
  }
}
