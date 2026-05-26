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

    // If this region has any tap / long-press binding, it is a
    // button in UX terms — exclude its content from any ambient
    // `SelectionArea` so its Text doesn't catch a drag-select, doesn't
    // flip the cursor to the I-beam on hover, and doesn't race the
    // SelectionArea's `TapAndDragGestureRecognizer` for pan events
    // (the race surfaces as "drag-select works every other time" on
    // adjacent Text widgets because the gesture arena arbitration
    // depends on arrival order). Desktop no longer has a global
    // `SelectionArea` — the wrap here is mostly a no-op at the shell
    // level and matters inside local selection scopes (dialogs,
    // threat list). Plain informational Text (subtitles, probe
    // hints, labels) lives outside `HoverRegion` and keeps the
    // ambient selection.
    if (hasGesture) {
      child = SelectionContainer.disabled(child: child);
    }

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
