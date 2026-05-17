import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/anchor_pinning_terminal_controller.dart';
import 'package:xterm/xterm.dart';

/// Helper: write [n] non-empty lines into [terminal] so the buffer has
/// real anchorable rows above the cursor.
void _seedLines(Terminal terminal, int n) {
  for (var i = 0; i < n; i++) {
    terminal.write('line-$i\r\n');
  }
}

void main() {
  group('AnchorPinningTerminalController', () {
    test('passes setSelection through verbatim when no drag is active', () {
      final terminal = Terminal();
      _seedLines(terminal, 5);
      final controller = AnchorPinningTerminalController();

      final base = terminal.buffer.createAnchor(0, 1);
      final baseOffset = base.offset;
      final extent = terminal.buffer.createAnchor(3, 2);
      final extentOffset = extent.offset;
      controller.setSelection(base, extent);

      final sel = controller.selection!;
      expect(sel.begin, equals(baseOffset));
      expect(sel.end, equals(extentOffset));
    });

    test('pins the first base for subsequent setSelection calls in a drag', () {
      final terminal = Terminal();
      _seedLines(terminal, 10);
      final controller = AnchorPinningTerminalController();

      // Simulate xterm's drag handler: start at (2, 1), then drag updates
      // recompute base from the same start pixel — under a scroll, that
      // pixel resolves to a different row. We model that by passing a
      // *different* base anchor on the second call.
      final originalBase = terminal.buffer.createAnchor(2, 1);
      final originalOffset = originalBase.offset;
      final scrollDriftedBase = terminal.buffer.createAnchor(2, 4);
      final extent = terminal.buffer.createAnchor(5, 6);
      final extentOffset = extent.offset;

      controller.beginDrag();
      controller.setSelection(originalBase, originalBase);
      controller.setSelection(scrollDriftedBase, extent);

      final sel = controller.selection!;
      // Base must remain the originally-observed anchor; only extent moves.
      expect(sel.begin, equals(originalOffset));
      expect(sel.end, equals(extentOffset));
    });

    test('stops pinning after endDrag', () {
      final terminal = Terminal();
      _seedLines(terminal, 10);
      final controller = AnchorPinningTerminalController();

      final firstBase = terminal.buffer.createAnchor(0, 1);
      final secondBase = terminal.buffer.createAnchor(0, 5);
      final secondOffset = secondBase.offset;
      final extent = terminal.buffer.createAnchor(3, 7);
      final extentOffset = extent.offset;

      controller.beginDrag();
      controller.setSelection(firstBase, firstBase);
      controller.endDrag();

      // A fresh setSelection after endDrag must NOT reuse firstBase.
      controller.setSelection(secondBase, extent);

      final sel = controller.selection!;
      expect(sel.begin, equals(secondOffset));
      expect(sel.end, equals(extentOffset));
    });

    test('clearSelection drops the pinned anchor', () {
      final terminal = Terminal();
      _seedLines(terminal, 10);
      final controller = AnchorPinningTerminalController();

      final firstBase = terminal.buffer.createAnchor(0, 1);
      final laterBase = terminal.buffer.createAnchor(0, 4);
      final laterOffset = laterBase.offset;
      final extent = terminal.buffer.createAnchor(3, 6);
      final extentOffset = extent.offset;

      controller.beginDrag();
      controller.setSelection(firstBase, firstBase);
      controller.clearSelection();
      // Still inside the same drag, but cleared — the next setSelection
      // captures a fresh base, not the stale firstBase.
      controller.setSelection(laterBase, extent);

      final sel = controller.selection!;
      expect(sel.begin, equals(laterOffset));
      expect(sel.end, equals(extentOffset));
    });

    test(
      'falls back to fresh base when pinned line rotates out of scrollback',
      () {
        // Small scrollback so a few hundred writes push the pinned
        // line out of the circular buffer (CircularBuffer._detach
        // fires → BufferLine.attached → false). maxLines must be
        // ≥ viewHeight (24 default) or the buffer can't bootstrap.
        final terminal = Terminal(maxLines: 30);
        _seedLines(terminal, 3);
        final controller = AnchorPinningTerminalController();

        final originalBase = terminal.buffer.createAnchor(0, 1);
        final originalLine = originalBase.line!;

        controller.beginDrag();
        controller.setSelection(originalBase, originalBase);

        // Overflow far beyond the scrollback so the early line is
        // guaranteed to rotate out.
        for (var i = 0; i < 200; i++) {
          terminal.write('overflow-$i\r\n');
        }
        expect(
          originalLine.attached,
          isFalse,
          reason: 'precondition: original line must have rotated out',
        );

        // Next setSelection in the same drag must adopt the new base
        // instead of trying to mint an anchor on the detached line.
        final freshBase = terminal.buffer.createAnchor(1, 0);
        final freshOffset = freshBase.offset;
        final freshExtent = terminal.buffer.createAnchor(4, 1);
        final freshExtentOffset = freshExtent.offset;
        controller.setSelection(freshBase, freshExtent);

        final sel = controller.selection!;
        expect(sel.begin, equals(freshOffset));
        expect(sel.end, equals(freshExtentOffset));
      },
    );

    test('beginDrag resets any previously pinned anchor', () {
      final terminal = Terminal();
      _seedLines(terminal, 10);
      final controller = AnchorPinningTerminalController();

      final firstDragBase = terminal.buffer.createAnchor(0, 1);
      final secondDragBase = terminal.buffer.createAnchor(0, 5);
      final secondBaseOffset = secondDragBase.offset;
      final secondDragExtent = terminal.buffer.createAnchor(2, 7);
      final secondExtentOffset = secondDragExtent.offset;

      controller.beginDrag();
      controller.setSelection(firstDragBase, firstDragBase);
      // No endDrag — exercise the defensive reset inside beginDrag itself.
      controller.beginDrag();
      controller.setSelection(secondDragBase, secondDragExtent);

      final sel = controller.selection!;
      expect(sel.begin, equals(secondBaseOffset));
      expect(sel.end, equals(secondExtentOffset));
    });
  });
}
