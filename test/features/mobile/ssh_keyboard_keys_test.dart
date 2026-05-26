import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/ssh_keyboard_keys.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;

void main() {
  group('charKey', () {
    test('carries the character scalar and no modifiers by default', () {
      final key = charKey('|');
      final name = key.name;
      expect(name, isA<rust_terminal.TerminalKeyName_Char>());
      expect(
        (name as rust_terminal.TerminalKeyName_Char).code,
        '|'.runes.first,
      );
      expect(key.ctrl, isFalse);
      expect(key.alt, isFalse);
      expect(key.shift, isFalse);
      expect(key.meta, isFalse);
    });

    test('folds Ctrl / Alt into the modifier flags', () {
      // Spec: the bar's sticky modifiers ride on the key's flags so the
      // Rust encoder produces the control / meta sequence — the mapping
      // does not pre-encode bytes.
      final key = charKey('c', ctrl: true, alt: true);
      expect(key.ctrl, isTrue);
      expect(key.alt, isTrue);
    });

    test('takes the first rune of a multi-rune string', () {
      // A multi-code-unit grapheme degrades to its first scalar rather than
      // throwing — the bar only ever passes single visible glyphs.
      final key = charKey('~tail');
      expect(
        (key.name as rust_terminal.TerminalKeyName_Char).code,
        '~'.runes.first,
      );
    });
  });

  group('namedKey', () {
    test('carries the named key and folded modifiers', () {
      final key = namedKey(SshBarKeys.escape, ctrl: true);
      expect(key.name, isA<rust_terminal.TerminalKeyName_Escape>());
      expect(key.ctrl, isTrue);
      expect(key.alt, isFalse);
    });
  });

  group('SshBarKeys', () {
    test('exposes the bar named keys', () {
      expect(SshBarKeys.escape, isA<rust_terminal.TerminalKeyName_Escape>());
      expect(SshBarKeys.tab, isA<rust_terminal.TerminalKeyName_Tab>());
      expect(SshBarKeys.arrowUp, isA<rust_terminal.TerminalKeyName_Up>());
      expect(SshBarKeys.arrowDown, isA<rust_terminal.TerminalKeyName_Down>());
      expect(SshBarKeys.arrowLeft, isA<rust_terminal.TerminalKeyName_Left>());
      expect(SshBarKeys.arrowRight, isA<rust_terminal.TerminalKeyName_Right>());
    });

    test('function(n) carries the F-key number', () {
      final f = SshBarKeys.function(7);
      expect(f, isA<rust_terminal.TerminalKeyName_F>());
      expect((f as rust_terminal.TerminalKeyName_F).number, 7);
    });
  });
}
