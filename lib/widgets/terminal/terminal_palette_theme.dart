import 'package:flutter/painting.dart';

import '../../src/rust/api/terminal.dart';
import '../../theme/app_theme.dart';

/// Bridges the app's terminal color theme into the Rust engine's
/// [TerminalPalette] DTO. The engine resolves every cell's abstract
/// color (ANSI index, 256-cube, default fg/bg) against this palette and
/// hands the renderer concrete RGB, so the colors a user sees come from
/// here — the same OneDark swatches that fed xterm's `TerminalTheme`.
///
/// Reads the live `AppTheme.term*` accessors, which already switch on
/// the active light/dark mode, so calling this after a theme toggle and
/// pushing the result through `TerminalSession.setPalette` re-themes the
/// terminal. The 256-color cube is derived inside the engine and is not
/// carried in the DTO.
extension TerminalPaletteFromTheme on TerminalPalette {
  /// Build the palette from the current [AppTheme] terminal swatches.
  static TerminalPalette fromAppTheme() => TerminalPalette(
    // Index order is NamedColor: the 8 base colors then their 8 bright
    // variants. Must match the order the engine indexes by.
    ansi: [
      _rgb(AppTheme.termBlack),
      _rgb(AppTheme.termRed),
      _rgb(AppTheme.termGreen),
      _rgb(AppTheme.termYellow),
      _rgb(AppTheme.termBlue),
      _rgb(AppTheme.termMagenta),
      _rgb(AppTheme.termCyan),
      _rgb(AppTheme.termWhite),
      _rgb(AppTheme.termBrightBlack),
      _rgb(AppTheme.termBrightRed),
      _rgb(AppTheme.termBrightGreen),
      _rgb(AppTheme.termBrightYellow),
      _rgb(AppTheme.termBrightBlue),
      _rgb(AppTheme.termBrightMagenta),
      _rgb(AppTheme.termBrightCyan),
      _rgb(AppTheme.termBrightWhite),
    ],
    foreground: _rgb(AppTheme.fg),
    background: _rgb(AppTheme.bg2),
    cursor: _rgb(AppTheme.termCursor),
    selection: _rgb(AppTheme.termSelection),
  );
}

/// Convert a Flutter [Color] to the engine's 24-bit [TerminalColor].
/// Drops alpha — the engine palette is opaque RGB; the renderer applies
/// any transparency (selection/cursor wash) at paint time.
TerminalColor _rgb(Color c) => TerminalColor(
  r: (c.r * 255.0).round() & 0xff,
  g: (c.g * 255.0).round() & 0xff,
  b: (c.b * 255.0).round() & 0xff,
);
