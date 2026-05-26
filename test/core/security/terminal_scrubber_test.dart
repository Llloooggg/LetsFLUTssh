import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/terminal_scrubber.dart';

void main() {
  setUp(() => TerminalScrubber.instance.resetForTests());
  tearDown(() => TerminalScrubber.instance.resetForTests());

  group('TerminalScrubber', () {
    test('starts empty', () {
      expect(TerminalScrubber.instance.trackedCount, 0);
    });

    test('register + unregister track count correctly', () {
      void noop() {}
      TerminalScrubber.instance.register(noop);
      expect(TerminalScrubber.instance.trackedCount, 1);
      TerminalScrubber.instance.unregister(noop);
      expect(TerminalScrubber.instance.trackedCount, 0);
    });

    test('register is idempotent — same closure twice stays at 1', () {
      void noop() {}
      TerminalScrubber.instance.register(noop);
      TerminalScrubber.instance.register(noop);
      expect(TerminalScrubber.instance.trackedCount, 1);
    });

    test('unregister of an unknown closure is a no-op', () {
      void noop() {}
      TerminalScrubber.instance.unregister(noop);
      expect(TerminalScrubber.instance.trackedCount, 0);
    });

    test('scrubAll invokes every registered callback', () {
      var aCalled = 0;
      var bCalled = 0;
      void a() => aCalled++;
      void b() => bCalled++;
      TerminalScrubber.instance.register(a);
      TerminalScrubber.instance.register(b);

      TerminalScrubber.instance.scrubAll();

      expect(aCalled, 1);
      expect(bCalled, 1);
    });

    test('scrubAll continues on a callback that throws', () {
      var bCalled = 0;
      void a() => throw StateError('boom');
      void b() => bCalled++;
      TerminalScrubber.instance.register(a);
      TerminalScrubber.instance.register(b);

      // Best-effort — must not propagate the throw and must call
      // the second callback regardless.
      expect(() => TerminalScrubber.instance.scrubAll(), returnsNormally);
      expect(bCalled, 1);
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
