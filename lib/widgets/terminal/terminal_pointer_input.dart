import 'package:flutter/painting.dart';

import '../../src/rust/api/terminal.dart';

/// Pure pointer-input helpers for the terminal grid: pixel→cell mapping,
/// the routing decision (mouse report vs local selection vs scroll), and
/// the search highlight-range geometry. Kept free of any live
/// `TerminalSession` / widget so the coordinate math and gating are
/// unit-testable without an FFI engine — the grid view wires the side
/// effects, this file owns the arithmetic.

/// A cell coordinate in two frames of reference. `viewportRow` is `0` at
/// the top visible line (what the painter and a mouse report use);
/// `absoluteRow` subtracts the scroll offset so it indexes the engine's
/// grid where the live screen starts at `0` and scrollback is negative
/// (what [TerminalSession.setSelection] / a re-painted selection use).
class TerminalCellCoord {
  const TerminalCellCoord({
    required this.viewportRow,
    required this.col,
    required this.absoluteRow,
  });

  final int viewportRow;
  final int col;
  final int absoluteRow;

  @override
  bool operator ==(Object other) =>
      other is TerminalCellCoord &&
      viewportRow == other.viewportRow &&
      col == other.col &&
      absoluteRow == other.absoluteRow;

  @override
  int get hashCode => Object.hash(viewportRow, col, absoluteRow);
}

/// Map a local pointer offset (in the grid view's coordinate space) to a
/// cell, accounting for the content padding, the per-cell pitch, and the
/// current scroll `displayOffset`. Columns/rows clamp into `0..cols-1` /
/// `0..rows-1` so a drag past the edge selects the last cell rather than
/// running off the grid. The absolute row subtracts `displayOffset`
/// because the engine's snapshot adds it to map a native line to a
/// viewport row — inverting it recovers the absolute grid line the
/// selection API expects.
TerminalCellCoord pointerToCell({
  required Offset localOffset,
  required EdgeInsets padding,
  required Size cellSize,
  required int cols,
  required int rows,
  required int displayOffset,
}) {
  final localX = localOffset.dx - padding.left;
  final localY = localOffset.dy - padding.top;
  final rawCol = cellSize.width <= 0 ? 0 : (localX / cellSize.width).floor();
  final rawRow = cellSize.height <= 0 ? 0 : (localY / cellSize.height).floor();
  final col = rawCol.clamp(0, cols > 0 ? cols - 1 : 0);
  final viewportRow = rawRow.clamp(0, rows > 0 ? rows - 1 : 0);
  return TerminalCellCoord(
    viewportRow: viewportRow,
    col: col,
    absoluteRow: viewportRow - displayOffset,
  );
}

/// The maximum gap between consecutive pointer-downs that still counts as
/// part of the same multi-tap run (single → double → triple). Flutter's own
/// `kDoubleTapTimeout` is 300 ms; this matches the manual double-tap windows
/// used elsewhere in the app (session tree, file rows) which the
/// `GestureDetector.onDoubleTap` delay-and-Draggable-conflict made
/// unsuitable to reuse here.
const Duration kTerminalMultiTapWindow = Duration(milliseconds: 400);

/// Fold a pointer-down into the running tap count for word/line selection.
///
/// A press extends the run (1 → 2 → 3, capped at 3 = triple-click) only when
/// it lands on the same cell as the previous press AND within
/// [kTerminalMultiTapWindow] of it; otherwise the run restarts at `1`. The
/// cap means a fourth quick click on the same cell stays a triple (whole
/// line) rather than wrapping back to a single — the standard terminal UX.
/// Pure so the tap-count state machine is unit-testable without timers or a
/// live pointer; the grid view supplies the clock and the previous press.
int nextTapCount({
  required int previousCount,
  required TerminalCellCoord? previousCell,
  required Duration sincePrevious,
  required TerminalCellCoord currentCell,
}) {
  final continues =
      previousCell == currentCell && sincePrevious <= kTerminalMultiTapWindow;
  if (!continues) return 1;
  if (previousCount >= 3) return 3;
  return previousCount + 1;
}

/// Map a multi-tap count to the selection geometry it drives: 1 = character
/// (Simple) drag, 2 = word (Semantic, double-click), 3 = whole line (Lines,
/// triple-click). Counts above 3 are clamped to Lines by [nextTapCount], so
/// any value ≥ 3 here is a line selection. Block selection is not a tap
/// gesture (it is modifier-driven) and is therefore not produced here.
TerminalSelectionKind selectionKindForTapCount(int tapCount) {
  switch (tapCount) {
    case 2:
      return TerminalSelectionKind.semantic;
    case 1:
      return TerminalSelectionKind.simple;
    default:
      return TerminalSelectionKind.lines;
  }
}

/// What a pointer gesture should do, decided from the program's
/// mouse-tracking level and the live modifier state.
enum PointerRouting {
  /// Send the gesture to the program as a mouse report.
  report,

  /// Handle the gesture locally as text selection.
  select,

  /// Handle a wheel gesture locally as scrollback scroll.
  scroll,
}

/// Decide how to route a press / drag gesture. When the program enabled
/// mouse tracking the gesture is a [PointerRouting.report] — UNLESS Shift
/// is held, the xterm override that always forces local text selection so
/// the user can still copy out of a full-screen mouse-tracking program
/// (vim, htop). With no tracking the gesture is always local selection.
PointerRouting routePointerGesture({
  required TerminalMouseTracking tracking,
  required bool shiftPressed,
}) {
  if (tracking == TerminalMouseTracking.none) return PointerRouting.select;
  if (shiftPressed) return PointerRouting.select;
  return PointerRouting.report;
}

/// Decide how to route a wheel gesture. Click-only tracking
/// ([TerminalMouseTracking.click]) does NOT report motion/wheel under the
/// alt-screen-less case, but xterm still forwards the wheel as buttons
/// 64/65 whenever any tracking is on — so a wheel reports under every
/// tracking level. Shift forces local scrollback scroll (the same
/// selection-override convention, applied to the wheel). With no tracking
/// the wheel always scrolls scrollback locally.
PointerRouting routeWheelGesture({
  required TerminalMouseTracking tracking,
  required bool shiftPressed,
}) {
  if (tracking == TerminalMouseTracking.none) return PointerRouting.scroll;
  if (shiftPressed) return PointerRouting.scroll;
  return PointerRouting.report;
}

/// One highlighted match span on a single viewport row, in viewport-cell
/// coordinates with an exclusive end column — the same shape the painter's
/// selection rects use, so the highlight overlay reuses the cell→pixel
/// mapping.
class TerminalHighlightRect {
  const TerminalHighlightRect({
    required this.row,
    required this.startCol,
    required this.endCol,
  });

  final int row;
  final int startCol;

  /// Exclusive end column.
  final int endCol;

  @override
  bool operator ==(Object other) =>
      other is TerminalHighlightRect &&
      row == other.row &&
      startCol == other.startCol &&
      endCol == other.endCol;

  @override
  int get hashCode => Object.hash(row, startCol, endCol);
}

/// Project a list of search matches (in absolute grid-line coordinates,
/// negative = scrollback) onto the current viewport, dropping matches that
/// fall outside the visible rows. `displayOffset` shifts an absolute line
/// into a viewport row (`viewportRow = matchLine + displayOffset`), the
/// inverse of [pointerToCell]'s mapping. The match's `endCol` is inclusive
/// in the engine's coordinates; the rect's is exclusive, so it is bumped
/// by one. Pure so the highlight geometry is unit-testable without a
/// canvas.
List<TerminalHighlightRect> highlightRectsForMatches({
  required List<TerminalMatch> matches,
  required int displayOffset,
  required int rows,
}) {
  final rects = <TerminalHighlightRect>[];
  for (final match in matches) {
    final viewportRow = match.line + displayOffset;
    if (viewportRow < 0 || viewportRow >= rows) continue;
    rects.add(
      TerminalHighlightRect(
        row: viewportRow,
        startCol: match.startCol,
        endCol: match.endCol + 1,
      ),
    );
  }
  return rects;
}

/// The scroll delta (in lines, positive = up into scrollback) needed to
/// bring an absolute match `line` into view, or `0` when it is already
/// visible. A match above the viewport (`viewportRow < 0`) scrolls up by
/// the shortfall; one below (`>= rows`) scrolls down. Used by next/prev
/// navigation so the selected match is always on screen.
int scrollDeltaToRevealLine({
  required int matchLine,
  required int displayOffset,
  required int rows,
}) {
  final viewportRow = matchLine + displayOffset;
  if (viewportRow < 0) return -viewportRow;
  if (viewportRow >= rows) return -(viewportRow - rows + 1);
  return 0;
}
