import 'dart:async' show Timer;
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

  // Manual double-tap detection — avoids GestureDetector's onDoubleTap
  // which delays onTap by ~300 ms in the gesture arena. Uses a Timer
  // (not DateTime.now()) so the fake clock in widget tests advances
  // correctly via tester.pump().
  //
  // Strategy: on first tap, arm a 400 ms timer. If a second tap arrives
  // before the timer fires, cancel it and call onDoubleTap. If the timer
  // fires with only one tap, call onTap. The 400 ms window matches
  // session_tree_view and terminal multi-tap constants.
  Timer? _doubleTapTimer;
  int _tapCount = 0;

  static const _kDoubleTapWindow = Duration(milliseconds: 400);

  static bool get _isCtrlHeld {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onCtrlTap != null && _isCtrlHeld) {
      widget.onCtrlTap!();
      return;
    }

    // If no double-tap callback, just fire onTap immediately.
    final onDoubleTap = widget.onDoubleTap;
    if (onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }

    _tapCount++;
    if (_tapCount == 1) {
      // Fire onTap immediately for responsiveness, then arm the timer.
      // If a second tap arrives before the timer fires, onDoubleTap
      // will be called. The timer just resets state when it expires.
      widget.onTap?.call();
      _doubleTapTimer?.cancel();
      _doubleTapTimer = Timer(_kDoubleTapWindow, () {
        _tapCount = 0;
      });
    } else if (_tapCount >= 2) {
      // Second tap arrived — fire onDoubleTap and reset.
      _doubleTapTimer?.cancel();
      _doubleTapTimer = null;
      _tapCount = 0;
      onDoubleTap();
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
      // onTap is the ONLY primary-button gesture on GestureDetector.
      // onDoubleTap is removed from the arena — it's disambiguated
      // manually in _handleTap via a Timer. This eliminates the
      // ~300 ms gesture-arena delay that GestureDetector adds when
      // both onTap and onDoubleTap are set.
      child = GestureDetector(
        onTap: _handleTap,
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
