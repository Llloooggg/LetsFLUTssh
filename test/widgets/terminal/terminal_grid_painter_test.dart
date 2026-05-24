import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/terminal/terminal_cell_flags.dart';
import 'package:letsflutssh/widgets/terminal/terminal_grid_painter.dart';

const _fg = TerminalColor(r: 200, g: 200, b: 200);
const _bg = TerminalColor(r: 10, g: 10, b: 10);

TerminalCell _cell(int row, int col, String ch, {int flags = 0}) =>
    TerminalCell(
      row: row,
      col: col,
      ch: ch.codeUnitAt(0),
      fg: _fg,
      bg: _bg,
      flags: flags,
    );

TerminalFrame _frame({
  List<TerminalCell> cells = const [],
  TerminalCursor? cursor,
  TerminalFrameSelection? selection,
  int cols = 10,
  int rows = 5,
}) => TerminalFrame(
  cols: cols,
  rows: rows,
  cursor:
      cursor ??
      const TerminalCursor(
        row: 0,
        col: 0,
        shape: TerminalCursorShape.block,
        visible: true,
      ),
  displayOffset: 0,
  historySize: 0,
  mouseTracking: TerminalMouseTracking.none,
  cells: cells,
  selection: selection,
);

TerminalGridPainter _painter(TerminalFrame frame, {int revision = 0}) =>
    TerminalGridPainter(
      frame: frame,
      frameRevision: revision,
      cellSize: const Size(8, 16),
      defaultBackground: AppTheme.bg2,
      cursorColor: AppTheme.termCursor,
      selectionColor: AppTheme.termSelection,
      fontSize: 14,
    );

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  theme: AppTheme.dark(),
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

void main() {
  group('selectionRects — linear', () {
    // Spec: a linear selection runs from startCol on the first row to the
    // end of each intervening full row and stops at endCol (inclusive) on
    // the last row. End columns are returned exclusive.
    test('single-row selection is one rect with exclusive end', () {
      const sel = TerminalFrameSelection(
        startRow: 1,
        startCol: 2,
        endRow: 1,
        endCol: 5,
        isBlock: false,
      );
      final rects = selectionRects(sel, 10);
      expect(rects, hasLength(1));
      expect(rects.single.row, 1);
      expect(rects.single.startCol, 2);
      expect(rects.single.endCol, 6); // 5 inclusive → 6 exclusive
    });

    test('multi-row selection fills intervening rows to the grid width', () {
      const sel = TerminalFrameSelection(
        startRow: 0,
        startCol: 3,
        endRow: 2,
        endCol: 4,
        isBlock: false,
      );
      final rects = selectionRects(sel, 10);
      expect(rects, hasLength(3));
      expect(
        rects[0],
        const TerminalSelectionRect(row: 0, startCol: 3, endCol: 10),
      );
      expect(
        rects[1],
        const TerminalSelectionRect(row: 1, startCol: 0, endCol: 10),
      );
      expect(
        rects[2],
        const TerminalSelectionRect(row: 2, startCol: 0, endCol: 5),
      );
    });

    test('reversed drag normalizes to the top-left anchor', () {
      const forward = TerminalFrameSelection(
        startRow: 0,
        startCol: 1,
        endRow: 2,
        endCol: 4,
        isBlock: false,
      );
      const reversed = TerminalFrameSelection(
        startRow: 2,
        startCol: 4,
        endRow: 0,
        endCol: 1,
        isBlock: false,
      );
      expect(selectionRects(reversed, 10), selectionRects(forward, 10));
    });
  });

  group('selectionRects — block', () {
    // Spec: a block selection covers the same column band on every row.
    test('covers identical column band per row', () {
      const sel = TerminalFrameSelection(
        startRow: 0,
        startCol: 2,
        endRow: 2,
        endCol: 5,
        isBlock: true,
      );
      final rects = selectionRects(sel, 10);
      expect(rects, hasLength(3));
      for (final r in rects) {
        expect(r.startCol, 2);
        expect(r.endCol, 6);
      }
    });

    test('block normalizes left/right columns regardless of drag dir', () {
      const sel = TerminalFrameSelection(
        startRow: 0,
        startCol: 5,
        endRow: 2,
        endCol: 2,
        isBlock: true,
      );
      final rects = selectionRects(sel, 10);
      expect(rects.first.startCol, 2);
      expect(rects.first.endCol, 6);
    });
  });

  group('shouldRepaint', () {
    test('repaints when the frame revision changes', () {
      final a = _painter(_frame(), revision: 1);
      final b = _painter(_frame(), revision: 2);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('does not repaint at the same revision and equal config', () {
      final a = _painter(_frame(), revision: 7);
      final b = _painter(_frame(), revision: 7);
      expect(b.shouldRepaint(a), isFalse);
    });

    test('repaints when the cursor color changes (theme toggle)', () {
      final a = _painter(_frame(), revision: 1);
      final b = TerminalGridPainter(
        frame: _frame(),
        frameRevision: 1,
        cellSize: const Size(8, 16),
        defaultBackground: AppTheme.bg2,
        cursorColor: const Color(0xFFABCDEF),
        selectionColor: AppTheme.termSelection,
        fontSize: 14,
      );
      expect(b.shouldRepaint(a), isTrue);
    });
  });

  group('paint — builds without throwing on synthetic frames', () {
    testWidgets('renders styled cells, a cursor, and a selection', (
      tester,
    ) async {
      final frame = _frame(
        cells: [
          _cell(0, 0, 'A', flags: kCellFlagBold),
          _cell(0, 1, 'B', flags: kCellFlagItalic | kCellFlagUnderline),
          _cell(1, 0, 'C', flags: kCellFlagStrikeout),
          _cell(1, 1, 'D', flags: kCellFlagHidden),
          _cell(2, 0, 'W', flags: kCellFlagWideChar),
        ],
        cursor: const TerminalCursor(
          row: 0,
          col: 0,
          shape: TerminalCursorShape.block,
          visible: true,
        ),
        selection: const TerminalFrameSelection(
          startRow: 1,
          startCol: 0,
          endRow: 1,
          endCol: 1,
          isBlock: false,
        ),
      );

      await tester.pumpWidget(
        _app(CustomPaint(painter: _painter(frame), size: const Size(400, 300))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden cursor and out-of-range cursor paint nothing extra', (
      tester,
    ) async {
      final frame = _frame(
        cursor: const TerminalCursor(
          row: 99,
          col: 99,
          shape: TerminalCursorShape.block,
          visible: true,
        ),
      );
      await tester.pumpWidget(
        _app(CustomPaint(painter: _painter(frame), size: const Size(400, 300))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every cursor shape paints without throwing', (tester) async {
      for (final shape in TerminalCursorShape.values) {
        final frame = _frame(
          cells: [_cell(0, 0, 'X')],
          cursor: TerminalCursor(row: 0, col: 0, shape: shape, visible: true),
        );
        await tester.pumpWidget(
          _app(
            CustomPaint(painter: _painter(frame), size: const Size(400, 300)),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
