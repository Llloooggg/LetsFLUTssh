import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/terminal/terminal_grid_painter.dart';
import 'package:letsflutssh/widgets/terminal/terminal_grid_view.dart';

const _fg = TerminalColor(r: 200, g: 200, b: 200);
const _bg = TerminalColor(r: 10, g: 10, b: 10);

TerminalFrame _frameWith(
  String ch, {
  TerminalMouseTracking tracking = TerminalMouseTracking.none,
  int displayOffset = 0,
}) => TerminalFrame(
  cols: 10,
  rows: 5,
  cursor: const TerminalCursor(
    row: 0,
    col: 0,
    shape: TerminalCursorShape.block,
    visible: true,
  ),
  displayOffset: displayOffset,
  historySize: 0,
  mouseTracking: tracking,
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
      of: find.byType(TerminalGridView),
      matching: find.byType(CustomPaint),
    ),
  );
  return cp.painter! as TerminalGridPainter;
}

void main() {
  group('TerminalGridView — render + repaint', () {
    testWidgets('paints the initial snapshot frame', (tester) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
          ),
        ),
      );

      final painter = _readPainter(tester);
      expect(painter.frame.cells.single.ch, 'A'.codeUnitAt(0));
      expect(painter.frameRevision, 0);
    });

    // Spec: a Wakeup pulls a fresh snapshot and bumps the revision so the
    // painter repaints; bursts coalesce to one pull per frame.
    testWidgets('Wakeup pulls a fresh frame and bumps the revision', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      var current = 'A';

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith(current),
            events: controller.stream,
          ),
        ),
      );
      expect(_readPainter(tester).frameRevision, 0);

      current = 'B';
      controller.add(const TerminalUiEvent.wakeup());
      await tester.pump(); // deliver event
      await tester.pump(); // post-frame gate fires

      final painter = _readPainter(tester);
      expect(painter.frame.cells.single.ch, 'B'.codeUnitAt(0));
      expect(painter.frameRevision, 1);
    });

    testWidgets('a burst of wakeups coalesces to one repaint', (tester) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      var pulls = 0;

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () {
              pulls++;
              return _frameWith('A');
            },
            events: controller.stream,
          ),
        ),
      );
      final initialPulls = pulls; // initState pull(s)

      controller
        ..add(const TerminalUiEvent.wakeup())
        ..add(const TerminalUiEvent.wakeup())
        ..add(const TerminalUiEvent.wakeup());
      await tester.pump();
      await tester.pump();

      expect(pulls - initialPulls, 1);
      expect(_readPainter(tester).frameRevision, 1);
    });
  });

  group('TerminalGridView — UI event callbacks', () {
    testWidgets('Title / ResetTitle / Bell / ClipboardStore forward', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      String? title;
      var reset = 0;
      var bell = 0;
      String? clip;

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            onTitle: (t) => title = t,
            onResetTitle: () => reset++,
            onBell: () => bell++,
            onClipboardStore: (t) => clip = t,
          ),
        ),
      );

      controller
        ..add(const TerminalUiEvent.title(title: 'remote'))
        ..add(const TerminalUiEvent.resetTitle())
        ..add(const TerminalUiEvent.bell())
        ..add(const TerminalUiEvent.clipboardStore(text: 'copied'));
      await tester.pump();

      expect(title, 'remote');
      expect(reset, 1);
      expect(bell, 1);
      expect(clip, 'copied');
    });

    testWidgets('Closed fires onClosed', (tester) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      var closed = 0;

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            onClosed: () => closed++,
          ),
        ),
      );

      controller.add(const TerminalUiEvent.closed());
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('stream done also fires onClosed', (tester) async {
      final controller = StreamController<TerminalUiEvent>();
      var closed = 0;

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            onClosed: () => closed++,
          ),
        ),
      );

      await controller.close();
      await tester.pump();
      expect(closed, 1);
    });
  });

  group('TerminalGridView — resize reporting', () {
    testWidgets('reports whole-cell cols/rows that fit the constraint', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      int? cols;
      int? rows;

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            onResize: (c, r) {
              cols = c;
              rows = r;
            },
          ),
        ),
      );
      await tester.pump(); // post-frame resize callback

      expect(cols, isNotNull);
      expect(rows, isNotNull);
      expect(cols, greaterThan(0));
      expect(rows, greaterThan(0));
    });
  });

  group('TerminalGridView — scroll', () {
    testWidgets('plain wheel reports a negated whole-line scroll delta', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      final deltas = <int>[];

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            fontSize: 14,
            onScroll: deltas.add,
          ),
        ),
      );
      await tester.pump();

      // One row pitch at fontSize 14 (1.2 line-height) ≈ 16.8px; scroll three
      // rows down. Wheel-down (positive dy) scrolls toward the live screen, so
      // the reported delta is negative (positive = up into scrollback).
      final center = tester.getCenter(find.byType(TerminalGridView));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, 16.8 * 3)),
      );
      await tester.pump();

      expect(deltas, isNotEmpty);
      // Spec: positive wheel dy (down) → negative line delta (move toward
      // live screen), magnitude in whole rows.
      expect(deltas.first, lessThan(0));
      expect(deltas.first, -3);
    });

    testWidgets('a sub-line wheel delta reports nothing', (tester) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      final deltas = <int>[];

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            fontSize: 14,
            onScroll: deltas.add,
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(TerminalGridView));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      // 2px is well under a row pitch → rounds to zero lines → no callback.
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 2)));
      await tester.pump();

      expect(deltas, isEmpty);
    });
  });

  group('TerminalGridView — selection drag', () {
    // Spec: with no mouse tracking, a primary-button drag drives a local
    // text selection — pointer-down clears, then each move sets a
    // selection spanning the anchor to the current cell.
    testWidgets('a primary drag clears then sets a selection', (tester) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      var cleared = 0;
      final sels = <List<int>>[];
      final kinds = <TerminalSelectionKind>[];

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            fontSize: 14,
            onClearSelection: () => cleared++,
            onSetSelection: (sr, sc, er, ec, kind) async {
              sels.add([sr, sc, er, ec]);
              kinds.add(kind);
            },
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(TerminalGridView));
      final gesture = await tester.startGesture(
        topLeft + const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(cleared, 1, reason: 'pointer-down clears prior selection');
      expect(sels, isNotEmpty);
      // The first set is the anchor (collapsed); a later set spans to the
      // moved cell with a larger end column / row.
      expect(sels.first[0], sels.first[2]); // anchor row == end row
      expect(sels.last[3], greaterThan(sels.first[1]));
      // A single drag selects character-by-character (Simple geometry).
      expect(
        kinds,
        everyElement(TerminalSelectionKind.simple),
        reason: 'a plain drag is a simple selection',
      );
    });

    // Spec: a double-click on a cell drives a word (Semantic) selection and
    // a triple-click drives a whole-line (Lines) selection; the engine
    // expands a collapsed anchor==end span to the word / line.
    testWidgets('double-click selects a word, triple-click a line', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      final kinds = <TerminalSelectionKind>[];

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () => _frameWith('A'),
            events: controller.stream,
            fontSize: 14,
            onSetSelection: (sr, sc, er, ec, kind) async => kinds.add(kind),
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(TerminalGridView));
      // Three fast taps on the same cell → single, double, triple click.
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(
        kinds,
        containsAllInOrder(<TerminalSelectionKind>[
          TerminalSelectionKind.simple,
          TerminalSelectionKind.semantic,
          TerminalSelectionKind.lines,
        ]),
        reason: '1st tap simple, 2nd word, 3rd line',
      );
    });

    // Spec: when the program enabled mouse tracking, a drag is reported to
    // the program (press → move → release) instead of selecting locally.
    testWidgets('a drag under mouse tracking reports instead of selecting', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      var cleared = 0;
      final mouse = <TerminalMouseInput>[];

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () =>
                _frameWith('A', tracking: TerminalMouseTracking.buttonEvent),
            events: controller.stream,
            fontSize: 14,
            onClearSelection: () => cleared++,
            onSetSelection: (sr, sc, er, ec, kind) async {},
            onMouse: mouse.add,
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(TerminalGridView));
      final gesture = await tester.startGesture(
        topLeft + const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(cleared, 0, reason: 'no local selection under tracking');
      expect(mouse, isNotEmpty);
      expect(mouse.first.action, TerminalMouseAction.press);
      expect(mouse.first.button, TerminalMouseButton.left);
      expect(mouse.last.action, TerminalMouseAction.release);
      // Report coordinates are 1-based.
      expect(mouse.first.col, greaterThanOrEqualTo(1));
      expect(mouse.first.row, greaterThanOrEqualTo(1));
    });

    // Spec: a wheel under mouse tracking reports a wheel button instead of
    // scrolling scrollback locally.
    testWidgets('wheel under tracking reports wheel button, not scroll', (
      tester,
    ) async {
      final controller = StreamController<TerminalUiEvent>();
      addTearDown(controller.close);
      final deltas = <int>[];
      final mouse = <TerminalMouseInput>[];

      await tester.pumpWidget(
        _app(
          TerminalGridView.fromSource(
            snapshotProvider: () =>
                _frameWith('A', tracking: TerminalMouseTracking.click),
            events: controller.stream,
            fontSize: 14,
            onScroll: deltas.add,
            onMouse: mouse.add,
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(TerminalGridView));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 30)));
      await tester.pump();

      expect(deltas, isEmpty, reason: 'wheel went to the program');
      expect(mouse, hasLength(1));
      expect(mouse.single.button, TerminalMouseButton.wheelDown);
    });
  });
}
