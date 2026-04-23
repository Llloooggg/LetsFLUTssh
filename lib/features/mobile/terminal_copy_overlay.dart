import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';
import '../terminal/cursor_overlay.dart' show kTerminalLineHeight;

/// Trackpad-style copy mode for the mobile terminal.
///
/// Renders a virtual cursor on top of the [TerminalView] and exposes
/// relative pan gestures that move the cursor in cell units — the finger
/// never jumps the cursor to its local position (absolute placement would
/// mean covering the target with the thumb). The first touch-down also
/// drops a selection anchor at the cursor's current cell; subsequent
/// movement extends the selection from anchor → cursor and writes it
/// through [TerminalController.setSelection]. The [Terminal] itself is
/// unchanged — selection is driven entirely via the controller, so the
/// same path that desktop drag-select uses renders the highlight.
///
/// The overlay is sized to the [TerminalView]'s padded content area. It
/// does *not* intercept two-finger gestures — those are routed to the
/// outer pinch-zoom detector by the parent view, which tracks pointer
/// count and dispatches single-finger deltas through [onCursorPan] and
/// two-finger events to its own recognizer. Suspend xterm's own pointer
/// input on the enclosing [TerminalController] for the lifetime of this
/// widget so the built-in tap / long-press handlers don't fight the
/// virtual cursor.
class TerminalCopyOverlay extends StatefulWidget {
  const TerminalCopyOverlay({
    super.key,
    required this.terminal,
    required this.controller,
    required this.scrollController,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    this.padding = const EdgeInsets.all(4),
  });

  final Terminal terminal;
  final TerminalController controller;

  /// Shared with `TerminalView` so edge-panning during copy mode
  /// scrolls the xterm viewport instead of clamping the virtual
  /// cursor inside the visible rows — without this the user could
  /// never select more than one screen of text at a time.
  final ScrollController scrollController;
  final double fontSize;
  final String fontFamily;
  final List<String> fontFamilyFallback;
  final EdgeInsets padding;

  @override
  State<TerminalCopyOverlay> createState() => TerminalCopyOverlayState();
}

class TerminalCopyOverlayState extends State<TerminalCopyOverlay> {
  /// Viewport-relative cell position of the virtual cursor (0..viewWidth-1,
  /// 0..viewHeight-1). We keep it viewport-relative rather than buffer-
  /// absolute so a scroll underneath the overlay (shell output) doesn't
  /// leave the cursor stranded.
  int _cursorX = 0;
  int _cursorY = 0;

  /// Sub-cell accumulator — the gesture stream delivers fractional pixels
  /// per frame, and we only move the cursor when the accumulator crosses
  /// a full cell width/height. Prevents the cursor from jittering through
  /// a cell when the finger barely moves.
  double _pxX = 0;
  double _pxY = 0;

  /// Selection anchor in *buffer-absolute* coordinates (y includes the
  /// scrollback offset at the moment it was set). Null before the first
  /// pointer-down in this copy-mode session.
  int? _anchorX;
  int? _anchorYAbs;

  /// Measured cell dimensions, computed lazily on first paint and
  /// recomputed whenever [TerminalCopyOverlay.fontSize] or fontFamily
  /// changes. Mirrors the measurement approach used by
  /// [`CursorTextOverlay`](../terminal/cursor_overlay.dart) so the virtual
  /// cursor lines up exactly with the glyph cells underneath.
  Size? _cellSize;
  double? _measuredFontSize;
  String? _measuredFontFamily;

  @override
  void initState() {
    super.initState();
    final buf = widget.terminal.buffer;
    final viewStart = buf.lines.length - buf.viewHeight;
    final relY = buf.absoluteCursorY - viewStart;
    if (relY >= 0 && relY < buf.viewHeight) {
      _cursorX = buf.cursorX;
      _cursorY = relY;
    } else {
      _cursorX = widget.terminal.viewWidth ~/ 2;
      _cursorY = widget.terminal.viewHeight ~/ 2;
    }
    widget.controller.setSuspendPointerInput(true);
    widget.controller.clearSelection();
  }

  @override
  void dispose() {
    widget.controller.setSuspendPointerInput(false);
    widget.controller.clearSelection();
    super.dispose();
  }

  Size _measureCellSize() {
    if (_cellSize != null &&
        _measuredFontSize == widget.fontSize &&
        _measuredFontFamily == widget.fontFamily) {
      return _cellSize!;
    }
    // Must match xterm's painter: `height: kTerminalLineHeight` on both
    // the paragraph style and the text style, otherwise the virtual
    // cursor marker lands ~20 % off from the xterm-rendered glyphs and
    // selection anchors drift below the cursor cell.
    final style = ui.TextStyle(
      fontFamily: widget.fontFamily,
      fontFamilyFallback: widget.fontFamilyFallback,
      fontSize: widget.fontSize,
      height: kTerminalLineHeight,
    );
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(height: kTerminalLineHeight))
          ..pushStyle(style)
          ..addText('mmmmmmmmmm');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    _cellSize = Size(paragraph.maxIntrinsicWidth / 10, paragraph.height);
    _measuredFontSize = widget.fontSize;
    _measuredFontFamily = widget.fontFamily;
    paragraph.dispose();
    return _cellSize!;
  }

  /// Consume [delta] pixels of finger movement, advance the cursor by the
  /// whole-cell remainder, and update the live selection. Called by the
  /// parent [MobileTerminalView] when a single-pointer drag is in flight.
  ///
  /// When the cursor would step past the viewport edge we scroll the
  /// xterm buffer in that direction by the overflow cells instead of
  /// clamping — this lets a single drag extend the selection through
  /// as much scrollback as the buffer holds. Horizontal overflow still
  /// clamps: xterm's viewport has no horizontal scrollback.
  void onCursorPan(Offset delta) {
    final cell = _measureCellSize();
    _pxX += delta.dx;
    _pxY += delta.dy;
    final dx = _pxX ~/ cell.width;
    final dy = _pxY ~/ cell.height;
    if (dx == 0 && dy == 0) return;
    _pxX -= dx * cell.width;
    _pxY -= dy * cell.height;
    final viewMaxY = widget.terminal.viewHeight - 1;
    final targetY = _cursorY + dy;
    int scrollOverflowCells = 0;
    int newY = targetY;
    if (targetY < 0) {
      scrollOverflowCells = targetY; // negative → scroll up into scrollback
      newY = 0;
    } else if (targetY > viewMaxY) {
      scrollOverflowCells = targetY - viewMaxY; // positive → toward live bottom
      newY = viewMaxY;
    }
    if (scrollOverflowCells != 0) {
      _scrollByCells(scrollOverflowCells, cell.height);
    }
    setState(() {
      _cursorX = (_cursorX + dx).clamp(0, widget.terminal.viewWidth - 1);
      _cursorY = newY;
      _syncSelection();
    });
  }

  /// Jump the shared scroll controller by [cells] rows worth of pixels,
  /// clamping to the scrollable extent. No-op when the controller is
  /// not attached (widget still building) or the extent is zero (buffer
  /// fits in the viewport).
  void _scrollByCells(int cells, double cellHeight) {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    final desired = (widget.scrollController.offset + cells * cellHeight).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    widget.scrollController.jumpTo(desired);
  }

  /// Drop the selection anchor at the current cursor position. Called by
  /// the parent on the *first* pointer-down of each copy-mode session —
  /// subsequent pointer-downs don't re-anchor, they continue extending the
  /// existing selection so the user can lift and re-touch without losing
  /// progress.
  void onAnchorDown() {
    if (_anchorX != null) return;
    _anchorX = _cursorX;
    _anchorYAbs = _cursorY + _viewportStartLine();
    _syncSelection();
  }

  /// Buffer-absolute index of the first visible row, accounting for
  /// live scroll offset. The old `buf.lines.length - buf.viewHeight`
  /// formula only held when the view was pinned to the bottom —
  /// during copy mode the user can scroll up, so we derive the
  /// visible start from the shared scroll controller instead.
  int _viewportStartLine() {
    final buf = widget.terminal.buffer;
    if (!widget.scrollController.hasClients) {
      return buf.lines.length - buf.viewHeight;
    }
    final cellHeight = _measureCellSize().height;
    if (cellHeight <= 0) return buf.lines.length - buf.viewHeight;
    // Scroll offset pixels ÷ cell height = absolute row index of the
    // topmost visible line (xterm renders from row 0 at offset 0,
    // matching the same convention).
    return (widget.scrollController.offset / cellHeight).floor();
  }

  void _syncSelection() {
    final ax = _anchorX;
    final ay = _anchorYAbs;
    if (ax == null || ay == null) return;
    final buf = widget.terminal.buffer;
    final cyAbs = _cursorY + _viewportStartLine();
    widget.controller.setSelection(
      buf.createAnchor(ax, ay),
      buf.createAnchor(_cursorX, cyAbs),
    );
  }

  /// True after the first [onAnchorDown] — surfaced so the parent can
  /// swap between "Tap to mark start" and "Tap to extend" hint copy in
  /// the top hint bar that now lives above the terminal in the mobile
  /// Column layout.
  bool get anchorSet => _anchorX != null;

  @override
  Widget build(BuildContext context) {
    final cell = _measureCellSize();
    final x = _cursorX * cell.width + widget.padding.left;
    final y = _cursorY * cell.height + widget.padding.top;
    // Cursor marker only. The hint banner and Copy/Cancel toolbar moved
    // out to `MobileTerminalView`'s Column so they shrink the terminal
    // instead of floating over its last row (covering the active line
    // is unusable on a 400 px-tall phone viewport). Pointer events on
    // the cursor must not be intercepted: the enclosing Listener reads
    // cursor-pan deltas via `onCursorPan`, and an opaque widget on top
    // would swallow them.
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: x,
            top: y,
            width: cell.width,
            height: cell.height,
            child: const _CursorMarker(),
          ),
        ],
      ),
    );
  }
}

class _CursorMarker extends StatelessWidget {
  const _CursorMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.accent, width: 2),
        color: AppTheme.accent.withValues(alpha: 0.25),
      ),
    );
  }
}

// The former CopyModeHint / CopyModeToolbar helpers were removed: the
// stable-height layout now swaps the SshKeyboardBar's own row content
// between a normal-keys variant and a copy-mode variant (hint text +
// Copy + Cancel) inside the SAME `itemHeightLg` container. Having
// dedicated banner / toolbar widgets next to the terminal forced the
// terminal's widget height to change every time copy mode toggled,
// which was the source of the mid-buffer reshuffle users kept
// reporting. See `ssh_keyboard_bar._buildCopyModeRow` for the new
// hint + action surface.
