import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/widgets/terminal/terminal_controller.dart';

import '../../helpers/frb_bootstrap.dart';

/// Pull the printed characters out of a sparse [TerminalFrame].
Set<String> _chars(TerminalFrame frame) =>
    frame.cells.map((c) => String.fromCharCode(c.ch)).toSet();

void main() {
  // The replay adapter wraps a real Rust TerminalReplay, so the native library
  // must be loaded.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('ReplayTerminalController', () {
    test('feed renders bytes into the snapshot and notifies repaint', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.feed(utf8.encode('Hi'));

      expect(_chars(controller.snapshot()), containsAll(['H', 'i']));
      expect(notified, 1);
    });

    test('clear wipes the grid and notifies', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('hello world'));
      expect(controller.snapshot().cells, isNotEmpty);

      var notified = 0;
      controller.repaint.addListener(() => notified++);
      controller.clear();

      expect(controller.snapshot().cells, isEmpty);
      expect(notified, 1);
    });

    test('resize updates the reported cols/rows; a no-op resize is silent', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      controller.resize(40, 10);
      expect(controller.cols, 40);
      expect(controller.rows, 10);
      expect(controller.snapshot().cols, 40);
      expect(notified, 1);

      // Re-resizing to the same dims must not notify (the view re-reports the
      // same size on every layout pass).
      controller.resize(40, 10);
      expect(notified, 1);
    });

    test('selection round-trips through the engine and notifies', () async {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('abcdef'));
      var notified = 0;
      controller.repaint.addListener(() => notified++);

      // Select the first three cells of the top line.
      await controller.setSelection(0, 0, 0, 2, TerminalSelectionKind.simple);
      expect(notified, 1);
      expect(await controller.selectionText(), isNotNull);

      controller.clearSelection();
      expect(notified, 2);
      expect(await controller.selectionText(), isNull);
    });

    test('feed discards PtyWrite replies without leaking into the grid', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);

      // `ESC[6n` (device status report) makes the engine queue a PtyWrite
      // reply; the replay drops it. The surrounding text still renders.
      controller.feed(utf8.encode('A\x1B[6nB'));

      expect(_chars(controller.snapshot()), containsAll(['A', 'B']));
    });

    test('exposes no UI-event stream and reports not-live', () {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      expect(controller.uiEvents, isNull);
      expect(controller.isLive, isFalse);
    });

    // Spec: the live-only capabilities are inert no-ops on the replay adapter
    // (the read-only surfaces never enable the matching config), so calling
    // them must neither throw nor mutate the grid.
    test('live-only capabilities are inert on the replay adapter', () async {
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);

      expect(
        () => controller.sendKey(
          const TerminalKey(
            name: TerminalKeyName.char(code: 0x41),
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
          ),
        ),
        returnsNormally,
      );
      expect(() => controller.writeInput(utf8.encode('x')), returnsNormally);
      expect(
        () => controller.sendMouse(
          const TerminalMouseInput(
            button: TerminalMouseButton.left,
            action: TerminalMouseAction.press,
            col: 1,
            row: 1,
            shift: false,
            alt: false,
            ctrl: false,
          ),
        ),
        returnsNormally,
      );
      expect(() => controller.scroll(3), returnsNormally);
      await controller.paste('x');
      expect(await controller.search('x'), isEmpty);
      // None of the inert calls put anything on the grid.
      expect(controller.snapshot().cells, isEmpty);
    });

    test('dispose releases the Rust replay handle deterministically', () {
      // The controller owns the `TerminalReplay` opaque, so its dispose
      // must drop it rather than leaving it to the FRB finalizer. After
      // dispose the freed handle rejects further engine calls instead of
      // operating on a released Arc.
      final controller = ReplayTerminalController(cols: 20, rows: 5);
      controller.dispose();
      expect(() => controller.feed(utf8.encode('x')), throwsA(anything));
    });
  });
}
