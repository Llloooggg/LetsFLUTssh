import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/mobile/ssh_key_sequences.dart';

void main() {
  group('SshKeySequences constants', () {
    test('escape is 0x1B', () {
      expect(SshKeySequences.escape, '\x1b');
    });

    test('tab is 0x09', () {
      expect(SshKeySequences.tab, '\x09');
    });

    test('backspace is 0x7F (DEL)', () {
      expect(SshKeySequences.backspace, '\x7f');
    });

    test('enter is CR', () {
      expect(SshKeySequences.enter, '\r');
    });

    test('arrow keys are CSI sequences', () {
      expect(SshKeySequences.arrowUp, '\x1b[A');
      expect(SshKeySequences.arrowDown, '\x1b[B');
      expect(SshKeySequences.arrowRight, '\x1b[C');
      expect(SshKeySequences.arrowLeft, '\x1b[D');
    });

    test('home and end', () {
      expect(SshKeySequences.home, '\x1b[H');
      expect(SshKeySequences.end, '\x1b[F');
    });

    test('F1-F4 are SS3 sequences', () {
      expect(SshKeySequences.f1, '\x1bOP');
      expect(SshKeySequences.f2, '\x1bOQ');
      expect(SshKeySequences.f3, '\x1bOR');
      expect(SshKeySequences.f4, '\x1bOS');
    });

    test('F5-F12 are CSI tilde sequences', () {
      expect(SshKeySequences.f5, '\x1b[15~');
      expect(SshKeySequences.f6, '\x1b[17~');
      expect(SshKeySequences.f12, '\x1b[24~');
    });

    test('functionKeyNames has 12 entries', () {
      expect(SshKeySequences.functionKeyNames.length, 12);
      expect(SshKeySequences.functionKeyNames.first, 'F1');
      expect(SshKeySequences.functionKeyNames.last, 'F12');
    });

    test('functionKeySequences has 12 entries matching names', () {
      expect(SshKeySequences.functionKeySequences.length, 12);
      expect(SshKeySequences.functionKeySequences[0], SshKeySequences.f1);
      expect(SshKeySequences.functionKeySequences[11], SshKeySequences.f12);
    });
  });

  group('ctrlKey', () {
    test('Ctrl+A = 0x01', () {
      expect(SshKeySequences.ctrlKey('a'), '\x01');
      expect(SshKeySequences.ctrlKey('A'), '\x01');
    });

    test('Ctrl+C = 0x03 (SIGINT)', () {
      expect(SshKeySequences.ctrlKey('c'), '\x03');
      expect(SshKeySequences.ctrlKey('C'), '\x03');
    });

    test('Ctrl+D = 0x04 (EOF)', () {
      expect(SshKeySequences.ctrlKey('d'), '\x04');
    });

    test('Ctrl+L = 0x0C (clear)', () {
      expect(SshKeySequences.ctrlKey('l'), '\x0c');
    });

    test('Ctrl+Z = 0x1A (SIGTSTP)', () {
      expect(SshKeySequences.ctrlKey('z'), '\x1a');
    });

    test('Ctrl+[ = ESC (0x1B)', () {
      expect(SshKeySequences.ctrlKey('['), '\x1b');
    });

    test('empty string returns empty', () {
      expect(SshKeySequences.ctrlKey(''), '');
    });

    test('character outside 0x40-0x5F returns unchanged', () {
      // '1' is 0x31, outside the Ctrl range
      expect(SshKeySequences.ctrlKey('1'), '1');
    });
  });

  group('altKey', () {
    test('Alt+a = ESC + a', () {
      expect(SshKeySequences.altKey('a'), '\x1ba');
    });

    test('Alt+x = ESC + x', () {
      expect(SshKeySequences.altKey('x'), '\x1bx');
    });

    test('empty string returns empty', () {
      expect(SshKeySequences.altKey(''), '');
    });
  });
}
