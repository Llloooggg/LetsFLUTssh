import 'package:flutter/material.dart';

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
  final VoidCallback? onDoubleTap;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final void Function(LongPressStartDetails)? onLongPressStart;
  final MouseCursor cursor;

  const HoverRegion({
    super.key,
    required this.builder,
    this.onTap,
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

  @override
  Widget build(BuildContext context) {
    final hasGesture =
        widget.onTap != null ||
        widget.onDoubleTap != null ||
        widget.onSecondaryTapUp != null ||
        widget.onLongPressStart != null;

    Widget child = widget.builder(_hovered);

    if (hasGesture) {
      child = GestureDetector(
        onTap: widget.onTap,
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
