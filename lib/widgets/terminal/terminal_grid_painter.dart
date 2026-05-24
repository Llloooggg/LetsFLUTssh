import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../src/rust/api/terminal.dart';
import '../../theme/app_theme.dart';
import 'terminal_cell_flags.dart';
import 'terminal_cell_metrics.dart';
import 'terminal_pointer_input.dart';

/// Paints one [TerminalFrame] onto a cell grid.
///
/// The frame is **sparse**: only non-blank cells are present (the Rust
/// engine omits blank default-background cells), so the painter clears
/// the whole surface to the default background once, then overlays each
/// cell's background rect (skipped when it equals the default bg) and
/// glyph. Cell positions are reconstructed from each cell's `row`/`col`
/// in viewport coordinates (`0` = top visible line) — see
/// `lfs_core::terminal::frame` for the coordinate contract.
///
/// Color is resolved Rust-side: `INVERSE`/`DIM` are already folded into
/// the cell's `fg`/`bg`, so the painter paints those concrete RGB
/// directly. The remaining attribute bits (bold, italic, underline,
/// strikeout, hidden, wide) are decoded via [TerminalCellFlags]; see
/// `terminal_cell_flags.dart` for the bit layout and its Rust source.
class TerminalGridPainter extends CustomPainter {
  TerminalGridPainter({
    required this.frame,
    required this.frameRevision,
    required this.cellSize,
    required this.defaultBackground,
    required this.cursorColor,
    required this.selectionColor,
    required this.fontSize,
    this.fontFamily = AppFonts.monoFamily,
    this.fontFamilyFallback = AppFonts.monoFallback,
    this.padding = EdgeInsets.zero,
    this.searchHighlights = const [],
    this.searchHighlightColor,
    this.activeSearchHighlight,
    this.activeSearchHighlightColor,
    this.showCursor = true,
  });

  final TerminalFrame frame;

  /// Monotonic counter the host bumps on every fresh snapshot. Frames
  /// are value-equal but distinct objects each pull; comparing a
  /// revision is cheaper than a deep `cells` compare and never misses a
  /// change that happens to value-equal a prior frame.
  final int frameRevision;

  final Size cellSize;
  final Color defaultBackground;
  final Color cursorColor;
  final Color selectionColor;
  final double fontSize;
  final String fontFamily;
  final List<String> fontFamilyFallback;
  final EdgeInsets padding;

  /// Search-match highlight spans in viewport-cell coordinates (exclusive
  /// end column). Painted under the glyphs so the matched text stays
  /// legible. Empty when no search is active.
  final List<TerminalHighlightRect> searchHighlights;

  /// Fill color for non-active search matches. Falls back to a translucent
  /// [selectionColor] when null (the search bar always supplies one).
  final Color? searchHighlightColor;

  /// The current match in next/prev navigation, painted in a stronger
  /// color so the user sees which one is focused. Null when no search.
  final TerminalHighlightRect? activeSearchHighlight;

  /// Fill color for the active match. Falls back to [searchHighlightColor].
  final Color? activeSearchHighlightColor;

  /// Whether to paint the block cursor. Read-only surfaces (log viewer,
  /// recording playback, connection progress) pass `false` — they replay a
  /// stream with no live input, so a cursor on the last line is noise, just
  /// as the old read-only view sent `CSI ?25l` to hide it.
  final bool showCursor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCellBackgrounds(canvas);
    _paintSearchHighlights(canvas);
    _paintSelection(canvas);
    _paintGlyphs(canvas);
    _paintCursor(canvas);
  }

  void _paintSearchHighlights(Canvas canvas) {
    if (searchHighlights.isEmpty) return;
    final baseColor = searchHighlightColor ?? selectionColor;
    final activeColor = activeSearchHighlightColor ?? baseColor;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final hl in searchHighlights) {
      paint.color = hl == activeSearchHighlight ? activeColor : baseColor;
      final origin = _cellOrigin(hl.row, hl.startCol);
      final width = (hl.endCol - hl.startCol) * cellSize.width;
      if (width <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(origin.dx, origin.dy, width, cellSize.height),
        paint,
      );
    }
  }

  /// Pixel offset of a cell's top-left corner.
  Offset _cellOrigin(int row, int col) => Offset(
    col * cellSize.width + padding.left,
    row * cellSize.height + padding.top,
  );

  void _paintCellBackgrounds(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final cell in frame.cells) {
      final bg = _color(cell.bg);
      // The surface is already cleared to the default bg by the host's
      // ColoredBox; skip cells that match it to save a fill.
      if (bg == defaultBackground) continue;
      paint.color = bg;
      final origin = _cellOrigin(cell.row, cell.col);
      final width = _columnSpan(cell) * cellSize.width;
      canvas.drawRect(
        Rect.fromLTWH(origin.dx, origin.dy, width, cellSize.height),
        paint,
      );
    }
  }

  void _paintGlyphs(Canvas canvas) {
    for (final cell in frame.cells) {
      final decoded = TerminalCellFlags.fromBits(cell.flags);
      if (decoded.hidden) continue;
      final ch = String.fromCharCode(cell.ch);
      if (ch.trim().isEmpty) continue;
      final paragraph = _buildGlyph(ch, _color(cell.fg), decoded);
      canvas.drawParagraph(paragraph, _cellOrigin(cell.row, cell.col));
      paragraph.dispose();
    }
  }

  /// Build a single-glyph paragraph honoring the decoded attributes. The
  /// paragraph height multiplier matches [kTerminalLineHeight] and the
  /// cell-metric measurement: a mismatch slides the baseline within the
  /// cell so the glyph rides above its background rect.
  ui.Paragraph _buildGlyph(String ch, Color fg, TerminalCellFlags flags) {
    final decorations = <TextDecoration>[
      if (flags.underline) TextDecoration.underline,
      if (flags.strikeout) TextDecoration.lineThrough,
    ];
    final style = ui.TextStyle(
      color: fg,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      height: kTerminalLineHeight,
      fontWeight: flags.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: flags.italic ? FontStyle.italic : FontStyle.normal,
      decoration: decorations.isEmpty
          ? TextDecoration.none
          : TextDecoration.combine(decorations),
      decorationColor: fg,
    );
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(height: kTerminalLineHeight))
          ..pushStyle(style)
          ..addText(ch);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  void _paintSelection(Canvas canvas) {
    final sel = frame.selection;
    if (sel == null) return;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = selectionColor;
    for (final rect in selectionRects(sel, frame.cols)) {
      final origin = _cellOrigin(rect.row, rect.startCol);
      final width = (rect.endCol - rect.startCol) * cellSize.width;
      if (width <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(origin.dx, origin.dy, width, cellSize.height),
        paint,
      );
    }
  }

  void _paintCursor(Canvas canvas) {
    if (!showCursor) return;
    final cursor = frame.cursor;
    if (!cursor.visible || cursor.shape == TerminalCursorShape.hidden) return;
    if (cursor.row < 0 || cursor.row >= frame.rows) return;
    if (cursor.col < 0 || cursor.col >= frame.cols) return;

    final origin = _cellOrigin(cursor.row, cursor.col);
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      cellSize.width,
      cellSize.height,
    );
    _paintCursorShape(canvas, cursor.shape, rect);
    _paintCursorGlyph(canvas, cursor);
  }

  void _paintCursorShape(Canvas canvas, TerminalCursorShape shape, Rect rect) {
    final paint = Paint()..color = cursorColor;
    switch (shape) {
      case TerminalCursorShape.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(rect, paint);
      case TerminalCursorShape.hollowBlock:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(rect.deflate(0.5), paint);
      case TerminalCursorShape.underline:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.bottom - 2, rect.width, 2),
          paint,
        );
      case TerminalCursorShape.beam:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, 2, rect.height),
          paint,
        );
      case TerminalCursorShape.hidden:
        break;
    }
  }

  /// Re-draw the glyph under a filled block cursor in the background
  /// color so it stays legible (the classic inverted-cursor look). Only
  /// the solid block fully covers the glyph; the other shapes leave it
  /// visible, so they skip the redraw.
  void _paintCursorGlyph(Canvas canvas, TerminalCursor cursor) {
    if (cursor.shape != TerminalCursorShape.block) return;
    final under = _cellAt(cursor.row, cursor.col);
    if (under == null) return;
    final decoded = TerminalCellFlags.fromBits(under.flags);
    if (decoded.hidden) return;
    final ch = String.fromCharCode(under.ch);
    if (ch.trim().isEmpty) return;
    final paragraph = _buildGlyph(ch, defaultBackground, decoded);
    canvas.drawParagraph(paragraph, _cellOrigin(cursor.row, cursor.col));
    paragraph.dispose();
  }

  TerminalCell? _cellAt(int row, int col) {
    for (final cell in frame.cells) {
      if (cell.row == row && cell.col == col) return cell;
    }
    return null;
  }

  int _columnSpan(TerminalCell cell) =>
      TerminalCellFlags.fromBits(cell.flags).wide ? 2 : 1;

  Color _color(TerminalColor c) => Color.fromARGB(0xff, c.r, c.g, c.b);

  @override
  bool shouldRepaint(TerminalGridPainter old) =>
      frameRevision != old.frameRevision ||
      cellSize != old.cellSize ||
      fontSize != old.fontSize ||
      defaultBackground != old.defaultBackground ||
      cursorColor != old.cursorColor ||
      showCursor != old.showCursor ||
      selectionColor != old.selectionColor ||
      activeSearchHighlight != old.activeSearchHighlight ||
      !_listEquals(searchHighlights, old.searchHighlights);

  static bool _listEquals(
    List<TerminalHighlightRect> a,
    List<TerminalHighlightRect> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One contiguous run of selected columns on a single viewport row.
class TerminalSelectionRect {
  const TerminalSelectionRect({
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
      other is TerminalSelectionRect &&
      row == other.row &&
      startCol == other.startCol &&
      endCol == other.endCol;

  @override
  int get hashCode => Object.hash(row, startCol, endCol);
}

/// Expand a frame selection into per-row highlight rects. A block
/// selection covers the same column band on every row; a linear
/// selection runs from `startCol` on the first row to the end of each
/// intervening row and stops at `endCol` on the last. End columns are
/// exclusive. Pure so the painter geometry is unit-testable without a
/// canvas.
List<TerminalSelectionRect> selectionRects(
  TerminalFrameSelection sel,
  int cols,
) {
  // Normalize so the start is the top-left anchor regardless of drag
  // direction.
  var topRow = sel.startRow;
  var topCol = sel.startCol;
  var bottomRow = sel.endRow;
  var bottomCol = sel.endCol;
  if (bottomRow < topRow || (bottomRow == topRow && bottomCol < topCol)) {
    topRow = sel.endRow;
    topCol = sel.endCol;
    bottomRow = sel.startRow;
    bottomCol = sel.startCol;
  }

  final rects = <TerminalSelectionRect>[];
  if (sel.isBlock) {
    final left = topCol < bottomCol ? topCol : bottomCol;
    final right = (topCol < bottomCol ? bottomCol : topCol) + 1;
    for (var row = topRow; row <= bottomRow; row++) {
      rects.add(TerminalSelectionRect(row: row, startCol: left, endCol: right));
    }
    return rects;
  }

  for (var row = topRow; row <= bottomRow; row++) {
    final start = row == topRow ? topCol : 0;
    final end = row == bottomRow ? bottomCol + 1 : cols;
    rects.add(TerminalSelectionRect(row: row, startCol: start, endCol: end));
  }
  return rects;
}
