import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../src/rust/api/terminal.dart';
import '../../theme/app_theme.dart';
import '../../utils/terminal_clipboard.dart';
import '../core/context_menu.dart';
import '../core/shortcut_registry.dart' show AppShortcut;
import 'terminal_cell_metrics.dart';
import 'terminal_controller.dart';
import 'terminal_grid_painter.dart';
import 'terminal_pointer_input.dart';

/// Which phase of a mouse interaction a pointer event represents — kept
/// separate from [TerminalMouseAction] so the view picks the button and
/// modifiers once before crossing to the FRB DTO.
enum MouseActionKind { press, release, move }

/// Feature flags for a [TerminalView]. The view is the single terminal
/// renderer; the flags select which features the painter wiring exposes for a
/// given surface — the interactive SSH pane turns everything on, the read-only
/// replay surfaces (progress, recording playback, log viewer) turn input /
/// mouse / paste / search off but keep select + copy.
///
/// Each flag is independent so a surface composes exactly the capability it
/// needs; the two factory constructors cover the common pairs.
@immutable
class TerminalViewConfig {
  const TerminalViewConfig({
    required this.interactive,
    required this.selectable,
    required this.pasteable,
    required this.mouseReportable,
    required this.searchable,
    required this.showCursor,
  });

  /// Interactive SSH pane: every feature on, cursor visible. Keyboard input is
  /// routed through the host's key path (`onKey`), so the host stays the owner
  /// of the focus surface and the shortcut dispatch.
  const TerminalViewConfig.interactive()
    : interactive = true,
      selectable = true,
      pasteable = true,
      mouseReportable = true,
      searchable = true,
      showCursor = true;

  /// Read-only replay surface: select + copy by default, cursor hidden, no
  /// input / mouse reporting / paste / search. Individual flags can be relaxed
  /// (e.g. a fully non-interactive surface passes `selectable: false`).
  const TerminalViewConfig.readOnly({
    this.selectable = true,
    this.showCursor = false,
    this.pasteable = false,
    this.interactive = false,
    this.mouseReportable = false,
    this.searchable = false,
  });

  /// Keyboard input is routed to the host's [TerminalView.onKey] handler.
  final bool interactive;

  /// Drag-select + copy + select-all are enabled.
  final bool selectable;

  /// Paste (shortcut handled by the host's [TerminalView.onKey]; the context
  /// menu adds a Paste item that calls [TerminalView.onPaste]).
  final bool pasteable;

  /// Pointer events route to `sendMouse` when the running program enabled
  /// mouse tracking (Shift forces a local selection instead).
  final bool mouseReportable;

  /// In-terminal search is available (the host owns the search bar).
  final bool searchable;

  /// Whether the painter draws the cursor.
  final bool showCursor;
}

/// The single terminal renderer over a [TerminalController]. Draws the
/// Rust-owned grid through the shared [TerminalGridPainter] and routes pointer
/// input per its [config]: a primary-button drag drives a local text selection
/// (unless mouse tracking is active and Shift is not held, when the pointer is
/// reported to the program); a right-click (when not mouse-reporting) opens a
/// Copy / Paste / Select-All menu built from the enabled capabilities; a plain
/// wheel scrolls scrollback (Ctrl+wheel is handed to the host for font zoom).
///
/// Keyboard input is owned by the host's `Focus` surface (the live pane's
/// `handleKey`), which encodes keystrokes Rust-side and dispatches copy / paste
/// / search shortcuts; this view forwards key events to [onKey] when
/// [TerminalViewConfig.interactive] is set, and installs its own focusable
/// surface only when [TerminalViewConfig.selectable] is set without
/// [TerminalViewConfig.interactive] (the read-only surfaces, whose copy
/// shortcuts have no host).
///
/// Repaints when the controller's `repaint` notifies; on each notify it
/// re-pulls a snapshot — the grid is Rust-owned and never cached Dart-side. A
/// `Wakeup` from the live controller schedules its OWN frame (post-frame gate
/// + `scheduleFrame`) so streamed output repaints while the app is otherwise
/// idle. Sizing is reported via [onResize] so the host drives the engine
/// resize.
class TerminalView extends StatefulWidget {
  const TerminalView({
    super.key,
    required this.controller,
    required this.config,
    this.fontSize = 14.0,
    this.onTitle,
    this.onResetTitle,
    this.onClosed,
    this.onBell,
    this.onClipboardStore,
    this.onResize,
    this.onScroll,
    this.onPointerSignal,
    this.onKey,
    this.onCopy,
    this.onPaste,
    this.reportResize = false,
    this.searchMatches = const [],
    this.activeMatchIndex = -1,
  });

  final TerminalController controller;
  final TerminalViewConfig config;
  final double fontSize;

  /// Remote set the window/tab title (OSC 0/2). Live-only.
  final void Function(String title)? onTitle;

  /// Remote reset the title to default. Live-only.
  final VoidCallback? onResetTitle;

  /// Shell channel closed (remote EOF / exit) or the event stream ended.
  final VoidCallback? onClosed;

  /// Terminal bell rang (`\x07`). Live-only.
  final VoidCallback? onBell;

  /// Remote requested storing text in the system clipboard (OSC 52).
  final void Function(String text)? onClipboardStore;

  /// Viewport size in cells changed (resize / first layout). The host forwards
  /// this to the controller's `resize`. Independent of [reportResize], which
  /// only gates the *convenience* default wiring; supplying [onResize]
  /// directly always reports.
  final void Function(int cols, int rows)? onResize;

  /// Mouse-wheel scroll over the grid, in whole-line deltas (positive = up
  /// into scrollback). Ctrl-modified wheel events are routed to
  /// [onPointerSignal] instead (font zoom) and never reach here.
  final void Function(int lineDelta)? onScroll;

  /// Raw pointer-signal hook (e.g. Ctrl+wheel font zoom in the live pane).
  /// Receives every signal so the host can claim modified-wheel events; the
  /// view consumes plain wheel events itself for scrollback.
  final void Function(PointerSignalEvent event)? onPointerSignal;

  /// Keyboard event for an interactive surface — the host encodes it Rust-side
  /// and dispatches shortcuts. Null disables keyboard input. The view does not
  /// install its own key handler when this is set; the host's `Focus` owns it.
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// Copy the active selection. Wired to the context-menu Copy item and, on
  /// the read-only surfaces, to the view's own copy shortcuts. The host reads
  /// the controller's `selectionText` and routes it through the shared
  /// clipboard path. When null on a selectable surface the view falls back to
  /// its built-in copy (read `selectionText`, write the secure clipboard).
  final VoidCallback? onCopy;

  /// Paste from the clipboard. Wired to the context-menu Paste item when
  /// [TerminalViewConfig.pasteable] is set.
  final VoidCallback? onPaste;

  /// When true and no explicit [onResize] is supplied, the laid-out cell count
  /// is reported through the controller's `resize`. Mirrors the read-only
  /// surfaces' convenience wiring; the live pane passes [onResize] directly.
  final bool reportResize;

  /// Search matches in absolute grid-line coordinates (negative = scrollback),
  /// projected onto the live viewport each build. Empty when search is off.
  final List<TerminalMatch> searchMatches;

  /// Index of the focused match within [searchMatches], painted stronger. `-1`
  /// when none is focused.
  final int activeMatchIndex;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  static const EdgeInsets _padding = EdgeInsets.all(kTerminalPadding);

  /// Plain `Ctrl+C` / `Cmd+C` copy, plus the live pane's `Ctrl+Shift+C`. Only
  /// armed on the read-only surfaces (selectable without interactive) — the
  /// live pane owns its own key path, where plain `Ctrl+C` is reserved for
  /// SIGINT and only `Ctrl+Shift+C` copies.
  static const _copyActivators = <ShortcutActivator>[
    SingleActivator(LogicalKeyboardKey.keyC, control: true),
    SingleActivator(LogicalKeyboardKey.keyC, meta: true),
    SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true),
  ];

  StreamSubscription<TerminalUiEvent>? _eventSub;
  late TerminalFrame _frame;
  int _frameRevision = 0;
  bool _repaintScheduled = false;

  int? _lastCols;
  int? _lastRows;

  /// Cell pitch from the last build, captured so pointer handlers (which run
  /// outside build) map pixels to cells with the same metrics the painter
  /// used. Set on every build before any pointer event can fire.
  Size _cellSize = Size.zero;

  /// The anchor cell of an in-progress local text-selection drag, in absolute
  /// grid-line coordinates. Null when no selection drag is active.
  TerminalCellCoord? _selectionAnchor;

  /// Whether the in-progress pointer-down is being reported to the program
  /// (mouse-tracking mode) rather than driving a local selection. Latched at
  /// pointer-down so a drag stays in the mode it started in.
  bool _pointerReporting = false;

  /// Multi-tap run state for word/line selection: the count of consecutive
  /// same-cell presses (1 = single, 2 = double, 3 = triple, capped), the cell
  /// of the previous press, and when it landed. `_tapKind` is the geometry the
  /// current run drives; a drag keeps the press's kind so a double-click-drag
  /// extends a word selection.
  int _tapCount = 0;
  TerminalCellCoord? _lastPressCell;
  DateTime _lastPressTime = DateTime.fromMillisecondsSinceEpoch(0);
  TerminalSelectionKind _tapKind = TerminalSelectionKind.simple;

  /// Owned focus node for the read-only copy shortcuts — only attached when
  /// the view installs its own key handler (see [_ownsKeyHandling]).
  FocusNode? _focus;

  /// True when the view installs its own focusable surface for copy shortcuts:
  /// selectable but NOT interactive (the read-only surfaces). An interactive
  /// surface routes keys through the host's `Focus`/[onKey] instead.
  bool get _ownsKeyHandling =>
      widget.config.selectable && !widget.config.interactive;

  @override
  void initState() {
    super.initState();
    // A config that turns on input / paste / mouse reporting must be paired
    // with a live controller — the replay adapter no-ops those, so the pairing
    // would silently do nothing. Caught in debug so a misconfigured surface
    // fails loud rather than rendering an inert "interactive" terminal.
    assert(
      widget.controller.isLive ||
          !(widget.config.interactive ||
              widget.config.pasteable ||
              widget.config.mouseReportable ||
              widget.config.searchable),
      'live-only config flags require a live controller',
    );
    if (_ownsKeyHandling) {
      _focus = FocusNode(debugLabel: 'TerminalView');
    }
    _frame = widget.controller.snapshot();
    _subscribe();
  }

  void _subscribe() {
    widget.controller.repaint.addListener(_scheduleRepaint);
    final uiEvents = widget.controller.uiEvents;
    if (uiEvents != null) {
      _eventSub = uiEvents.listen(_onUiEvent);
    }
  }

  void _unsubscribe() {
    widget.controller.repaint.removeListener(_scheduleRepaint);
    _eventSub?.cancel();
    _eventSub = null;
  }

  @override
  void didUpdateWidget(TerminalView old) {
    super.didUpdateWidget(old);
    if (!identical(widget.controller, old.controller)) {
      old.controller.repaint.removeListener(_scheduleRepaint);
      _eventSub?.cancel();
      _eventSub = null;
      _subscribe();
      _pullFrame();
    }
  }

  void _onUiEvent(TerminalUiEvent event) {
    switch (event) {
      case TerminalUiEvent_Wakeup():
        // The live controller already bridges Wakeup into `repaint`; an
        // explicit Wakeup on the UI stream would be redundant, but handle it
        // defensively so a future controller that surfaces it still repaints.
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

  /// Coalesce a burst of repaint signals into one frame pull per vsync: the
  /// gate bumps the revision at most once per frame even if the controller
  /// notified many times (large paste, build output) since the last paint.
  void _scheduleRepaint() {
    if (_repaintScheduled) return;
    _repaintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repaintScheduled = false;
      if (!mounted) return;
      _pullFrame();
    });
    // A post-frame callback only runs once a frame is actually produced. When
    // the app is otherwise idle (no animation, no pointer/key input) nothing
    // schedules one, so a pump Wakeup would starve until the next unrelated
    // frame — the terminal would freeze mid-stream and only catch up on a
    // mouse move. Force a frame so streamed output (vim redraw, htop, long
    // build logs) repaints on its own.
    WidgetsBinding.instance.scheduleFrame();
  }

  void _pullFrame() {
    setState(() {
      _frame = widget.controller.snapshot();
      _frameRevision++;
    });
  }

  @override
  void dispose() {
    _unsubscribe();
    _focus?.dispose();
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
    final active = _activeHighlight();
    return LayoutBuilder(
      builder: (context, constraints) {
        _reportSize(constraints, cellSize);
        final grid = ColoredBox(
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
              showCursor: widget.config.showCursor,
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
        );
        return _wrapInteraction(grid);
      },
    );
  }

  /// Wrap the painted grid in the pointer / focus layers the config calls for.
  /// A surface with no interaction (a non-selectable read-only view) returns
  /// the bare grid. Selectable / interactive / mouse-reporting surfaces get a
  /// [Listener]; a read-only selectable surface also gets a [Focus] so its
  /// copy shortcuts arm once clicked.
  Widget _wrapInteraction(Widget grid) {
    final config = widget.config;
    final needsPointer =
        config.selectable || config.mouseReportable || widget.onScroll != null;
    if (!needsPointer && !_ownsKeyHandling) return grid;
    final listener = Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: grid,
    );
    if (!_ownsKeyHandling) return listener;
    return Focus(focusNode: _focus, onKeyEvent: _handleKey, child: listener);
  }

  /// The highlight rect for the focused match, or null when the active index
  /// is out of range or its match is scrolled off-viewport. Projected
  /// separately (not by index into the visible list) because off-viewport
  /// matches are dropped, so the index would no longer line up.
  TerminalHighlightRect? _activeHighlight() {
    final i = widget.activeMatchIndex;
    if (i < 0 || i >= widget.searchMatches.length) return null;
    final single = highlightRectsForMatches(
      matches: [widget.searchMatches[i]],
      displayOffset: _frame.displayOffset,
      rows: _frame.rows,
    );
    return single.isEmpty ? null : single.first;
  }

  /// Map a pointer event's local position to a cell using the last-built cell
  /// metrics and the current frame's scroll offset. Returns null when the
  /// metrics are not measured yet (no build) so an early event is a no-op.
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

  /// Translate a pointer button into the report's mouse button. Only primary
  /// (left), secondary (right), and tertiary (middle) map; any other returns
  /// null so a report is not forged for it.
  TerminalMouseButton? _reportButton(int buttons) {
    if (buttons & kPrimaryMouseButton != 0) return TerminalMouseButton.left;
    if (buttons & kSecondaryMouseButton != 0) {
      return TerminalMouseButton.right;
    }
    if (buttons & kTertiaryButton != 0) return TerminalMouseButton.middle;
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    final cell = _cellFor(event);
    if (cell == null) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (widget.config.mouseReportable) {
      final routing = routePointerGesture(
        tracking: _frame.mouseTracking,
        shiftPressed: shift,
      );
      if (routing == PointerRouting.report) {
        _pointerReporting = true;
        _sendMouse(cell, MouseActionKind.press, event.buttons, shift);
        return;
      }
    }
    _pointerReporting = false;
    if (!widget.config.selectable) return;
    // Secondary button opens the context menu (when not mouse-reporting) and
    // does not start a selection.
    if (event.buttons & kSecondaryButton != 0) {
      _showContextMenu(event.position);
      return;
    }
    // Only the primary button drives a local selection.
    if (event.buttons & kPrimaryMouseButton == 0) return;
    _focus?.requestFocus();
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
    widget.controller.clearSelection();
    _selectionAnchor = cell;
    // A double / triple click collapses anchor and end onto one cell; the
    // engine expands Semantic to the word and Lines to the whole line.
    _setSelection(cell, cell, _tapKind);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final cell = _cellFor(event);
    if (cell == null) return;
    if (_pointerReporting) {
      _sendMouse(
        cell,
        MouseActionKind.move,
        event.buttons,
        HardwareKeyboard.instance.isShiftPressed,
      );
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
    // collapsed 1-cell selection the user did not intend — clear it so a later
    // copy does not grab a stray glyph. A drag that moved, or a double / triple
    // click (expanded to a word / line by the engine), keeps its selection.
    if (anchor != null &&
        cell != null &&
        anchor == cell &&
        _tapKind == TerminalSelectionKind.simple) {
      widget.controller.clearSelection();
    }
  }

  void _setSelection(
    TerminalCellCoord start,
    TerminalCellCoord end,
    TerminalSelectionKind kind,
  ) {
    unawaited(
      widget.controller
          .setSelection(
            start.absoluteRow,
            start.col,
            end.absoluteRow,
            end.col,
            kind,
          )
          .then((_) {
            // The engine does not raise a Wakeup for a host-driven selection,
            // so pull a fresh frame to paint the highlight.
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
    widget.controller.sendMouse(
      TerminalMouseInput(
        button: button,
        action: action,
        // The report is 1-based; the viewport row maps directly (row 0 is the
        // top visible line, report row 1).
        col: cell.col + 1,
        row: cell.viewportRow + 1,
        shift: shift,
        alt: HardwareKeyboard.instance.isAltPressed,
        ctrl: HardwareKeyboard.instance.isControlPressed,
      ),
    );
  }

  /// Plain wheel → scrollback (negate so wheel-up scrolls up into history). A
  /// modified wheel (Ctrl) is handed to the host for font zoom and not consumed
  /// here. Under mouse-tracking mode (no Shift) the wheel is reported to the
  /// program as buttons 64/65 instead of scrolling scrollback.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) {
      widget.onPointerSignal?.call(event);
      return;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (widget.config.mouseReportable) {
      final routing = routeWheelGesture(
        tracking: _frame.mouseTracking,
        shiftPressed: shift,
      );
      if (routing == PointerRouting.report) {
        _reportWheel(event, shift);
        return;
      }
    }
    final onScroll = widget.onScroll;
    if (onScroll == null) return;
    final lines = (event.scrollDelta.dy / _cellHeightForScroll).round();
    if (lines == 0) return;
    onScroll(-lines);
  }

  /// Forward a wheel notch to the program as a wheel-up / wheel-down mouse
  /// report at the pointer's cell. One report per notch direction; a wheel has
  /// no release in the mouse-reporting protocol.
  void _reportWheel(PointerScrollEvent event, bool shift) {
    if (event.scrollDelta.dy == 0) return;
    final cell = _cellFor(event);
    if (cell == null) return;
    widget.controller.sendMouse(
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

  // ── Read-only copy shortcuts + context menu ────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    for (final activator in _copyActivators) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        _copy();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Copy the active selection. Prefers the host's [TerminalView.onCopy] (the
  /// live pane routes through its own clipboard path); falls back to the
  /// built-in read-only copy.
  void _copy() {
    final onCopy = widget.onCopy;
    if (onCopy != null) {
      onCopy();
      return;
    }
    unawaited(_copyBuiltIn());
  }

  /// Built-in copy for the read-only surfaces with no host copy hook: read the
  /// engine's selection text and route it through the shared clipboard path,
  /// then clear the highlight. No-op when nothing is selected.
  Future<void> _copyBuiltIn() async {
    final text = await widget.controller.selectionText();
    if (text == null || text.isEmpty) return;
    TerminalClipboard.copyText(text);
    widget.controller.clearSelection();
  }

  void _selectAll() {
    final rows = _frame.rows;
    final cols = _frame.cols;
    if (rows <= 0 || cols <= 0) return;
    // Cover the whole scrollback + viewport: from the top of history
    // (`-historySize`) to the bottom of the live screen, as a Lines selection
    // so the engine trims trailing blanks per row.
    final topRow = -_frame.historySize;
    _setSelection(
      TerminalCellCoord(viewportRow: 0, col: 0, absoluteRow: topRow),
      TerminalCellCoord(
        viewportRow: rows - 1,
        col: cols - 1,
        absoluteRow: rows - 1,
      ),
      TerminalSelectionKind.lines,
    );
  }

  void _showContextMenu(Offset position) {
    unawaited(_showContextMenuAsync(position));
  }

  Future<void> _showContextMenuAsync(Offset position) async {
    final config = widget.config;
    // Copy shows only when there is a live selection to copy.
    final hasSelection =
        ((await widget.controller.selectionText()) ?? '').isNotEmpty;
    if (!mounted) return;
    final items = <ContextMenuItem>[
      if (hasSelection)
        StandardMenuAction.copy.item(
          context,
          shortcut: AppShortcut.fileCopy,
          onTap: _copy,
        ),
      if (config.pasteable && widget.onPaste != null)
        StandardMenuAction.paste.item(
          context,
          shortcut: AppShortcut.terminalPaste,
          onTap: widget.onPaste!,
        ),
      if (config.selectable)
        ContextMenuItem(
          label: S.of(context).selectAll,
          icon: Icons.select_all,
          onTap: _selectAll,
        ),
    ];
    if (items.isEmpty) return;
    await showAppContextMenu(
      context: context,
      position: position,
      items: items,
    );
  }

  /// Compute whole cells that fit the constraint and report when it changes.
  /// Floors to whole cells so a partial trailing cell never invites a wrap into
  /// a column the grid can't show.
  void _reportSize(BoxConstraints constraints, Size cellSize) {
    final report = widget.onResize ?? _defaultResize;
    if (report == null) return;
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
    // Defer out of layout — calling back synchronously during a LayoutBuilder
    // build would re-enter the host's setState mid-layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      report(cols, rows);
    });
  }

  /// Convenience resize wiring for surfaces that opt into [reportResize]
  /// without supplying [onResize]: report straight to the controller. Null
  /// when neither is set.
  void Function(int, int)? get _defaultResize =>
      widget.reportResize ? widget.controller.resize : null;
}
