import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/terminal/terminal_palette_theme.dart';

TerminalColor _rgb(Color c) => TerminalColor(
  r: (c.r * 255.0).round() & 0xff,
  g: (c.g * 255.0).round() & 0xff,
  b: (c.b * 255.0).round() & 0xff,
);

void main() {
  // Restore dark (the app default) so test ordering can't leak the mode.
  tearDown(() => AppTheme.setBrightness(Brightness.dark));

  group('TerminalPaletteFromTheme.fromAppTheme', () {
    // Spec: the DTO carries the OneDark dark swatches in NamedColor order
    // (8 base, then 8 bright) plus default fg/bg/cursor/selection, so the
    // engine resolves cells against the same colors xterm rendered.
    test('dark palette maps the 16 ANSI swatches in NamedColor order', () {
      AppTheme.setBrightness(Brightness.dark);
      final p = TerminalPaletteFromTheme.fromAppTheme();

      expect(p.ansi, hasLength(16));
      expect(
        p.ansi[0],
        const TerminalColor(r: 0x3F, g: 0x44, b: 0x51),
      ); // black
      expect(p.ansi[1], const TerminalColor(r: 0xE0, g: 0x55, b: 0x61)); // red
      expect(
        p.ansi[2],
        const TerminalColor(r: 0x8C, g: 0xC2, b: 0x65),
      ); // green
      expect(
        p.ansi[7],
        const TerminalColor(r: 0xD7, g: 0xDA, b: 0xE0),
      ); // white
      expect(
        p.ansi[8],
        const TerminalColor(r: 0x4F, g: 0x56, b: 0x66),
      ); // bright black
      expect(
        p.ansi[15],
        const TerminalColor(r: 0xE6, g: 0xE6, b: 0xE6),
      ); // bright white
    });

    test('dark palette maps default fg/bg/cursor/selection', () {
      AppTheme.setBrightness(Brightness.dark);
      final p = TerminalPaletteFromTheme.fromAppTheme();

      expect(p.foreground, _rgb(AppTheme.fg));
      expect(p.background, _rgb(AppTheme.bg2));
      expect(p.cursor, _rgb(AppTheme.termCursor));
      expect(p.selection, _rgb(AppTheme.termSelection));
    });

    test('light palette maps the Atom One Light swatches', () {
      AppTheme.setBrightness(Brightness.light);
      final p = TerminalPaletteFromTheme.fromAppTheme();

      expect(
        p.ansi[0],
        const TerminalColor(r: 0x38, g: 0x3A, b: 0x42),
      ); // black
      expect(p.ansi[1], const TerminalColor(r: 0xE4, g: 0x56, b: 0x49)); // red
      expect(
        p.ansi[15],
        const TerminalColor(r: 0xFF, g: 0xFF, b: 0xFF),
      ); // bright white
      expect(p.background, _rgb(AppTheme.bg2));
    });

    test('alpha is dropped from semi-transparent swatches', () {
      AppTheme.setBrightness(Brightness.dark);
      final p = TerminalPaletteFromTheme.fromAppTheme();
      // termSelection is defined with alpha; the DTO is opaque RGB.
      final sel = AppTheme.termSelection;
      expect(p.selection.r, (sel.r * 255.0).round() & 0xff);
      expect(p.selection.g, (sel.g * 255.0).round() & 0xff);
      expect(p.selection.b, (sel.b * 255.0).round() & 0xff);
    });
  });
}
