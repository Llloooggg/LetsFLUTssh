import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/widgets/terminal/readonly_terminal_grid_view.dart';

import '../../helpers/frb_bootstrap.dart';

/// Pull the printed characters out of a sparse [TerminalFrame].
Set<String> _chars(TerminalFrame frame) =>
    frame.cells.map((c) => String.fromCharCode(c.ch)).toSet();

void main() {
  // The controller wraps a real Rust TerminalReplay, so the native library
  // must be loaded.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('ReadOnlyTerminalController', () {
    test('feed renders bytes into the snapshot and notifies', () {
      final controller = ReadOnlyTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.feed(utf8.encode('Hi'));

      expect(_chars(controller.snapshot()), containsAll(['H', 'i']));
      expect(notified, 1);
    });

    test('clear wipes the grid and notifies', () {
      final controller = ReadOnlyTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      controller.feed(utf8.encode('hello world'));
      expect(controller.snapshot().cells, isNotEmpty);

      var notified = 0;
      controller.addListener(() => notified++);
      controller.clear();

      expect(controller.snapshot().cells, isEmpty);
      expect(notified, 1);
    });

    test('resize updates the reported cols/rows; a no-op resize is silent', () {
      final controller = ReadOnlyTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.resize(40, 10);
      expect(controller.cols, 40);
      expect(controller.rows, 10);
      expect(controller.snapshot().cols, 40);
      expect(notified, 1);

      // Re-resizing to the same dims must not notify (the grid view re-reports
      // the same size on every layout pass).
      controller.resize(40, 10);
      expect(notified, 1);
    });

    test('feed discards PtyWrite replies without leaking into the grid', () {
      final controller = ReadOnlyTerminalController(cols: 20, rows: 5);
      addTearDown(controller.dispose);

      // `ESC[6n` (device status report) makes the engine queue a PtyWrite
      // reply; the replay drops it. The surrounding text still renders.
      controller.feed(utf8.encode('A\x1B[6nB'));

      expect(_chars(controller.snapshot()), containsAll(['A', 'B']));
    });
  });
}
