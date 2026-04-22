import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../l10n/app_localizations.dart';
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
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    this.padding = const EdgeInsets.all(4),
  });

  final Terminal terminal;
  final TerminalController controller;
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
  void onCursorPan(Offset delta) {
    final cell = _measureCellSize();
    _pxX += delta.dx;
    _pxY += delta.dy;
    final dx = _pxX ~/ cell.width;
    final dy = _pxY ~/ cell.height;
    if (dx == 0 && dy == 0) return;
    _pxX -= dx * cell.width;
    _pxY -= dy * cell.height;
    setState(() {
      _cursorX = (_cursorX + dx).clamp(0, widget.terminal.viewWidth - 1);
      _cursorY = (_cursorY + dy).clamp(0, widget.terminal.viewHeight - 1);
      _syncSelection();
    });
  }

  /// Drop the selection anchor at the current cursor position. Called by
  /// the parent on the *first* pointer-down of each copy-mode session —
  /// subsequent pointer-downs don't re-anchor, they continue extending the
  /// existing selection so the user can lift and re-touch without losing
  /// progress.
  void onAnchorDown() {
    if (_anchorX != null) return;
    final buf = widget.terminal.buffer;
    final viewStart = buf.lines.length - buf.viewHeight;
    _anchorX = _cursorX;
    _anchorYAbs = _cursorY + viewStart;
    _syncSelection();
  }

  void _syncSelection() {
    final ax = _anchorX;
    final ay = _anchorYAbs;
    if (ax == null || ay == null) return;
    final buf = widget.terminal.buffer;
    final viewStart = buf.lines.length - buf.viewHeight;
    final cyAbs = _cursorY + viewStart;
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

/// Copy-mode hint banner rendered *above* the terminal in the mobile
/// Column layout so it pushes the terminal down instead of overlaying
/// its last row. Swaps between "tap to mark start" and "tap to extend"
/// copy once the user drops an anchor.
class CopyModeHint extends StatelessWidget {
  const CopyModeHint({super.key, required this.anchorSet});

  final bool anchorSet;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final text = anchorSet ? l10n.copyModeExtending : l10n.copyModeTapToStart;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppTheme.bg3,
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppFonts.sm,
          color: AppTheme.fg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Copy-mode action bar (Copy + Cancel). Lives *below* the terminal in
/// the mobile Column layout so it shrinks the terminal viewport rather
/// than covering it and butts flush against the SSH keyboard bar / soft
/// keyboard underneath.
class CopyModeToolbar extends StatelessWidget {
  const CopyModeToolbar({
    super.key,
    required this.onCopy,
    required this.onCancel,
  });

  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: AppTheme.bg3,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToolbarButton(icon: Icons.copy, label: l10n.copy, onTap: onCopy),
          const SizedBox(width: 16),
          _ToolbarButton(
            icon: Icons.close,
            label: l10n.cancel,
            onTap: onCancel,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: AppTheme.radiusLg,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        borderRadius: AppTheme.radiusLg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppFonts.md,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
