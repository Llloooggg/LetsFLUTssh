import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/terminal/terminal_cell_flags.dart';
import 'package:letsflutssh/widgets/terminal/terminal_grid_painter.dart';
import 'package:letsflutssh/widgets/terminal/terminal_pointer_input.dart';

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

    // Spec: `showCursor: false` is the read-only-surface contract (log
    // viewer, playback, progress). The painter must skip both the cursor
    // rect and the inverted-glyph redraw so the read-only view never
    // shows a phantom block on the last paint.
    testWidgets('showCursor=false suppresses the block cursor paint', (
      tester,
    ) async {
      final frame = _frame(
        cells: [_cell(0, 0, 'X')],
        cursor: const TerminalCursor(
          row: 0,
          col: 0,
          shape: TerminalCursorShape.block,
          visible: true,
        ),
      );
      final p = TerminalGridPainter(
        frame: frame,
        frameRevision: 0,
        cellSize: const Size(8, 16),
        defaultBackground: AppTheme.bg2,
        cursorColor: AppTheme.termCursor,
        selectionColor: AppTheme.termSelection,
        fontSize: 14,
        showCursor: false,
      );
      await tester.pumpWidget(
        _app(CustomPaint(painter: p, size: const Size(400, 300))),
      );
      expect(tester.takeException(), isNull);
    });

    // Spec: a hidden cursor (visible=false OR shape=hidden) skips the
    // cursor paint regardless of the showCursor flag. The grammar comes
    // from `lfs_core::terminal::frame::TerminalCursor`.
    testWidgets('invisible cursor and hidden-shape cursor paint nothing', (
      tester,
    ) async {
      final framesToTry = [
        _frame(
          cells: [_cell(0, 0, 'Y')],
          cursor: const TerminalCursor(
            row: 0,
            col: 0,
            shape: TerminalCursorShape.block,
            visible: false,
          ),
        ),
        _frame(
          cells: [_cell(0, 0, 'Y')],
          cursor: const TerminalCursor(
            row: 0,
            col: 0,
            shape: TerminalCursorShape.hidden,
            visible: true,
          ),
        ),
      ];
      for (final frame in framesToTry) {
        await tester.pumpWidget(
          _app(
            CustomPaint(painter: _painter(frame), size: const Size(400, 300)),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    // Spec: search highlights paint per-row with an exclusive end column.
    // The active highlight uses the activeSearchHighlightColor; the rest
    // use the base highlight color. Zero-width spans (`endCol == startCol`)
    // collapse out so an empty match never paints a stripe.
    testWidgets('search highlights including active + zero-width spans', (
      tester,
    ) async {
      const base = TerminalHighlightRect(row: 0, startCol: 0, endCol: 3);
      const active = TerminalHighlightRect(row: 1, startCol: 2, endCol: 5);
      const empty = TerminalHighlightRect(row: 2, startCol: 4, endCol: 4);
      final frame = _frame(cells: [_cell(0, 0, 'A')]);
      final p = TerminalGridPainter(
        frame: frame,
        frameRevision: 0,
        cellSize: const Size(8, 16),
        defaultBackground: AppTheme.bg2,
        cursorColor: AppTheme.termCursor,
        selectionColor: AppTheme.termSelection,
        fontSize: 14,
        searchHighlights: const [base, active, empty],
        activeSearchHighlight: active,
        searchHighlightColor: const Color(0x44AABBCC),
        activeSearchHighlightColor: const Color(0xFFFF0000),
      );
      await tester.pumpWidget(
        _app(CustomPaint(painter: p, size: const Size(400, 300))),
      );
      expect(tester.takeException(), isNull);
    });

    // Spec: a block selection paints a uniform column band on every
    // covered row; the painter must walk the rects returned by
    // `selectionRects` and render each as a filled rect.
    testWidgets('block selection paints without throwing', (tester) async {
      final frame = _frame(
        cells: [_cell(0, 0, 'A'), _cell(1, 1, 'B'), _cell(2, 2, 'C')],
        selection: const TerminalFrameSelection(
          startRow: 0,
          startCol: 0,
          endRow: 2,
          endCol: 3,
          isBlock: true,
        ),
      );
      await tester.pumpWidget(
        _app(CustomPaint(painter: _painter(frame), size: const Size(400, 300))),
      );
      expect(tester.takeException(), isNull);
    });

    // Spec: cells whose decoded glyph is whitespace are skipped (no
    // paragraph build / draw) so empty padding cells do not pay the
    // paragraph cost. Hidden cells skip glyph paint but keep their bg.
    testWidgets('whitespace-only and hidden cells skip glyph paint', (
      tester,
    ) async {
      final frame = _frame(
        cells: [
          _cell(0, 0, ' '), // whitespace → skip
          _cell(0, 1, 'A', flags: kCellFlagHidden), // hidden → skip glyph
          _cell(0, 2, 'B'), // normal
        ],
      );
      await tester.pumpWidget(
        _app(CustomPaint(painter: _painter(frame), size: const Size(400, 300))),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('shouldRepaint — additional triggers', () {
    // Spec: `shouldRepaint` is the gate that prevents redundant frame
    // builds; changes to selectionColor, defaultBackground, fontSize,
    // cellSize, showCursor, activeSearchHighlight, or the highlights
    // list shape MUST trigger a repaint. Otherwise the user sees stale
    // pixels until something else dirties the canvas.
    TerminalGridPainter make({
      Size cellSize = const Size(8, 16),
      double fontSize = 14,
      Color defaultBackground = const Color(0xFF101010),
      Color cursorColor = const Color(0xFF00FF00),
      Color selectionColor = const Color(0x44FFFFFF),
      bool showCursor = true,
      List<TerminalHighlightRect> highlights = const [],
      TerminalHighlightRect? active,
    }) => TerminalGridPainter(
      frame: _frame(),
      frameRevision: 1,
      cellSize: cellSize,
      defaultBackground: defaultBackground,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      fontSize: fontSize,
      showCursor: showCursor,
      searchHighlights: highlights,
      activeSearchHighlight: active,
    );

    test('repaints when cellSize changes', () {
      final a = make();
      final b = make(cellSize: const Size(10, 20));
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when fontSize changes', () {
      final a = make();
      final b = make(fontSize: 16);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when defaultBackground changes', () {
      final a = make();
      final b = make(defaultBackground: const Color(0xFF202020));
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when selectionColor changes', () {
      final a = make();
      final b = make(selectionColor: const Color(0x88112233));
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when showCursor toggles', () {
      final a = make(showCursor: true);
      final b = make(showCursor: false);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when activeSearchHighlight changes', () {
      const r1 = TerminalHighlightRect(row: 0, startCol: 0, endCol: 1);
      const r2 = TerminalHighlightRect(row: 1, startCol: 0, endCol: 1);
      final a = make(active: r1);
      final b = make(active: r2);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when searchHighlights list contents differ', () {
      const r1 = TerminalHighlightRect(row: 0, startCol: 0, endCol: 1);
      const r2 = TerminalHighlightRect(row: 1, startCol: 0, endCol: 1);
      final a = make(highlights: const [r1]);
      final b = make(highlights: const [r2]);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when searchHighlights list length differs', () {
      const r1 = TerminalHighlightRect(row: 0, startCol: 0, endCol: 1);
      final a = make(highlights: const [r1]);
      final b = make(highlights: const [r1, r1]);
      expect(b.shouldRepaint(a), isTrue);
    });
  });
}
