import 'package:flutter/material.dart';

import '../../src/rust/api/terminal.dart' as rust_terminal;
import '../../theme/app_theme.dart';
import '../../widgets/terminal/terminal_cell_metrics.dart';

/// Trackpad-style copy mode for the mobile terminal, driving the
/// Rust-engine selection.
///
/// Renders a virtual cursor on top of the [rust_terminal.TerminalGridView]
/// content and exposes relative pan gestures that move the cursor in cell
/// units — the finger never jumps the cursor to its local position
/// (absolute placement would mean covering the target with the thumb). The
/// user drops a selection anchor with the "Set anchor" bar button; from
/// then on each pan extends the selection from anchor → cursor through
/// [onSetSelection], which the host forwards to
/// `TerminalSession.setSelection`. The copy then reads the covered text via
/// `TerminalSession.selectionText`.
///
/// The selection lives Rust-side; this widget only computes cell
/// coordinates from the gesture and the live frame geometry and hands them
/// to the host. It owns no terminal state — it reads cols / rows / scroll
/// offset off the latest [snapshotProvider] frame each gesture.
///
/// The overlay is sized to the grid's padded content area and does not
/// intercept pointers: the enclosing [Listener] reads cursor-pan deltas via
/// [onCursorPan], and an opaque widget on top would swallow them.
class TerminalCopyOverlay extends StatefulWidget {
  const TerminalCopyOverlay({
    super.key,
    required this.snapshotProvider,
    required this.onSetSelection,
    required this.onClearSelection,
    required this.onScroll,
    required this.fontSize,
    this.padding = const EdgeInsets.all(kTerminalPadding),
  });

  /// Pulls the latest [rust_terminal.TerminalFrame] so the overlay knows the
  /// current cols / rows and scroll `displayOffset` to map the virtual
  /// cursor to an absolute grid line.
  final rust_terminal.TerminalFrame Function() snapshotProvider;

  /// Set the selection over the engine: anchor → cursor in absolute
  /// grid-line coordinates (negative row = scrollback). The host forwards
  /// this to `TerminalSession.setSelection` and pulls a fresh snapshot so
  /// the highlight paints.
  final void Function(int startRow, int startCol, int endRow, int endCol)
  onSetSelection;

  /// Clear any active engine selection (overlay open / dispose).
  final VoidCallback onClearSelection;

  /// Scroll the viewport by whole lines (positive = up into scrollback)
  /// when the virtual cursor pans past the top / bottom edge, so one drag
  /// can extend the selection through the whole scrollback.
  final void Function(int lineDelta) onScroll;

  final double fontSize;
  final EdgeInsets padding;

  @override
  State<TerminalCopyOverlay> createState() => TerminalCopyOverlayState();
}

class TerminalCopyOverlayState extends State<TerminalCopyOverlay> {
  /// Viewport-relative cell position of the virtual cursor (0..cols-1,
  /// 0..rows-1). Kept viewport-relative rather than buffer-absolute so a
  /// scroll underneath the overlay (shell output) doesn't strand it.
  int _cursorX = 0;
  int _cursorY = 0;

  /// Sub-cell accumulator — the gesture stream delivers fractional pixels
  /// per frame; the cursor only advances when the accumulator crosses a
  /// full cell width / height, so it never jitters through a cell when the
  /// finger barely moves.
  double _pxX = 0;
  double _pxY = 0;

  /// Selection anchor in *absolute* grid-line coordinates (row includes the
  /// scroll offset at the moment it was set). Null before the user taps
  /// "Set anchor" in the copy-mode bar row.
  int? _anchorCol;
  int? _anchorRowAbs;

  Size? _cellSize;
  double? _measuredFontSize;

  @override
  void initState() {
    super.initState();
    final frame = widget.snapshotProvider();
    // Start the cursor under the engine cursor when it is on-screen,
    // otherwise centre it. `frame.cursor.row` is viewport-relative.
    final cursorRow = frame.cursor.row;
    if (cursorRow >= 0 && cursorRow < frame.rows) {
      _cursorX = frame.cursor.col.clamp(0, _maxX(frame));
      _cursorY = cursorRow;
    } else {
      _cursorX = (frame.cols ~/ 2).clamp(0, _maxX(frame));
      _cursorY = (frame.rows ~/ 2).clamp(0, _maxY(frame));
    }
    widget.onClearSelection();
  }

  @override
  void dispose() {
    widget.onClearSelection();
    super.dispose();
  }

  int _maxX(rust_terminal.TerminalFrame frame) =>
      frame.cols > 0 ? frame.cols.toInt() - 1 : 0;
  int _maxY(rust_terminal.TerminalFrame frame) =>
      frame.rows > 0 ? frame.rows.toInt() - 1 : 0;

  Size _measureCellSize() {
    if (_cellSize != null && _measuredFontSize == widget.fontSize) {
      return _cellSize!;
    }
    _cellSize = measureMonoCell(fontSize: widget.fontSize);
    _measuredFontSize = widget.fontSize;
    return _cellSize!;
  }

  /// Consume [delta] pixels of finger movement, advance the cursor by the
  /// whole-cell remainder, and update the live selection. Called by the
  /// host when a single-pointer drag is in flight.
  ///
  /// Horizontal overflow rolls onto the next row (and back on negative dx)
  /// so a soft-wrapped line can be crossed in one continuous drag. Vertical
  /// overflow past the top / bottom edge scrolls the engine viewport by the
  /// overflow cells via [onScroll] — a single drag can extend the selection
  /// through the entire scrollback.
  void onCursorPan(Offset delta) {
    final cell = _measureCellSize();
    if (cell.width <= 0 || cell.height <= 0) return;
    _pxX += delta.dx;
    _pxY += delta.dy;
    final dx = _pxX ~/ cell.width;
    final dy = _pxY ~/ cell.height;
    if (dx == 0 && dy == 0) return;
    _pxX -= dx * cell.width;
    _pxY -= dy * cell.height;

    final frame = widget.snapshotProvider();
    final cols = frame.cols.toInt();
    final viewMaxY = _maxY(frame);
    if (cols <= 0) return;

    // Linearise into row-major cell indices so a horizontal overflow rolls
    // to the next row instead of clamping at the right edge. Dart's `~/`
    // truncates toward zero (wrong for negatives — we want floor), so the
    // negative branch uses ceil(abs/cols) and flips the sign.
    final combined = _cursorY * cols + _cursorX + dx + dy * cols;
    int newY;
    final int newX;
    if (combined >= 0) {
      newY = combined ~/ cols;
      newX = combined - newY * cols;
    } else {
      final abs = -combined;
      newY = -((abs + cols - 1) ~/ cols);
      newX = combined - newY * cols;
    }

    int scrollOverflowCells = 0;
    if (newY < 0) {
      scrollOverflowCells = newY; // negative → scroll up into scrollback
      newY = 0;
    } else if (newY > viewMaxY) {
      scrollOverflowCells = newY - viewMaxY; // positive → toward live bottom
      newY = viewMaxY;
    }
    if (scrollOverflowCells != 0) {
      // `onScroll` is positive-up; a cursor moving down past the bottom
      // (positive overflow) should scroll the viewport toward the live
      // screen (negative line delta), and vice versa.
      widget.onScroll(-scrollOverflowCells);
    }
    setState(() {
      _cursorX = newX.clamp(0, cols - 1);
      _cursorY = newY;
      _syncSelection(frame);
    });
  }

  /// Drop the selection anchor at the current cursor cell. No-op once an
  /// anchor exists — subsequent pans extend the existing selection so the
  /// user can lift + re-touch without losing progress.
  void onAnchorDown() {
    if (_anchorCol != null) return;
    final frame = widget.snapshotProvider();
    _anchorCol = _cursorX;
    _anchorRowAbs = _absoluteRow(_cursorY, frame);
    _syncSelection(frame);
  }

  /// Map a viewport row to an absolute grid line. The engine's snapshot
  /// adds `displayOffset` to map a native line to a viewport row, so the
  /// inverse subtracts it — the same mapping `pointerToCell` uses on the
  /// desktop grid.
  int _absoluteRow(int viewportRow, rust_terminal.TerminalFrame frame) =>
      viewportRow - frame.displayOffset.toInt();

  void _syncSelection(rust_terminal.TerminalFrame frame) {
    final ac = _anchorCol;
    final ar = _anchorRowAbs;
    if (ac == null || ar == null) return;
    widget.onSetSelection(ar, ac, _absoluteRow(_cursorY, frame), _cursorX);
  }

  /// True after the first [onAnchorDown] — surfaced so the bar can swap
  /// between "tap to start" and "tap to extend" hint copy.
  bool get anchorSet => _anchorCol != null;

  @override
  Widget build(BuildContext context) {
    final cell = _measureCellSize();
    final x = _cursorX * cell.width + widget.padding.left;
    final y = _cursorY * cell.height + widget.padding.top;
    // Cursor marker only. The hint + Copy / Cancel toolbar lives in the
    // SshKeyboardBar's copy-mode row (stable-height swap), not over the
    // terminal rows. IgnorePointer so the enclosing Listener keeps reading
    // cursor-pan deltas through this overlay.
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
