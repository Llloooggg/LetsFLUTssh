import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../theme/app_theme.dart';

/// Line-height multiplier xterm-flutter renders terminal rows with.
/// Mirrors `TerminalStyle._kDefaultHeight` in
/// `package:xterm/src/ui/terminal_text_style.dart` (1.2). Every
/// overlay / SizedBox host that needs to land pixels on xterm's
/// cell grid measures with this same multiplier, so a divergence
/// (e.g. a TextPainter pass without `height:` set) yields a slightly
/// shorter row pitch and overlays render off by ~0.02 × fontSize per
/// row — visible on the bottom of a 24-row terminal as a half-cell
/// drift. Keep in lock-step with the xterm-flutter version pinned in
/// `pubspec.yaml`.
const double kTerminalLineHeight = 1.2;

/// Measure one terminal cell (width × height) the same way
/// xterm-flutter does internally so callers can size their host
/// `SizedBox` / overlay coordinates without drifting off
/// xterm's grid.
///
/// Algorithm matches `TerminalPainter._measureCharSize` byte-for-byte
/// (xterm-4.0.0 `lib/src/ui/painter.dart`): build a 10-char
/// `'mmmmmmmmmm'` paragraph under the same mono `TextStyle` xterm
/// renders with, divide `maxIntrinsicWidth / test.length` for the
/// cell width, take `paragraph.height` for the row pitch. The
/// height multiplier defaults to [kTerminalLineHeight] (1.2) so the
/// height value matches xterm-flutter's `TerminalStyle.height`
/// default.
///
/// Drift on this number is load-bearing: when the host SizedBox
/// gets `cols * cell.width` of width, xterm-flutter's
/// `TerminalView` auto-resizes the underlying `Terminal` based on
/// its OWN re-measurement of the same algorithm against the
/// constrained width. A 0.1 px / cell mismatch over 132 cols
/// drops the auto-resize down to 131 cols, and curses workloads
/// (htop / vim) that write at col 132 wrap onto col 1 of the
/// next row — ghost characters bleed across every redraw.
Size measureMonoCell({
  required double fontSize,
  double lineHeight = kTerminalLineHeight,
  String fontFamily = AppFonts.monoFamily,
  List<String> fontFamilyFallback = AppFonts.monoFallback,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  const test = 'mmmmmmmmmm';
  // Match `TerminalView`, which measures its grid against
  // `MediaQuery.textScalerOf(context)` (`terminal_view.dart`). A
  // host that sizes a SizedBox off the unscaled font while xterm
  // renders the scaled one ends up a row short — the OS text-scale
  // gap clips the bottom row. Scale the font here so the cell pitch
  // matches whatever xterm will actually paint with.
  final scaledFontSize = textScaler.scale(fontSize);
  final paragraphStyle = ui.ParagraphStyle(height: lineHeight);
  final textStyle = ui.TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: scaledFontSize,
    height: lineHeight,
  );
  final paragraph =
      (ui.ParagraphBuilder(paragraphStyle)
            ..pushStyle(textStyle)
            ..addText(test))
          .build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
  final size = Size(
    paragraph.maxIntrinsicWidth / test.length,
    paragraph.height,
  );
  paragraph.dispose();
  return size;
}
