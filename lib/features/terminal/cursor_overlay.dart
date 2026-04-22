import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';

/// Overlay that paints the character under the block cursor with an inverted
/// color so it stays readable.  xterm-flutter draws the cursor as a solid
/// opaque rectangle **on top** of the text — this widget re-draws just that
/// one character with [AppTheme.bg2] (background) as the text color, giving
/// the classic "inverted cursor" look without forking the package.
///
/// Place inside a [Stack] on top of [TerminalView] with identical sizing.
///
/// ### Line-height invariant
///
/// xterm's [TerminalStyle] defaults to `height: 1.2` (line_height multiplier)
/// and the internal painter multiplies the ParagraphStyle by that value when
/// measuring cell size. Our overlay measures cells independently to place the
/// inverted-colour glyph, so the measurement must use the same multiplier —
/// otherwise the cell row stride drifts by ~20 % and the painted character
/// lands a couple of rows off from the real cursor for every scroll. Same
/// reason the mobile [TerminalCopyOverlay] applies [kTerminalLineHeight] to
/// its virtual-cursor marker + selection anchor math.
const double kTerminalLineHeight = 1.2;

class CursorTextOverlay extends StatefulWidget {
  const CursorTextOverlay({
    super.key,
    required this.terminal,
    required this.fontSize,
    this.fontFamily = AppFonts.monoFamily,
    this.fontFamilyFallback = AppFonts.monoFallback,
    this.padding = const EdgeInsets.all(4),
  });

  final Terminal terminal;
  final double fontSize;
  final String fontFamily;
  final List<String> fontFamilyFallback;
  final EdgeInsets padding;

  @override
  State<CursorTextOverlay> createState() => _CursorTextOverlayState();
}

class _CursorTextOverlayState extends State<CursorTextOverlay> {
  final _repaint = ValueNotifier<int>(0);

  void _onTerminalChanged() => _repaint.value++;

  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_onTerminalChanged);
  }

  @override
  void didUpdateWidget(CursorTextOverlay old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      old.terminal.removeListener(_onTerminalChanged);
      widget.terminal.addListener(_onTerminalChanged);
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalChanged);
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CursorCharPainter(
          repaint: _repaint,
          terminal: widget.terminal,
          fontSize: widget.fontSize,
          fontFamily: widget.fontFamily,
          fontFamilyFallback: widget.fontFamilyFallback,
          padding: widget.padding,
        ),
      ),
    );
  }
}

class _CursorCharPainter extends CustomPainter {
  _CursorCharPainter({
    required ValueNotifier<int> repaint,
    required this.terminal,
    required this.fontSize,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.padding,
  }) : super(repaint: repaint);

  final Terminal terminal;
  final double fontSize;
  final String fontFamily;
  final List<String> fontFamilyFallback;
  final EdgeInsets padding;

  Size? _cellSize;
  double? _cachedFontSize;

  /// Measure cell size the same way xterm does: lay out "mmmmmmmmmm" with
  /// the matching line-height multiplier and divide by 10 for width. The
  /// [kTerminalLineHeight] multiplier is applied on the [ui.ParagraphStyle]
  /// — xterm passes it via `ParagraphStyle.height`, which is how its
  /// painter lands cell rows at `row * (fontSize * 1.2)` rather than raw
  /// ascent+descent. Drop the multiplier here and every cursor paint lands
  /// ~20 % higher than the real glyph.
  Size _measureCellSize() {
    if (_cellSize != null && _cachedFontSize == fontSize) return _cellSize!;

    final style = ui.TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      height: kTerminalLineHeight,
    );
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(height: kTerminalLineHeight))
          ..pushStyle(style)
          ..addText('mmmmmmmmmm');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    _cellSize = Size(paragraph.maxIntrinsicWidth / 10, paragraph.height);
    _cachedFontSize = fontSize;
    paragraph.dispose();
    return _cellSize!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final buffer = terminal.buffer;
    final cursorX = buffer.cursorX;
    final cursorY = buffer.absoluteCursorY;

    if (cursorY >= buffer.lines.length) return;
    final line = buffer.lines[cursorY];
    if (cursorX >= line.length) return;

    final cellData = CellData.empty();
    line.getCellData(cursorX, cellData);

    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final cell = _measureCellSize();

    // The visible viewport starts at (totalLines - viewHeight).
    // absoluteCursorY is relative to the entire buffer.
    final viewStart = buffer.lines.length - buffer.viewHeight;
    final visibleRow = cursorY - viewStart;
    if (visibleRow < 0 || visibleRow >= buffer.viewHeight) return;

    final x = cursorX * cell.width + padding.left;
    final y = visibleRow * cell.height + padding.top;

    // Build inverted-color character: use the terminal background as text.
    // The line-height multiplier must match xterm's painter — otherwise the
    // glyph baseline slides up within the cell and the inverted char lands
    // above the real glyph it is meant to cover.
    final textColor = AppTheme.bg2;
    final style = ui.TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      height: kTerminalLineHeight,
      color: textColor,
    );
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(height: kTerminalLineHeight))
          ..pushStyle(style)
          ..addText(String.fromCharCode(charCode));
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    canvas.drawParagraph(paragraph, Offset(x, y));
    paragraph.dispose();
  }

  @override
  bool shouldRepaint(_CursorCharPainter old) =>
      terminal != old.terminal ||
      fontSize != old.fontSize ||
      fontFamily != old.fontFamily ||
      !listEquals(fontFamilyFallback, old.fontFamilyFallback);
}
