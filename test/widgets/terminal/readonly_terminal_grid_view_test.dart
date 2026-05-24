import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/terminal_clipboard.dart';
import 'package:letsflutssh/widgets/terminal/readonly_terminal_grid_view.dart';
import 'package:letsflutssh/widgets/terminal/terminal_grid_painter.dart';

const _fg = TerminalColor(r: 200, g: 200, b: 200);
const _bg = TerminalColor(r: 10, g: 10, b: 10);

TerminalFrame _frameWith(String ch) => TerminalFrame(
  cols: 10,
  rows: 5,
  cursor: const TerminalCursor(
    row: 0,
    col: 0,
    shape: TerminalCursorShape.hidden,
    visible: false,
  ),
  displayOffset: 0,
  historySize: 0,
  mouseTracking: TerminalMouseTracking.none,
  cells: [
    TerminalCell(
      row: 0,
      col: 0,
      ch: ch.codeUnitAt(0),
      fg: _fg,
      bg: _bg,
      flags: 0,
    ),
  ],
  selection: null,
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  theme: AppTheme.dark(),
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

TerminalGridPainter _readPainter(WidgetTester tester) {
  final cp = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(ReadOnlyTerminalGridView),
      matching: find.byType(CustomPaint),
    ),
  );
  return cp.painter! as TerminalGridPainter;
}

void main() {
  group('ReadOnlyTerminalGridView — render via DI seam', () {
    // Spec: the view paints the snapshot the provider returns at mount.
    testWidgets('paints the initial snapshot frame', (tester) async {
      final repaint = ChangeNotifier();
      addTearDown(repaint.dispose);

      await tester.pumpWidget(
        _app(
          ReadOnlyTerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            repaint: repaint,
          ),
        ),
      );

      final painter = _readPainter(tester);
      expect(painter.frame.cells.single.ch, 'A'.codeUnitAt(0));
      expect(painter.frameRevision, 0);
    });

    // Spec: a repaint notify re-pulls the snapshot and bumps the revision so
    // the painter repaints — the only repaint trigger (no event stream).
    testWidgets('repaint notify pulls a fresh frame and bumps revision', (
      tester,
    ) async {
      final repaint = ChangeNotifier();
      addTearDown(repaint.dispose);
      var current = 'A';

      await tester.pumpWidget(
        _app(
          ReadOnlyTerminalGridView.fromSource(
            snapshotProvider: () => _frameWith(current),
            repaint: repaint,
          ),
        ),
      );
      expect(_readPainter(tester).frame.cells.single.ch, 'A'.codeUnitAt(0));

      current = 'B';
      repaint.notifyListeners();
      await tester.pump();

      final painter = _readPainter(tester);
      expect(painter.frame.cells.single.ch, 'B'.codeUnitAt(0));
      expect(painter.frameRevision, 1);
    });

    // Spec: with onResize set, the laid-out whole-cell count is reported back
    // (deferred out of layout). Without it, no report fires.
    testWidgets('reports laid-out cell count when onResize is set', (
      tester,
    ) async {
      final repaint = ChangeNotifier();
      addTearDown(repaint.dispose);
      int? cols;
      int? rows;

      await tester.pumpWidget(
        _app(
          ReadOnlyTerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            repaint: repaint,
            onResize: (c, r) {
              cols = c;
              rows = r;
            },
          ),
        ),
      );
      await tester.pump();

      expect(cols, isNotNull);
      expect(rows, isNotNull);
      expect(cols! > 0, isTrue);
      expect(rows! > 0, isTrue);
    });

    // Spec: disposing the view removes its listener so a later notify on a
    // surviving repaint source does not throw against a dead State.
    testWidgets('removes its repaint listener on dispose', (tester) async {
      final repaint = ChangeNotifier();
      addTearDown(repaint.dispose);

      await tester.pumpWidget(
        _app(
          ReadOnlyTerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            repaint: repaint,
          ),
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );

      // A notify after dispose must not throw (listener was removed).
      expect(repaint.notifyListeners, returnsNormally);
    });
  });

  group('ReadOnlyTerminalGridView — select + copy via the DI seam', () {
    late List<List<Object>> setCalls;
    late int clearCalls;
    late String? selectionText;

    setUp(() {
      setCalls = [];
      clearCalls = 0;
      selectionText = null;
    });

    tearDown(() {
      clearClipboardMock();
      TerminalClipboard.debugResetSecureClipboard();
    });

    Widget buildSelectable() => _app(
      ReadOnlyTerminalGridView.fromSource(
        snapshotProvider: () => _frameWith('A'),
        repaint: ChangeNotifier(),
        onSetSelection: (sr, sc, er, ec, kind) =>
            setCalls.add([sr, sc, er, ec, kind]),
        onClearSelection: () => clearCalls++,
        selectionTextProvider: () => selectionText,
      ),
    );

    // Spec: a primary-button drag maps start/end pixels to cells via the
    // shared `pointerToCell` helper and forwards them to onSetSelection. The
    // exact cells depend on the measured mono pitch, so assert the wiring
    // fired across distinct cells rather than pinning coordinates.
    testWidgets('a primary-button drag drives onSetSelection', (tester) async {
      await tester.pumpWidget(buildSelectable());
      await tester.pump();

      final box = tester.getTopLeft(find.byType(CustomPaint).first);
      final gesture = await tester.startGesture(box + const Offset(20, 20));
      await tester.pump();
      await gesture.moveTo(box + const Offset(120, 60));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // Press anchors a collapsed selection; the move extends it. The last
      // call must span a wider column than the first (the drag moved right).
      expect(setCalls.length, greaterThanOrEqualTo(2));
      final first = setCalls.first;
      final last = setCalls.last;
      expect((last[3] as int) > (first[3] as int), isTrue);
      expect(last[4], TerminalSelectionKind.simple);
    });

    // Spec: Ctrl+C reads the engine's selectionText and routes it through the
    // shared TerminalClipboard path (stock clipboard for non-sensitive text),
    // then clears the selection — the OLD read-only view's plain-Ctrl+C copy.
    testWidgets('Ctrl+C copies selectionText to the clipboard', (tester) async {
      selectionText = 'copied text';
      String? lastWrite;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              lastWrite = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      await tester.pumpWidget(buildSelectable());
      await tester.pump();
      // Focus the surface so the key event reaches the handler.
      await tester.tapAt(
        tester.getCenter(find.byType(ReadOnlyTerminalGridView)),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await Future<void>.delayed(Duration.zero);

      expect(lastWrite, 'copied text');
      // Selection cleared after copy (plus the single-click clear from the
      // focusing tap) — at least one clear fired.
      expect(clearCalls, greaterThanOrEqualTo(1));
    });

    // Spec: Ctrl+Shift+C — the live pane's terminalCopy binding — also copies,
    // so muscle memory from the interactive pane works here.
    testWidgets('Ctrl+Shift+C also copies selectionText', (tester) async {
      selectionText = 'shift copy';
      String? lastWrite;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              lastWrite = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      await tester.pumpWidget(buildSelectable());
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byType(ReadOnlyTerminalGridView)),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await Future<void>.delayed(Duration.zero);

      expect(lastWrite, 'shift copy');
    });

    // Spec: with nothing selected, the copy shortcut is a no-op — no clipboard
    // write — so an empty selection never overwrites the clipboard.
    testWidgets('Ctrl+C with no selection writes nothing', (tester) async {
      selectionText = null;
      var stockWrites = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') stockWrites++;
            return null;
          });

      await tester.pumpWidget(buildSelectable());
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byType(ReadOnlyTerminalGridView)),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await Future<void>.delayed(Duration.zero);

      expect(stockWrites, 0);
    });

    // Spec: a non-selectable view (the default) wires no selection seam, so it
    // renders no Focus/Listener interaction layer over the grid.
    testWidgets('non-selectable view installs no Focus layer', (tester) async {
      await tester.pumpWidget(
        _app(
          ReadOnlyTerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            repaint: ChangeNotifier(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(ReadOnlyTerminalGridView),
          matching: find.byType(Focus),
        ),
        findsNothing,
      );
    });
  });
}

void clearClipboardMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
}
