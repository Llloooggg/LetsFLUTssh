import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../src/rust/api/terminal.dart';
import '../../theme/app_theme.dart';
import 'terminal_cell_metrics.dart';
import 'terminal_grid_painter.dart';
import 'terminal_pointer_input.dart';

/// Snapshot provider — returns the latest [TerminalFrame] to paint.
/// Injected so the view is testable with a synthetic frame instead of a
/// live `TerminalSession` (whose `snapshot()` reaches into Rust/FFI).
typedef TerminalSnapshotProvider = TerminalFrame Function();

/// Which phase of a mouse interaction a pointer event represents — kept
/// separate from [TerminalMouseAction] so the grid view picks the button
/// and modifiers once before crossing to the FRB DTO.
enum MouseActionKind { press, release, move }

/// Renders a live terminal from a Rust-owned [TerminalSession] using a
/// [CustomPaint] cell grid. Subscribes to the session event stream; on a
/// `Wakeup` it pulls a fresh `snapshot()` and schedules one repaint per
/// frame (coalesced via a post-frame gate, so a busy output burst that
/// fires many wakeups still repaints once per vsync).
///
/// Keyboard input is owned by the host's `Focus` surface (see
/// `TerminalPane.handleKey`), which encodes keystrokes Rust-side. This
/// widget owns pointer input: a primary-button drag drives a local text
/// selection (forwarded via [onSetSelection]) unless the running program
/// enabled mouse tracking and Shift is not held, in which case the
/// pointer is reported to the program via [onMouse]. The host wires
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
    this.onSetSelection,
    this.onClearSelection,
    this.onMouse,
    this.searchMatches = const [],
    this.activeMatchIndex = -1,
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
    this.onSetSelection,
    this.onClearSelection,
    this.onMouse,
    this.searchMatches = const [],
    this.activeMatchIndex = -1,
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

  /// Selection updated — the anchor and the current cell, both in absolute
  /// grid-line coordinates (negative = scrollback), plus the geometry the
  /// gesture chose: a drag is [TerminalSelectionKind.simple]; a double-click
  /// is [TerminalSelectionKind.semantic] (whole word) and a triple-click is
  /// [TerminalSelectionKind.lines] (whole line), both collapsed to a single
  /// cell since the engine expands them. The host forwards this to
  /// `TerminalSession.setSelection`. It returns a future the view awaits
  /// before pulling a fresh snapshot, because the engine does not emit a
  /// `Wakeup` for a host-driven selection — without the pull the highlight
  /// would not paint until the next remote output.
  final Future<void> Function(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    TerminalSelectionKind kind,
  )?
  onSetSelection;

  /// A click that starts a new drag clears any prior selection. The host
  /// forwards this to `TerminalSession.clearSelection`.
  final VoidCallback? onClearSelection;

  /// A mouse event to forward to the running program (mouse-tracking mode
  /// on, no Shift override). The host forwards this to
  /// `TerminalSession.sendMouse`.
  final void Function(TerminalMouseInput event)? onMouse;

  /// Search matches in absolute grid-line coordinates (negative =
  /// scrollback). Projected onto the live viewport each build so the
  /// highlights track scrolling. Empty when no search is active.
  final List<TerminalMatch> searchMatches;

  /// Index of the focused match within [searchMatches], painted in a
  /// stronger color. `-1` when none is focused.
  final int activeMatchIndex;

  @override
  State<TerminalGridView> createState() => _TerminalGridViewState();
}

class _TerminalGridViewState extends State<TerminalGridView> {
  static const EdgeInsets _padding = EdgeInsets.all(kTerminalPadding);

  StreamSubscription<TerminalUiEvent>? _eventSub;
  late TerminalFrame _frame;
  int _frameRevision = 0;
  bool _repaintScheduled = false;

  int? _lastCols;
  int? _lastRows;

  /// Cell pitch from the last build, captured so pointer handlers (which
  /// run outside build) map pixels to cells with the same metrics the
  /// painter used. Set on every build before any pointer event can fire.
  Size _cellSize = Size.zero;

  /// The anchor cell of an in-progress local text-selection drag, in
  /// absolute grid-line coordinates. Null when no selection drag is
  /// active. A non-null value also means the pointer is captured for
  /// selection, so moves extend it rather than re-routing.
  TerminalCellCoord? _selectionAnchor;

  /// Whether the in-progress pointer-down is being reported to the program
  /// (mouse-tracking mode) rather than driving a local selection. Latched
  /// at pointer-down so a drag stays in the mode it started in.
  bool _pointerReporting = false;

  /// Multi-tap run state for word/line selection: the count of consecutive
  /// same-cell presses (1 = single, 2 = double, 3 = triple, capped), the
  /// cell of the previous press, and when it landed. Folded forward by
  /// [nextTapCount] on each local pointer-down. `_tapKind` is the geometry
  /// the current run drives; a drag (move) keeps the press's kind so a
  /// double-click-then-drag extends a word selection rather than collapsing
  /// to a character one.
  int _tapCount = 0;
  TerminalCellCoord? _lastPressCell;
  DateTime _lastPressTime = DateTime.fromMillisecondsSinceEpoch(0);
  TerminalSelectionKind _tapKind = TerminalSelectionKind.simple;

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
    _cellSize = cellSize;
    final highlights = highlightRectsForMatches(
      matches: widget.searchMatches,
      displayOffset: _frame.displayOffset,
      rows: _frame.rows,
    );
    final active = _activeHighlight(highlights);
    return LayoutBuilder(
      builder: (context, constraints) {
        _reportSize(constraints, cellSize);
        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
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
                searchHighlights: highlights,
                searchHighlightColor: AppTheme.searchHighlight.withValues(
                  alpha: 0.35,
                ),
                activeSearchHighlight: active,
                activeSearchHighlightColor: AppTheme.searchHighlight.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The highlight rect for the focused match, or null when the active
  /// index is out of range or its match is scrolled off-viewport. The
  /// active match is projected separately (not by index into [highlights])
  /// because off-viewport matches are dropped from that list, so the index
  /// would no longer line up.
  TerminalHighlightRect? _activeHighlight(List<TerminalHighlightRect> _) {
    final i = widget.activeMatchIndex;
    if (i < 0 || i >= widget.searchMatches.length) return null;
    final single = highlightRectsForMatches(
      matches: [widget.searchMatches[i]],
      displayOffset: _frame.displayOffset,
      rows: _frame.rows,
    );
    return single.isEmpty ? null : single.first;
  }

  /// Map a pointer event's local position to a cell using the last-built
  /// cell metrics and the current frame's scroll offset. Returns null when
  /// the metrics are not measured yet (no build) so an early event is a
  /// no-op rather than a divide-by-zero.
  TerminalCellCoord? _cellFor(PointerEvent event) {
    if (_cellSize.width <= 0 || _cellSize.height <= 0) return null;
    return pointerToCell(
      localOffset: event.localPosition,
      padding: _padding,
      cellSize: _cellSize,
      cols: _frame.cols,
      rows: _frame.rows,
      displayOffset: _frame.displayOffset,
    );
  }

  /// Translate a pointer button into the report's mouse button. Only the
  /// primary (left), secondary (right), and tertiary (middle) buttons map;
  /// any other returns null so we do not forge a report for it.
  TerminalMouseButton? _reportButton(int buttons) {
    if (buttons & kPrimaryMouseButton != 0) return TerminalMouseButton.left;
    if (buttons & kSecondaryMouseButton != 0) {
      return TerminalMouseButton.right;
    }
    if (buttons & kTertiaryButton != 0) return TerminalMouseButton.middle;
    return null;
  }

  /// Pointer-down: decide between forwarding a mouse report to the program
  /// and starting a local text selection. Mouse-tracking mode reports the
  /// press unless Shift forces local selection (standard terminal override);
  /// otherwise
  /// the down clears any prior selection and anchors a new drag.
  void _onPointerDown(PointerDownEvent event) {
    final cell = _cellFor(event);
    if (cell == null) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final routing = routePointerGesture(
      tracking: _frame.mouseTracking,
      shiftPressed: shift,
    );
    if (routing == PointerRouting.report) {
      _pointerReporting = true;
      _sendMouse(cell, MouseActionKind.press, event.buttons, shift);
      return;
    }
    _pointerReporting = false;
    // Only the primary button drives a local selection; secondary/tertiary
    // are reserved for the context menu / paste handled by the host.
    if (event.buttons & kPrimaryMouseButton == 0) return;
    final now = DateTime.now();
    _tapCount = nextTapCount(
      previousCount: _tapCount,
      previousCell: _lastPressCell,
      sincePrevious: now.difference(_lastPressTime),
      currentCell: cell,
    );
    _lastPressCell = cell;
    _lastPressTime = now;
    _tapKind = selectionKindForTapCount(_tapCount);
    widget.onClearSelection?.call();
    _selectionAnchor = cell;
    // A double / triple click collapses anchor and end onto one cell; the
    // engine expands Semantic to the word and Lines to the whole line.
    _setSelection(cell, cell, _tapKind);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final cell = _cellFor(event);
    if (cell == null) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (_pointerReporting) {
      _sendMouse(cell, MouseActionKind.move, event.buttons, shift);
      return;
    }
    final anchor = _selectionAnchor;
    if (anchor == null) return;
    // Keep the press's geometry while dragging — a double-click-then-drag
    // extends the word selection, not a character one.
    _setSelection(anchor, cell, _tapKind);
  }

  void _onPointerUp(PointerUpEvent event) {
    final cell = _cellFor(event);
    if (_pointerReporting) {
      _pointerReporting = false;
      if (cell != null) {
        _sendMouse(
          cell,
          MouseActionKind.release,
          event.buttons,
          HardwareKeyboard.instance.isShiftPressed,
        );
      }
      return;
    }
    final anchor = _selectionAnchor;
    _selectionAnchor = null;
    // A single click that did not move (anchor == release cell) leaves a
    // collapsed 1-cell selection the user did not intend — clear it so a
    // later Ctrl+Shift+C does not copy a stray glyph. A drag that moved, or a
    // double / triple click (which the engine expanded to a word / line),
    // keeps its selection set until the next click / copy.
    if (anchor != null &&
        cell != null &&
        anchor == cell &&
        _tapKind == TerminalSelectionKind.simple) {
      widget.onClearSelection?.call();
    }
  }

  void _setSelection(
    TerminalCellCoord start,
    TerminalCellCoord end,
    TerminalSelectionKind kind,
  ) {
    final onSetSelection = widget.onSetSelection;
    if (onSetSelection == null) return;
    unawaited(
      onSetSelection(
        start.absoluteRow,
        start.col,
        end.absoluteRow,
        end.col,
        kind,
      ).then((_) {
        // The engine does not raise a Wakeup for a host-driven
        // selection, so pull a fresh frame to paint the highlight.
        if (mounted) _pullFrame();
      }),
    );
  }

  void _sendMouse(
    TerminalCellCoord cell,
    MouseActionKind kind,
    int buttons,
    bool shift,
  ) {
    final onMouse = widget.onMouse;
    if (onMouse == null) return;
    final TerminalMouseButton button;
    final TerminalMouseAction action;
    switch (kind) {
      case MouseActionKind.press:
        final b = _reportButton(buttons);
        if (b == null) return;
        button = b;
        action = TerminalMouseAction.press;
      case MouseActionKind.release:
        // The button bitfield is already cleared on release; report the
        // primary as the canonical released button (SGR carries the real
        // identity, the legacy form collapses to "released" anyway).
        button = TerminalMouseButton.left;
        action = TerminalMouseAction.release;
      case MouseActionKind.move:
        button = _reportButton(buttons) ?? TerminalMouseButton.none;
        action = TerminalMouseAction.move;
    }
    onMouse(
      TerminalMouseInput(
        button: button,
        action: action,
        // The report is 1-based; the viewport row maps directly (row 0 is
        // the top visible line, report row 1).
        col: cell.col + 1,
        row: cell.viewportRow + 1,
        shift: shift,
        alt: HardwareKeyboard.instance.isAltPressed,
        ctrl: HardwareKeyboard.instance.isControlPressed,
      ),
    );
  }

  /// Plain wheel → scrollback (negate so wheel-up scrolls up into history,
  /// matching `TerminalSession.scroll`'s positive-up convention). A modified
  /// wheel (Ctrl) is handed to the host for font zoom and not consumed here.
  /// Under mouse-tracking mode (no Shift) the wheel is reported to the
  /// program as buttons 64/65 instead of scrolling scrollback.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) {
      widget.onPointerSignal?.call(event);
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final routing = routeWheelGesture(
      tracking: _frame.mouseTracking,
      shiftPressed: shift,
    );
    if (routing == PointerRouting.report) {
      _reportWheel(event, shift);
      return;
    }
    final onScroll = widget.onScroll;
    if (onScroll == null) return;
    final lines = (event.scrollDelta.dy / _cellHeightForScroll).round();
    if (lines == 0) return;
    onScroll(-lines);
  }

  /// Forward a wheel notch to the program as a wheel-up / wheel-down mouse
  /// report at the pointer's cell. One report per notch direction; a wheel
  /// has no release in the mouse-reporting protocol.
  void _reportWheel(PointerScrollEvent event, bool shift) {
    final onMouse = widget.onMouse;
    if (onMouse == null || event.scrollDelta.dy == 0) return;
    final cell = _cellFor(event);
    if (cell == null) return;
    onMouse(
      TerminalMouseInput(
        button: event.scrollDelta.dy < 0
            ? TerminalMouseButton.wheelUp
            : TerminalMouseButton.wheelDown,
        action: TerminalMouseAction.press,
        col: cell.col + 1,
        row: cell.viewportRow + 1,
        shift: shift,
        alt: HardwareKeyboard.instance.isAltPressed,
        ctrl: HardwareKeyboard.instance.isControlPressed,
      ),
    );
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
