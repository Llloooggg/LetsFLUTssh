import 'dart:ui' as ui;

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
class CursorTextOverlay extends StatefulWidget {
  const CursorTextOverlay({
    super.key,
    required this.terminal,
    required this.fontSize,
    this.fontFamily = 'JetBrains Mono',
    this.padding = const EdgeInsets.all(4),
  });

  final Terminal terminal;
  final double fontSize;
  final String fontFamily;
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
    required this.padding,
  }) : super(repaint: repaint);

  final Terminal terminal;
  final double fontSize;
  final String fontFamily;
  final EdgeInsets padding;

  Size? _cellSize;
  double? _cachedFontSize;

  /// Measure cell size the same way xterm does: lay out "mmmmmmmmmm" and
  /// divide by 10 to get the average character width.
  Size _measureCellSize() {
    if (_cellSize != null && _cachedFontSize == fontSize) return _cellSize!;

    final style = ui.TextStyle(fontFamily: fontFamily, fontSize: fontSize);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
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
    final textColor = AppTheme.bg2;
    final style = ui.TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: textColor,
    );
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
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
      fontFamily != old.fontFamily;
}
