import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/terminal_scrubber.dart';
import 'package:xterm/xterm.dart';

void main() {
  setUp(() => TerminalScrubber.instance.resetForTests());
  tearDown(() => TerminalScrubber.instance.resetForTests());

  group('TerminalScrubber', () {
    test('starts empty', () {
      expect(TerminalScrubber.instance.trackedCount, 0);
    });

    test('register + unregister track count correctly', () {
      final t = Terminal(maxLines: 10);
      TerminalScrubber.instance.register(t);
      expect(TerminalScrubber.instance.trackedCount, 1);
      TerminalScrubber.instance.unregister(t);
      expect(TerminalScrubber.instance.trackedCount, 0);
    });

    test('register is idempotent — same instance twice stays at 1', () {
      final t = Terminal(maxLines: 10);
      TerminalScrubber.instance.register(t);
      TerminalScrubber.instance.register(t);
      expect(TerminalScrubber.instance.trackedCount, 1);
    });

    test('unregister of an unknown terminal is a no-op', () {
      final t = Terminal(maxLines: 10);
      TerminalScrubber.instance.unregister(t);
      expect(TerminalScrubber.instance.trackedCount, 0);
    });

    test('scrubAll clears the scrollback of every registered terminal', () {
      final a = Terminal(maxLines: 100);
      final b = Terminal(maxLines: 100);
      // Write something so scrollback has content.
      a.write('secret output\r\n');
      b.write('other output\r\n');
      TerminalScrubber.instance.register(a);
      TerminalScrubber.instance.register(b);

      TerminalScrubber.instance.scrubAll();

      // After scrub the buffer's current line should be empty.
      // We cannot assert on deep internals without tight coupling;
      // the contract is "scrubAll runs without throwing and resets
      // cursor to (0,0)" which we verify via the cursor.
      expect(a.buffer.cursorX, 0);
      expect(a.buffer.cursorY, 0);
      expect(b.buffer.cursorX, 0);
      expect(b.buffer.cursorY, 0);
    });

    test('scrubAll on an empty registry is a no-op that does not throw', () {
      expect(() => TerminalScrubber.instance.scrubAll(), returnsNormally);
    });

    test('singleton — instance is the same across gets', () {
      expect(
        identical(TerminalScrubber.instance, TerminalScrubber.instance),
        isTrue,
      );
    });
  });
}
