import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_clipboard.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/terminal.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/terminal_clipboard.dart';
import 'package:letsflutssh/widgets/terminal/terminal_controller.dart';
import 'package:letsflutssh/widgets/terminal/terminal_grid_painter.dart';
import 'package:letsflutssh/widgets/terminal/terminal_view.dart';

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

/// Test [TerminalController] with injectable snapshot + repaint + optional UI
/// event stream — exercises the view without an FRB runtime. Records the
/// capability calls the view drives so the selection / mouse / scroll wiring
/// can be asserted.
class _FakeController extends TerminalController {
  _FakeController({
    required this.snapshotFn,
    Stream<TerminalUiEvent>? events,
    this.live = true,
    this.selection,
  }) : _events = events;

  final TerminalFrame Function() snapshotFn;
  final Stream<TerminalUiEvent>? _events;
  final bool live;
  String? selection;

  final repaintNotifier = ChangeNotifier();
  final setCalls = <List<Object>>[];
  final mouse = <TerminalMouseInput>[];
  var clears = 0;

  void notify() => repaintNotifier.notifyListeners();

  @override
  bool get isLive => live;

  @override
  TerminalFrame snapshot() => snapshotFn();

  @override
  Listenable get repaint => repaintNotifier;

  @override
  Stream<TerminalUiEvent>? get uiEvents => _events;

  @override
  void resize(int cols, int rows) {}

  @override
  Future<void> setSelection(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    TerminalSelectionKind kind,
  ) async {
    setCalls.add([startRow, startCol, endRow, endCol, kind]);
  }

  @override
  void clearSelection() => clears++;

  @override
  Future<String?> selectionText() async => selection;

  @override
  void sendMouse(TerminalMouseInput event) => mouse.add(event);
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: S.localizationsDelegates,
  supportedLocales: S.supportedLocales,
  theme: AppTheme.dark(),
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

TerminalGridPainter _readPainter(WidgetTester tester) {
  final cp = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(TerminalView),
      matching: find.byType(CustomPaint),
    ),
  );
  return cp.painter! as TerminalGridPainter;
}

void main() {
  group('TerminalView — render + repaint', () {
    testWidgets('paints the initial snapshot frame', (tester) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
          ),
        ),
      );

      final painter = _readPainter(tester);
      expect(painter.frame.cells.single.ch, 'A'.codeUnitAt(0));
      expect(painter.frameRevision, 0);
    });

    // Spec: a repaint notify pulls a fresh snapshot and bumps the revision.
    testWidgets('repaint notify pulls a fresh frame and bumps revision', (
      tester,
    ) async {
      var current = 'A';
      final c = _FakeController(snapshotFn: () => _frameWith(current));
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
          ),
        ),
      );
      expect(_readPainter(tester).frameRevision, 0);

      current = 'B';
      c.notify();
      await tester.pump(); // deliver
      await tester.pump(); // post-frame gate fires

      final painter = _readPainter(tester);
      expect(painter.frame.cells.single.ch, 'B'.codeUnitAt(0));
      expect(painter.frameRevision, 1);
    });

    // Regression: a repaint signal (Wakeup, bridged into `repaint`) must
    // schedule its OWN frame. In production no pump runs while the app is idle,
    // so without scheduleFrame the repaint would starve until an unrelated
    // frame — the terminal froze mid-stream and only caught up on a mouse move.
    // A plain pump() masks the bug, so deliver off-pump via runAsync and assert
    // a frame got requested.
    testWidgets('a repaint signal schedules its own frame (no external pump)', (
      tester,
    ) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(c.repaintNotifier.dispose);
      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'idle after settle',
      );

      await tester.runAsync(() async {
        c.notify();
        await Future<void>.delayed(Duration.zero);
      });

      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'a repaint must request a frame on its own',
      );
    });

    testWidgets('a burst of repaints coalesces to one pull', (tester) async {
      var pulls = 0;
      final c = _FakeController(
        snapshotFn: () {
          pulls++;
          return _frameWith('A');
        },
      );
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
          ),
        ),
      );
      final initialPulls = pulls; // initState pull(s)

      c
        ..notify()
        ..notify()
        ..notify();
      await tester.pump();
      await tester.pump();

      expect(pulls - initialPulls, 1);
      expect(_readPainter(tester).frameRevision, 1);
    });

    // Spec: read-only config hides the cursor; interactive shows it.
    testWidgets('showCursor follows the config', (tester) async {
      final live = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(live.repaintNotifier.dispose);
      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: live,
            config: const TerminalViewConfig.interactive(),
          ),
        ),
      );
      expect(_readPainter(tester).showCursor, isTrue);

      final ro = _FakeController(
        snapshotFn: () => _frameWith('A'),
        live: false,
      );
      addTearDown(ro.repaintNotifier.dispose);
      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: ro,
            config: const TerminalViewConfig.readOnly(),
          ),
        ),
      );
      expect(_readPainter(tester).showCursor, isFalse);
    });
  });

  group('TerminalView — UI event callbacks (live)', () {
    testWidgets('Title / ResetTitle / Bell / ClipboardStore / Closed forward', (
      tester,
    ) async {
      final events = StreamController<TerminalUiEvent>();
      addTearDown(events.close);
      final c = _FakeController(
        snapshotFn: () => _frameWith('A'),
        events: events.stream,
      );
      addTearDown(c.repaintNotifier.dispose);
      String? title;
      var reset = 0;
      var bell = 0;
      String? clip;
      var closed = 0;

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            onTitle: (t) => title = t,
            onResetTitle: () => reset++,
            onBell: () => bell++,
            onClipboardStore: (t) => clip = t,
            onClosed: () => closed++,
          ),
        ),
      );

      events
        ..add(const TerminalUiEvent.title(title: 'remote'))
        ..add(const TerminalUiEvent.resetTitle())
        ..add(const TerminalUiEvent.bell())
        ..add(const TerminalUiEvent.clipboardStore(text: 'copied'))
        ..add(const TerminalUiEvent.closed());
      await tester.pump();

      expect(title, 'remote');
      expect(reset, 1);
      expect(bell, 1);
      expect(clip, 'copied');
      expect(closed, 1);
    });
  });

  group('TerminalView — resize reporting', () {
    testWidgets('reports whole-cell cols/rows that fit the constraint', (
      tester,
    ) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(c.repaintNotifier.dispose);
      int? cols;
      int? rows;

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            onResize: (cc, rr) {
              cols = cc;
              rows = rr;
            },
          ),
        ),
      );
      await tester.pump();

      expect(cols, isNotNull);
      expect(rows, isNotNull);
      expect(cols, greaterThan(0));
      expect(rows, greaterThan(0));
    });
  });

  group('TerminalView — scroll', () {
    testWidgets('plain wheel reports a negated whole-line scroll delta', (
      tester,
    ) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(c.repaintNotifier.dispose);
      final deltas = <int>[];

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            fontSize: 14,
            onScroll: deltas.add,
          ),
        ),
      );
      await tester.pump();

      // One row pitch at fontSize 14 (1.2 line-height) ≈ 16.8px; scroll three
      // rows down. Wheel-down (positive dy) scrolls toward the live screen, so
      // the reported delta is negative (positive = up into scrollback).
      final center = tester.getCenter(find.byType(TerminalView));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, 16.8 * 3)),
      );
      await tester.pump();

      expect(deltas, isNotEmpty);
      expect(deltas.first, -3);
    });
  });

  group('TerminalView — selection drag', () {
    testWidgets('a primary drag clears then sets a simple selection', (
      tester,
    ) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            fontSize: 14,
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(TerminalView));
      final gesture = await tester.startGesture(
        topLeft + const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(c.clears, greaterThanOrEqualTo(1));
      expect(c.setCalls, isNotEmpty);
      expect(c.setCalls.first[0], c.setCalls.first[2]); // anchor row == end
      expect(
        c.setCalls.last[3] as int,
        greaterThan(c.setCalls.first[1] as int),
      );
      expect(
        c.setCalls.map((e) => e[4]),
        everyElement(TerminalSelectionKind.simple),
      );
    });

    testWidgets('double-click selects a word, triple-click a line', (
      tester,
    ) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'));
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            fontSize: 14,
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(TerminalView));
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(
        c.setCalls.map((e) => e[4]),
        containsAllInOrder(<TerminalSelectionKind>[
          TerminalSelectionKind.simple,
          TerminalSelectionKind.semantic,
          TerminalSelectionKind.lines,
        ]),
      );
    });

    testWidgets('a drag under mouse tracking reports instead of selecting', (
      tester,
    ) async {
      final c = _FakeController(
        snapshotFn: () =>
            _frameWith('A', tracking: TerminalMouseTracking.buttonEvent),
      );
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            fontSize: 14,
          ),
        ),
      );
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(TerminalView));
      final gesture = await tester.startGesture(
        topLeft + const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(c.clears, 0, reason: 'no local selection under tracking');
      expect(c.setCalls, isEmpty);
      expect(c.mouse, isNotEmpty);
      expect(c.mouse.first.action, TerminalMouseAction.press);
      expect(c.mouse.first.button, TerminalMouseButton.left);
      expect(c.mouse.last.action, TerminalMouseAction.release);
    });

    // Spec: Shift forces a local selection even under mouse tracking.
    testWidgets('Shift under mouse tracking forces local selection', (
      tester,
    ) async {
      final c = _FakeController(
        snapshotFn: () =>
            _frameWith('A', tracking: TerminalMouseTracking.buttonEvent),
      );
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            fontSize: 14,
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final topLeft = tester.getTopLeft(find.byType(TerminalView));
      final gesture = await tester.startGesture(
        topLeft + const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(c.mouse, isEmpty, reason: 'Shift overrides reporting');
      expect(c.setCalls, isNotEmpty);
    });

    testWidgets('wheel under tracking reports a wheel button, not scroll', (
      tester,
    ) async {
      final c = _FakeController(
        snapshotFn: () =>
            _frameWith('A', tracking: TerminalMouseTracking.click),
      );
      addTearDown(c.repaintNotifier.dispose);
      final deltas = <int>[];

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            fontSize: 14,
            onScroll: deltas.add,
          ),
        ),
      );
      await tester.pump();

      final center = tester.getCenter(find.byType(TerminalView));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 30)));
      await tester.pump();

      expect(deltas, isEmpty, reason: 'wheel went to the program');
      expect(c.mouse, hasLength(1));
      expect(c.mouse.single.button, TerminalMouseButton.wheelDown);
    });
  });

  group('TerminalView — context menu', () {
    testWidgets('shows Copy + Paste + Select All per the interactive config', (
      tester,
    ) async {
      final c = _FakeController(
        snapshotFn: () => _frameWith('A'),
        selection: 'something',
      );
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.interactive(),
            onCopy: () {},
            onPaste: () {},
          ),
        ),
      );
      await tester.pump();

      await _rightClickCenter(tester);

      expect(find.text(_copyLabel), findsOneWidget);
      expect(find.text(_pasteLabel), findsOneWidget);
      expect(find.text(_selectAllLabel), findsOneWidget);
    });

    // Spec: with no selection, Copy is omitted; a read-only surface with no
    // paste hook omits Paste.
    testWidgets('read-only menu omits Copy (no selection) and Paste', (
      tester,
    ) async {
      final c = _FakeController(
        snapshotFn: () => _frameWith('A'),
        live: false,
        selection: null,
      );
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.readOnly(),
          ),
        ),
      );
      await tester.pump();

      await _rightClickCenter(tester);

      expect(find.text(_copyLabel), findsNothing);
      expect(find.text(_pasteLabel), findsNothing);
      expect(find.text(_selectAllLabel), findsOneWidget);
    });
  });

  group('TerminalView — read-only copy via the built-in path', () {
    late List<String> secureWrites;

    setUp(() {
      secureWrites = [];
      SecureClipboard.debugRustWriterOverride = secureWrites.add;
      TerminalClipboard.debugSetSecureClipboard(
        SecureClipboard(rustWriter: secureWrites.add),
      );
      TerminalClipboard.debugHashOverride = (text) => 'h:${text.length}';
      TerminalClipboard.debugRustCompareAndClearOverride = (_) => true;
    });

    tearDown(() {
      TerminalClipboard.debugCancelPendingWipe();
      _clearClipboardMock();
      SecureClipboard.debugResetRustWriter();
      TerminalClipboard.debugResetHashOverride();
      TerminalClipboard.debugResetRustCompareAndClear();
      TerminalClipboard.debugResetSecureClipboard();
    });

    // Spec: a read-only selectable surface installs its own Focus + copy
    // shortcuts; Ctrl+C reads selectionText and routes it through the shared
    // clipboard path (stock clipboard for non-sensitive text), then clears.
    testWidgets('Ctrl+C copies selectionText to the clipboard', (tester) async {
      final c = _FakeController(
        snapshotFn: () => _frameWith('A'),
        live: false,
        selection: 'copied text',
      );
      addTearDown(c.repaintNotifier.dispose);
      String? lastWrite;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              lastWrite = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.readOnly(),
          ),
        ),
      );
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(TerminalView)));
      await tester.pump();

      await _copyWithCtrlC(tester);

      expect(lastWrite, 'copied text');
      expect(c.clears, greaterThanOrEqualTo(1));
    });

    // Spec: a sensitive selection routes through SecureClipboard, never the
    // stock pasteboard.
    testWidgets('Ctrl+C routes a sensitive selection through SecureClipboard', (
      tester,
    ) async {
      const secret =
          '-----BEGIN OPENSSH PRIVATE KEY-----\nABCD\n'
          '-----END OPENSSH PRIVATE KEY-----';
      final c = _FakeController(
        snapshotFn: () => _frameWith('A'),
        live: false,
        selection: secret,
      );
      addTearDown(c.repaintNotifier.dispose);
      var stockWrites = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') stockWrites++;
            return null;
          });

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.readOnly(),
          ),
        ),
      );
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(TerminalView)));
      await tester.pump();

      await _copyWithCtrlC(tester);

      expect(secureWrites, [secret]);
      expect(stockWrites, 0);
    });
  });

  group('TerminalView — non-selectable surface', () {
    testWidgets('installs no Focus layer', (tester) async {
      final c = _FakeController(snapshotFn: () => _frameWith('A'), live: false);
      addTearDown(c.repaintNotifier.dispose);

      await tester.pumpWidget(
        _app(
          TerminalView(
            controller: c,
            config: const TerminalViewConfig.readOnly(selectable: false),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(TerminalView),
          matching: find.byType(Focus),
        ),
        findsNothing,
      );
    });
  });
}

// Labels resolved from the default (English) localization for menu assertions.
const _copyLabel = 'Copy';
const _pasteLabel = 'Paste';
const _selectAllLabel = 'Select All';

Future<void> _rightClickCenter(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(TerminalView));
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.down(center, buttons: kSecondaryButton),
  );
  await tester.sendEventToBinding(pointer.up());
  await tester.pumpAndSettle();
}

void _clearClipboardMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
}

/// Send Ctrl+C on the real event loop so the discarded `Clipboard.setData`
/// future and the async mock handler settle before the synthetic-clock
/// teardown ("Cannot close sink while adding stream" otherwise).
Future<void> _copyWithCtrlC(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}
