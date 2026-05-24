import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart' as rust_terminal;
import 'package:letsflutssh/widgets/terminal/terminal_key_input.dart';

/// Build a synthetic key-down event. `character` defaults to the label for
/// single-character keys so the printable-char path resolves; pass an
/// explicit `character` (or `''`) to model control combos / special keys.
KeyDownEvent _down(LogicalKeyboardKey key, {String? character}) {
  return KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
    character: character,
  );
}

void main() {
  group('terminalKeyFromEvent', () {
    test('plain letter maps to its Char scalar with no modifiers', () {
      // Spec: a typed printable char becomes Char(code) and carries no
      // modifier flags when none are held.
      final key = terminalKeyFromEvent(
        _down(LogicalKeyboardKey.keyA, character: 'a'),
        {LogicalKeyboardKey.keyA},
      );
      expect(key, isNotNull);
      expect(
        key!.name,
        rust_terminal.TerminalKeyName.char(code: 'a'.codeUnitAt(0)),
      );
      expect(key.ctrl, isFalse);
      expect(key.alt, isFalse);
      expect(key.shift, isFalse);
      expect(key.meta, isFalse);
    });

    test(
      'Ctrl+C resolves the letter via logical key when character is empty',
      () {
        // Spec: under Ctrl the OS reports no character, so the mapping falls
        // back to the logical key's label — Char('c') with ctrl set. The
        // byte transform (→0x03) happens Rust-side.
        final key = terminalKeyFromEvent(
          _down(LogicalKeyboardKey.keyC, character: ''),
          {LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyC},
        );
        expect(key, isNotNull);
        expect(
          key!.name,
          rust_terminal.TerminalKeyName.char(code: 'c'.codeUnitAt(0)),
        );
        expect(key.ctrl, isTrue);
      },
    );

    test('arrow key maps to its directional logical name', () {
      // Spec: a named special key wins over any character; ArrowUp → Up.
      final key = terminalKeyFromEvent(_down(LogicalKeyboardKey.arrowUp), {
        LogicalKeyboardKey.arrowUp,
      });
      expect(key, isNotNull);
      expect(key!.name, const rust_terminal.TerminalKeyName.up());
    });

    test('function key maps to F(n)', () {
      // Spec: F5 maps to the F variant carrying the number 5.
      final key = terminalKeyFromEvent(_down(LogicalKeyboardKey.f5), {
        LogicalKeyboardKey.f5,
      });
      expect(key, isNotNull);
      expect(key!.name, const rust_terminal.TerminalKeyName.f(number: 5));
    });

    test('Shift+Tab carries the Tab name with shift set', () {
      // Spec: Tab maps to the Tab name; the shift modifier surfaces so the
      // Rust encoder produces the back-tab sequence.
      final key = terminalKeyFromEvent(
        _down(LogicalKeyboardKey.tab, character: '\t'),
        {LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.tab},
      );
      expect(key, isNotNull);
      expect(key!.name, const rust_terminal.TerminalKeyName.tab());
      expect(key.shift, isTrue);
    });

    test('Enter maps to the Enter name, not a printable char', () {
      // Spec: Enter carries a CR character but must resolve to the Enter
      // name so the encoder applies the CR / LNM rule.
      final key = terminalKeyFromEvent(
        _down(LogicalKeyboardKey.enter, character: '\r'),
        {LogicalKeyboardKey.enter},
      );
      expect(key, isNotNull);
      expect(key!.name, const rust_terminal.TerminalKeyName.enter());
    });

    test('bare modifier press maps to null', () {
      // Spec: pressing a modifier alone produces no PTY bytes, so the
      // mapping returns null and the key is not forwarded.
      final key = terminalKeyFromEvent(_down(LogicalKeyboardKey.controlLeft), {
        LogicalKeyboardKey.controlLeft,
      });
      expect(key, isNull);
    });

    test('unmappable key with no character maps to null', () {
      // Spec: a key that is neither a recognised special key nor produces a
      // printable character (e.g. a media key) is dropped, not forwarded as
      // a garbage descriptor.
      final key = terminalKeyFromEvent(
        _down(LogicalKeyboardKey.mediaPlay),
        const <LogicalKeyboardKey>{},
      );
      expect(key, isNull);
    });

    test('held Alt surfaces as the alt modifier on a letter', () {
      // Spec: Alt+x reports the alt flag so the encoder applies the
      // ESC-prefix (metaSendsEscape) transform.
      final key = terminalKeyFromEvent(
        _down(LogicalKeyboardKey.keyX, character: 'x'),
        {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyX},
      );
      expect(key, isNotNull);
      expect(key!.alt, isTrue);
      expect(
        key.name,
        rust_terminal.TerminalKeyName.char(code: 'x'.codeUnitAt(0)),
      );
    });
  });
}
