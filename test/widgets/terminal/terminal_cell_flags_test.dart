import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/terminal/terminal_cell_flags.dart';

void main() {
  group('TerminalCellFlags.fromBits', () {
    // Spec: each render-relevant attribute bit decodes to its own bool,
    // matching the alacritty_terminal Flags layout the engine widens and
    // forwards verbatim. A wrong bit constant mis-styles glyphs.
    test('decodes each attribute from its own bit', () {
      expect(TerminalCellFlags.fromBits(kCellFlagBold).bold, isTrue);
      expect(TerminalCellFlags.fromBits(kCellFlagItalic).italic, isTrue);
      expect(TerminalCellFlags.fromBits(kCellFlagUnderline).underline, isTrue);
      expect(TerminalCellFlags.fromBits(kCellFlagStrikeout).strikeout, isTrue);
      expect(TerminalCellFlags.fromBits(kCellFlagHidden).hidden, isTrue);
      expect(TerminalCellFlags.fromBits(kCellFlagWideChar).wide, isTrue);
    });

    test('zero bits decode to all-false', () {
      final f = TerminalCellFlags.fromBits(0);
      expect(f.bold, isFalse);
      expect(f.italic, isFalse);
      expect(f.underline, isFalse);
      expect(f.strikeout, isFalse);
      expect(f.hidden, isFalse);
      expect(f.wide, isFalse);
    });

    test('a bit does not leak into a neighbouring attribute', () {
      // BOLD (0x2) must not register as ITALIC (0x4) or INVERSE (0x1).
      final f = TerminalCellFlags.fromBits(kCellFlagBold);
      expect(f.bold, isTrue);
      expect(f.italic, isFalse);
    });

    test('combined bits decode independently', () {
      final f = TerminalCellFlags.fromBits(
        kCellFlagBold | kCellFlagItalic | kCellFlagUnderline,
      );
      expect(f.bold, isTrue);
      expect(f.italic, isTrue);
      expect(f.underline, isTrue);
      expect(f.strikeout, isFalse);
    });

    test('the BOLD_ITALIC composite (0x6) sets both', () {
      // alacritty composes BOLD_ITALIC = BOLD | ITALIC = 0x6.
      final f = TerminalCellFlags.fromBits(0x0006);
      expect(f.bold, isTrue);
      expect(f.italic, isTrue);
    });

    test('high bits the renderer ignores do not flip a consumed flag', () {
      // WRAPLINE (0x10) and DOUBLE_UNDERLINE (0x800) are not consumed.
      final f = TerminalCellFlags.fromBits(0x10 | 0x800);
      expect(f.bold, isFalse);
      expect(f.italic, isFalse);
      expect(f.underline, isFalse);
      expect(f.wide, isFalse);
    });
  });
}
