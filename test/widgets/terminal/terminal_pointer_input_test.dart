import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/widgets/terminal/terminal_pointer_input.dart';

const _cell = Size(8, 16);
const _padding = EdgeInsets.all(4);

void main() {
  group('pointerToCell', () {
    // Spec: a pixel offset maps to the cell whose box contains it, after
    // subtracting the content padding and dividing by the cell pitch. The
    // absolute row subtracts the scroll offset (the inverse of the
    // snapshot's native-line → viewport-row mapping).
    test('maps a padded offset to the containing cell', () {
      // (4,4) is the top-left of cell (0,0) after padding.
      final c = pointerToCell(
        localOffset: const Offset(4 + 8 * 3 + 1, 4 + 16 * 2 + 1),
        padding: _padding,
        cellSize: _cell,
        cols: 80,
        rows: 24,
        displayOffset: 0,
      );
      expect(c.col, 3);
      expect(c.viewportRow, 2);
      expect(c.absoluteRow, 2);
    });

    test('subtracts the display offset for the absolute row', () {
      // Scrolled up 5 lines: viewport row 2 is absolute line 2 - 5 = -3
      // (in scrollback).
      final c = pointerToCell(
        localOffset: const Offset(4, 4 + 16 * 2),
        padding: _padding,
        cellSize: _cell,
        cols: 80,
        rows: 24,
        displayOffset: 5,
      );
      expect(c.viewportRow, 2);
      expect(c.absoluteRow, -3);
    });

    test('clamps a drag past the right/bottom edge to the last cell', () {
      final c = pointerToCell(
        localOffset: const Offset(100000, 100000),
        padding: _padding,
        cellSize: _cell,
        cols: 80,
        rows: 24,
        displayOffset: 0,
      );
      expect(c.col, 79);
      expect(c.viewportRow, 23);
    });

    test('clamps a drag above/left of the grid to the first cell', () {
      final c = pointerToCell(
        localOffset: const Offset(-50, -50),
        padding: _padding,
        cellSize: _cell,
        cols: 80,
        rows: 24,
        displayOffset: 0,
      );
      expect(c.col, 0);
      expect(c.viewportRow, 0);
    });
  });

  group('routePointerGesture', () {
    // Spec: with no tracking the pointer is always local selection. With
    // tracking on, a press reports to the program — unless Shift forces
    // local selection (the xterm copy-out override).
    test('no tracking → local selection', () {
      expect(
        routePointerGesture(
          tracking: TerminalMouseTracking.none,
          shiftPressed: false,
        ),
        PointerRouting.select,
      );
    });

    test('tracking on, no shift → report', () {
      expect(
        routePointerGesture(
          tracking: TerminalMouseTracking.buttonEvent,
          shiftPressed: false,
        ),
        PointerRouting.report,
      );
    });

    test('tracking on, shift held → local selection override', () {
      expect(
        routePointerGesture(
          tracking: TerminalMouseTracking.anyMotion,
          shiftPressed: true,
        ),
        PointerRouting.select,
      );
    });
  });

  group('routeWheelGesture', () {
    // Spec: no tracking → local scrollback scroll. Tracking on (any level)
    // → report the wheel to the program, unless Shift forces local scroll.
    test('no tracking → local scroll', () {
      expect(
        routeWheelGesture(
          tracking: TerminalMouseTracking.none,
          shiftPressed: false,
        ),
        PointerRouting.scroll,
      );
    });

    test('click-only tracking still reports the wheel', () {
      expect(
        routeWheelGesture(
          tracking: TerminalMouseTracking.click,
          shiftPressed: false,
        ),
        PointerRouting.report,
      );
    });

    test('tracking on, shift held → local scroll override', () {
      expect(
        routeWheelGesture(
          tracking: TerminalMouseTracking.click,
          shiftPressed: true,
        ),
        PointerRouting.scroll,
      );
    });
  });

  group('highlightRectsForMatches', () {
    // Spec: a match at absolute line L projects to viewport row
    // L + displayOffset, with an exclusive end column (endCol + 1).
    // Matches off the viewport are dropped.
    test('projects an on-screen match with exclusive end column', () {
      final rects = highlightRectsForMatches(
        matches: const [TerminalMatch(line: 2, startCol: 1, endCol: 4)],
        displayOffset: 0,
        rows: 24,
      );
      expect(rects, hasLength(1));
      expect(rects.single.row, 2);
      expect(rects.single.startCol, 1);
      expect(rects.single.endCol, 5); // inclusive 4 → exclusive 5
    });

    test('shifts a scrollback match into the viewport via displayOffset', () {
      // Absolute line -3 with the view scrolled up 5 → viewport row 2.
      final rects = highlightRectsForMatches(
        matches: const [TerminalMatch(line: -3, startCol: 0, endCol: 0)],
        displayOffset: 5,
        rows: 24,
      );
      expect(rects.single.row, 2);
    });

    test('drops matches above or below the viewport', () {
      final rects = highlightRectsForMatches(
        matches: const [
          TerminalMatch(line: -10, startCol: 0, endCol: 0), // above
          TerminalMatch(line: 100, startCol: 0, endCol: 0), // below
        ],
        displayOffset: 0,
        rows: 24,
      );
      expect(rects, isEmpty);
    });
  });

  group('scrollDeltaToRevealLine', () {
    // Spec: a visible match needs no scroll. A match above the viewport
    // scrolls up (positive delta = into scrollback) by the shortfall; one
    // below scrolls down (negative).
    test('visible match → no scroll', () {
      expect(
        scrollDeltaToRevealLine(matchLine: 3, displayOffset: 0, rows: 24),
        0,
      );
    });

    test('match above the top scrolls up by the shortfall', () {
      // line -2, offset 0 → viewport row -2 → need +2 to bring to row 0.
      expect(
        scrollDeltaToRevealLine(matchLine: -2, displayOffset: 0, rows: 24),
        2,
      );
    });

    test('match below the bottom scrolls down', () {
      // line 30, offset 0, rows 24 → viewport row 30 → need -(30-24+1) = -7.
      expect(
        scrollDeltaToRevealLine(matchLine: 30, displayOffset: 0, rows: 24),
        -7,
      );
    });
  });

  group('nextTapCount', () {
    const a = TerminalCellCoord(viewportRow: 1, col: 2, absoluteRow: 1);
    const b = TerminalCellCoord(viewportRow: 3, col: 5, absoluteRow: 3);

    // Spec: a press on the same cell within the window extends the run
    // (1 → 2 → 3); a press on a different cell, or after the window, restarts
    // at 1; the run caps at 3 so a fourth fast click stays a triple.
    test('same cell within window extends the run', () {
      expect(
        nextTapCount(
          previousCount: 1,
          previousCell: a,
          sincePrevious: const Duration(milliseconds: 100),
          currentCell: a,
        ),
        2,
      );
      expect(
        nextTapCount(
          previousCount: 2,
          previousCell: a,
          sincePrevious: const Duration(milliseconds: 100),
          currentCell: a,
        ),
        3,
      );
    });

    test('a different cell restarts the run at 1', () {
      expect(
        nextTapCount(
          previousCount: 2,
          previousCell: a,
          sincePrevious: const Duration(milliseconds: 100),
          currentCell: b,
        ),
        1,
      );
    });

    test('a press after the window restarts the run at 1', () {
      expect(
        nextTapCount(
          previousCount: 2,
          previousCell: a,
          sincePrevious:
              kTerminalMultiTapWindow + const Duration(milliseconds: 1),
          currentCell: a,
        ),
        1,
      );
    });

    test('the run caps at 3 (a fourth fast click stays a triple)', () {
      expect(
        nextTapCount(
          previousCount: 3,
          previousCell: a,
          sincePrevious: const Duration(milliseconds: 100),
          currentCell: a,
        ),
        3,
      );
    });

    test('a first-ever press (no previous cell) is a single', () {
      expect(
        nextTapCount(
          previousCount: 0,
          previousCell: null,
          sincePrevious: Duration.zero,
          currentCell: a,
        ),
        1,
      );
    });
  });

  group('selectionKindForTapCount', () {
    // Spec: 1 = character (Simple), 2 = word (Semantic), 3+ = line (Lines).
    test('maps tap counts to selection geometry', () {
      expect(selectionKindForTapCount(1), TerminalSelectionKind.simple);
      expect(selectionKindForTapCount(2), TerminalSelectionKind.semantic);
      expect(selectionKindForTapCount(3), TerminalSelectionKind.lines);
    });
  });
}
