import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../src/rust/api/terminal.dart';
import '../../theme/app_theme.dart';
import 'app_terminal_view.dart';
import 'terminal_cell_metrics.dart';
import 'terminal_grid_painter.dart';

/// Snapshot provider — returns the latest [TerminalFrame] to paint.
/// Injected so the view is testable with a synthetic frame instead of a
/// live `TerminalSession` (whose `snapshot()` reaches into Rust/FFI).
typedef TerminalSnapshotProvider = TerminalFrame Function();

/// Renders a live terminal from a Rust-owned [TerminalSession] using a
/// [CustomPaint] cell grid. Subscribes to the session event stream; on a
/// `Wakeup` it pulls a fresh `snapshot()` and schedules one repaint per
/// frame (coalesced via a post-frame gate, so a busy output burst that
/// fires many wakeups still repaints once per vsync).
///
/// Render + scroll only: keyboard input is owned by the host's `Focus`
/// surface (see `TerminalPane.handleKey`), which encodes keystrokes
/// Rust-side; selection gestures land in a later task. The host wires
/// [onTitle]/[onResetTitle]/[onClosed] callbacks; [onBell] defaults to a
/// no-op (visual/audible bell is a host concern wired later). The data is
/// Rust-owned; this widget holds only the latest pulled frame, never
/// mutating it Dart-side.
///
/// Sizing is reported back via [onResize] so the host can drive
/// `TerminalSession.resize` — this widget does not call FFI resize
/// itself, keeping it free of a live session in tests.
class TerminalGridView extends StatefulWidget {
  /// Live-session convenience constructor: pulls frames from
  /// `session.snapshot()` and listens to `session.events()`.
  TerminalGridView({
    super.key,
    required TerminalSession session,
    this.fontSize = 14.0,
    this.onTitle,
    this.onResetTitle,
    this.onClosed,
    this.onBell,
    this.onClipboardStore,
    this.onResize,
    this.onScroll,
    this.onPointerSignal,
  }) : snapshotProvider = session.snapshot,
       events = session.events();

  /// Dependency-injected constructor for tests / non-FFI hosts: supply a
  /// snapshot function and an event stream directly.
  const TerminalGridView.fromSource({
    super.key,
    required this.snapshotProvider,
    required this.events,
    this.fontSize = 14.0,
    this.onTitle,
    this.onResetTitle,
    this.onClosed,
    this.onBell,
    this.onClipboardStore,
    this.onResize,
    this.onScroll,
    this.onPointerSignal,
  });

  final TerminalSnapshotProvider snapshotProvider;
  final Stream<TerminalUiEvent> events;
  final double fontSize;

  /// Remote set the window/tab title (OSC 0/2).
  final void Function(String title)? onTitle;

  /// Remote reset the title to default.
  final VoidCallback? onResetTitle;

  /// Shell channel closed (remote EOF / exit).
  final VoidCallback? onClosed;

  /// Terminal bell rang (`\x07`).
  final VoidCallback? onBell;

  /// Remote requested storing text in the system clipboard (OSC 52).
  final void Function(String text)? onClipboardStore;

  /// Viewport size in cells changed (resize / first layout). The host
  /// forwards this to `TerminalSession.resize`.
  final void Function(int cols, int rows)? onResize;

  /// Mouse-wheel scroll over the grid, in whole-line deltas (positive =
  /// scroll up into scrollback). The host forwards this to
  /// `TerminalSession.scroll`. Ctrl-modified wheel events are routed to
  /// [onPointerSignal] instead (font zoom) and never reach here.
  final void Function(int lineDelta)? onScroll;

  /// Raw pointer-signal hook (e.g. Ctrl+wheel font zoom in the live pane).
  /// Receives every signal so the host can claim modified-wheel events; the
  /// view consumes plain wheel events itself for scrollback.
  final void Function(PointerSignalEvent event)? onPointerSignal;

  @override
  State<TerminalGridView> createState() => _TerminalGridViewState();
}

class _TerminalGridViewState extends State<TerminalGridView> {
  static const EdgeInsets _padding = EdgeInsets.all(AppTerminalView.padding);

  StreamSubscription<TerminalUiEvent>? _eventSub;
  late TerminalFrame _frame;
  int _frameRevision = 0;
  bool _repaintScheduled = false;

  int? _lastCols;
  int? _lastRows;

  @override
  void initState() {
    super.initState();
    _frame = widget.snapshotProvider();
    _subscribe();
  }

  @override
  void didUpdateWidget(TerminalGridView old) {
    super.didUpdateWidget(old);
    if (old.events != widget.events) {
      _eventSub?.cancel();
      _subscribe();
    }
    if (old.snapshotProvider != widget.snapshotProvider) {
      _pullFrame();
    }
  }

  void _subscribe() {
    _eventSub = widget.events.listen(_onEvent, onDone: widget.onClosed);
  }

  void _onEvent(TerminalUiEvent event) {
    switch (event) {
      case TerminalUiEvent_Wakeup():
        _scheduleRepaint();
      case TerminalUiEvent_Bell():
        widget.onBell?.call();
      case TerminalUiEvent_Title(:final title):
        widget.onTitle?.call(title);
      case TerminalUiEvent_ResetTitle():
        widget.onResetTitle?.call();
      case TerminalUiEvent_ClipboardStore(:final text):
        widget.onClipboardStore?.call(text);
      case TerminalUiEvent_Closed():
        widget.onClosed?.call();
    }
  }

  /// Coalesce a burst of `Wakeup` events into one frame pull per vsync:
  /// the gate bumps the revision at most once per frame even if the pump
  /// fired many wakeups (large paste, build output) since the last paint.
  void _scheduleRepaint() {
    if (_repaintScheduled) return;
    _repaintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repaintScheduled = false;
      if (!mounted) return;
      _pullFrame();
    });
  }

  void _pullFrame() {
    setState(() {
      _frame = widget.snapshotProvider();
      _frameRevision++;
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cellSize = measureMonoCell(
      fontSize: widget.fontSize,
      textScaler: MediaQuery.textScalerOf(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _reportSize(constraints, cellSize);
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: ColoredBox(
            color: AppTheme.bg2,
            child: CustomPaint(
              size: Size.infinite,
              painter: TerminalGridPainter(
                frame: _frame,
                frameRevision: _frameRevision,
                cellSize: cellSize,
                defaultBackground: AppTheme.bg2,
                cursorColor: AppTheme.termCursor,
                selectionColor: AppTheme.termSelection,
                fontSize: widget.fontSize,
                padding: _padding,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Plain wheel → scrollback (negate so wheel-up scrolls up into history,
  /// matching `TerminalSession.scroll`'s positive-up convention). A modified
  /// wheel (Ctrl) is handed to the host for font zoom and not consumed here.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) {
      widget.onPointerSignal?.call(event);
      return;
    }
    final onScroll = widget.onScroll;
    if (onScroll == null) return;
    final lines = (event.scrollDelta.dy / _cellHeightForScroll).round();
    if (lines == 0) return;
    onScroll(-lines);
  }

  /// Wheel delta is in pixels; divide by the row pitch to convert to whole
  /// scrollback lines. Re-measured lazily so a font-zoom keeps the conversion
  /// in step with the current cell height.
  double get _cellHeightForScroll =>
      measureMonoCell(fontSize: widget.fontSize).height;

  /// Compute how many whole cells fit the constraint and notify the host
  /// when the count changes. Floors to whole cells so a partial trailing
  /// cell never invites the remote PTY to wrap into a column the grid
  /// can't show.
  void _reportSize(BoxConstraints constraints, Size cellSize) {
    if (widget.onResize == null) return;
    if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) return;
    final innerW = constraints.maxWidth - _padding.horizontal;
    final innerH = constraints.maxHeight - _padding.vertical;
    if (cellSize.width <= 0 || cellSize.height <= 0) return;
    final cols = (innerW / cellSize.width).floor();
    final rows = (innerH / cellSize.height).floor();
    if (cols <= 0 || rows <= 0) return;
    if (cols == _lastCols && rows == _lastRows) return;
    _lastCols = cols;
    _lastRows = rows;
    // Defer out of layout — calling back synchronously during a
    // LayoutBuilder build would re-enter the host's setState mid-layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onResize?.call(cols, rows);
    });
  }
}
