import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../theme/app_theme.dart';

/// Line-height multiplier our renderer lays terminal rows out with.
/// [TerminalGridPainter] passes this as the glyph paragraph `height:`
/// and derives every cell origin from a row pitch measured under the
/// same multiplier (via [measureMonoCell]). Any overlay / SizedBox
/// host that needs to land pixels on the cell grid must measure with
/// this same value: a divergence (e.g. a TextPainter pass without
/// `height:` set) yields a shorter row pitch and overlays render off
/// by ~0.02 × fontSize per row — visible on the bottom of a 24-row
/// terminal as a half-cell drift.
const double kTerminalLineHeight = 1.2;

/// Inset around terminal content — single source of truth across every
/// terminal surface (PTY pane, mobile pane, log viewer, connection
/// progress, read-only replay). Callers that snap a `LayoutBuilder`
/// constraint to whole cells subtract [kTerminalVerticalPadding] first.
const double kTerminalPadding = AppSpacing.xs;

/// Combined vertical inset (top + bottom).
const double kTerminalVerticalPadding = kTerminalPadding * 2;

/// Measure one terminal cell (width × height) the same way
/// [TerminalGridPainter] lays glyphs out, so callers can size their
/// host `SizedBox` / overlay coordinates without drifting off the
/// rendered grid.
///
/// Algorithm: build a 10-char `'mmmmmmmmmm'` paragraph under the same
/// mono `TextStyle` the painter renders with, divide
/// `maxIntrinsicWidth / test.length` for the cell width, take
/// `paragraph.height` for the row pitch. The height multiplier
/// defaults to [kTerminalLineHeight] (1.2), matching the painter's
/// glyph paragraph `height:`.
///
/// Drift on this number is load-bearing: the host derives the grid
/// dimensions it reports to the Rust engine (`resize`) from
/// `floor(width / cell.width)` × `floor(height / cell.height)`. A
/// 0.1 px / cell mismatch over 132 cols drops the reported width to
/// 131 cols, and curses workloads (htop / vim) that the engine then
/// wraps at col 132 land on col 1 of the next painted row — ghost
/// characters bleed across every redraw.
Size measureMonoCell({
  required double fontSize,
  double lineHeight = kTerminalLineHeight,
  String fontFamily = AppFonts.monoFamily,
  List<String> fontFamilyFallback = AppFonts.monoFallback,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  const test = 'mmmmmmmmmm';
  // Scale the font by the OS text scaler so the measured cell pitch
  // matches what the painter actually draws. A host that sizes a
  // SizedBox off the unscaled font while the painter renders the
  // scaled one ends up a row short — the text-scale gap clips the
  // bottom row.
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
