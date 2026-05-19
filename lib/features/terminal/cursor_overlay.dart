import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_terminal_view.dart';
import '../../widgets/terminal_cell_metrics.dart';

/// Overlay that paints the character under the block cursor with an inverted
/// color so it stays readable.  xterm-flutter draws the cursor as a solid
/// opaque rectangle **on top** of the text — this widget re-draws just that
/// one character with [AppTheme.bg2] (background) as the text color, giving
/// the classic "inverted cursor" look without forking the package.
///
/// Place inside a [Stack] on top of [TerminalView] with identical sizing.
///
/// Cell sizing routes through the shared [measureMonoCell] helper so this
/// overlay, the mobile copy overlay, and the recording playback host all
/// land pixels on the same xterm-flutter cell grid — see
/// `widgets/terminal_cell_metrics.dart` for the algorithm.

class CursorTextOverlay extends StatefulWidget {
  const CursorTextOverlay({
    super.key,
    required this.terminal,
    required this.fontSize,
    this.fontFamily = AppFonts.monoFamily,
    this.fontFamilyFallback = AppFonts.monoFallback,
    this.padding = const EdgeInsets.all(AppTerminalView.padding),
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

  /// Coalesce bursts of terminal change events into one repaint per frame.
  /// xterm's [Terminal] fires its listeners on every write callback, which
  /// on a busy stream (large SSH paste, long-running build output) can be
  /// hundreds of callbacks per frame. Without throttling each callback
  /// forced a [CustomPainter] repaint — we measure the same cursor cell,
  /// build a paragraph, draw it, dispose — at a frequency far above vsync.
  /// [_repaintScheduled] gates the `addPostFrameCallback` so we bump the
  /// [ValueNotifier] at most once per frame.
  bool _repaintScheduled = false;

  void _onTerminalChanged() {
    if (_repaintScheduled) return;
    _repaintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repaintScheduled = false;
      if (!mounted) return;
      _repaint.value++;
    });
  }

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

  Size _measureCellSize() {
    if (_cellSize != null && _cachedFontSize == fontSize) return _cellSize!;
    _cellSize = measureMonoCell(
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    _cachedFontSize = fontSize;
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
