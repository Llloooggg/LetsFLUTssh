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
import 'terminal_grid_painter.dart';
import 'terminal_grid_view.dart' show TerminalSnapshotProvider;
import 'terminal_palette_theme.dart';
import 'terminal_pointer_input.dart';

/// Applies a selection to the backing engine in absolute grid-line
/// coordinates. Wired to the controller's `setSelection` by the convenience
/// constructor; injected directly by the DI [`.fromSource`] seam in tests.
typedef ReadOnlySetSelection =
    void Function(
      int startRow,
      int startCol,
      int endRow,
      int endCol,
      TerminalSelectionKind kind,
    );

/// Reads back the text the active selection covers, or null when nothing is
/// selected. Wired to the controller's `selectionText` / injected in tests.
typedef ReadOnlySelectionText = String? Function();

/// Drives a shell-less [TerminalReplay] for a read-only surface: feed bytes,
/// pull a fresh snapshot, notify listeners to repaint. No SSH shell, no pump,
/// no input — the feeder (progress writer, recording scrub loop, log viewer)
/// pushes bytes and the [ReadOnlyTerminalGridView] listening to this repaints.
///
/// Widget-local state, so a [ChangeNotifier] per the project's state-placement
/// rule (the grid is Rust-owned; this holds only the repaint signal, never the
/// grid data). The latest [TerminalFrame] is always re-pulled from Rust on
/// repaint — never cached Dart-side.
class ReadOnlyTerminalController extends ChangeNotifier {
  ReadOnlyTerminalController({
    required int cols,
    required int rows,
    int scrollback = 10000,
    TerminalPalette? palette,
  }) : _replay = terminalReplayOpen(
         cols: cols,
         rows: rows,
         scrollback: scrollback,
         palette: palette ?? TerminalPaletteFromTheme.fromAppTheme(),
       ),
       _cols = cols,
       _rows = rows;

  final TerminalReplay _replay;
  int _cols;
  int _rows;

  /// Current grid width in columns — the wrap width feeders (the log viewer)
  /// format against. Tracks [resize].
  int get cols => _cols;

  /// Current grid height in rows.
  int get rows => _rows;

  /// Pull the current viewport snapshot. Always re-read from Rust — the
  /// engine owns the grid.
  TerminalFrame snapshot() => _replay.snapshot();

  /// Feed bytes (UTF-8 / ANSI) into the engine and schedule a repaint. The
  /// engine drops any `PtyWrite` reply (no shell) — see `TerminalReplay`.
  void feed(List<int> bytes) {
    _replay.feed(bytes: bytes);
    notifyListeners();
  }

  /// Wipe the grid + scrollback and repaint. Used by the recording scrub
  /// path before re-feeding from `t=0`.
  void clear() {
    _replay.clear();
    notifyListeners();
  }

  /// Resize the engine grid; repaint only when the count actually changed so
  /// a layout pass that re-reports the same size is a no-op.
  void resize(int cols, int rows) {
    if (cols == _cols && rows == _rows) return;
    _cols = cols;
    _rows = rows;
    _replay.resize(cols: cols, rows: rows);
    notifyListeners();
  }

  /// Re-theme the terminal (brightness flip). Re-resolves cell colors on the
  /// next snapshot.
  void setPalette(TerminalPalette palette) {
    _replay.setPalette(palette: palette);
    notifyListeners();
  }

  /// Set a selection over the rendered grid in absolute grid-line coordinates
  /// (negative row = scrollback) and repaint so the highlight paints. Used by
  /// the read-only view's pointer-drag selection — the replay has no shell, so
  /// the view drives the repaint itself rather than waiting on a `Wakeup`.
  void setSelection(
    int startRow,
    int startCol,
    int endRow,
    int endCol,
    TerminalSelectionKind kind,
  ) {
    _replay.setSelection(
      startRow: startRow,
      startCol: startCol,
      endRow: endRow,
      endCol: endCol,
      kind: kind,
    );
    notifyListeners();
  }

  /// Clear any active selection and repaint to drop the highlight.
  void clearSelection() {
    _replay.clearSelection();
    notifyListeners();
  }

  /// The text covered by the active selection, or null when nothing is
  /// selected. Read straight from the engine — never cached Dart-side.
  String? selectionText() => _replay.selectionText();
}

/// Read-only renderer over a [TerminalReplay], reusing the same
/// [TerminalGridPainter] + cell metrics the live desktop pane uses. No
/// keyboard input to the engine and no mouse reporting — the surfaces this
/// backs (connection-progress output, recording playback, the log viewer)
/// only feed bytes and render.
///
/// When [selectable] is set the view also supports **select + copy** (no input
/// to a shell, just reading text out): a primary-button drag drives a local
/// text selection (same pixel→cell mapping + multi-tap word/line geometry as
/// the live [TerminalGridView], via the shared `terminal_pointer_input.dart`
/// helpers), `Ctrl+C` / `Cmd+C` and `Ctrl+Shift+C` copy the selection, and a
/// right-click opens a Copy + Select All menu. Copy reads the engine's
/// `selectionText` and routes it through the same [TerminalClipboard] path the
/// live pane uses (sensitive-content routing + auto-wipe). Surfaces that want
/// genuine zero interaction leave [selectable] false (the default).
///
/// Repaints when [repaint] notifies (the controller bumps it after each feed
/// / clear / resize / selection change); on each notify it re-pulls a snapshot
/// from [snapshotProvider]. When [reportResize] is set, the laid-out cell
/// count is reported back so the host can resize the replay to fit the
/// viewport (the progress / log surfaces do; recording playback renders a
/// fixed recorded grid and leaves it null).
class ReadOnlyTerminalGridView extends StatefulWidget {
  /// Convenience constructor over a [ReadOnlyTerminalController]: pulls frames
  /// from `controller.snapshot` and repaints when the controller notifies.
  /// Pass [selectable] to wire the controller's selection methods so the view
  /// supports drag-select + copy.
  ReadOnlyTerminalGridView({
    super.key,
    required ReadOnlyTerminalController controller,
    this.fontSize = 14.0,
    this.reportResize = false,
    this.selectable = false,
  }) : snapshotProvider = controller.snapshot,
       repaint = controller,
       onResize = reportResize ? controller.resize : null,
       onSetSelection = selectable ? controller.setSelection : null,
       onClearSelection = selectable ? controller.clearSelection : null,
       selectionTextProvider = selectable ? controller.selectionText : null;

  /// Dependency-injected constructor for tests / non-FFI hosts: supply a
  /// snapshot function and a repaint [Listenable] directly. Pass the selection
  /// seam ([onSetSelection] / [selectionTextProvider]) to exercise the
  /// drag-select + copy wiring against a fake engine.
  const ReadOnlyTerminalGridView.fromSource({
    super.key,
    required this.snapshotProvider,
    required this.repaint,
    this.fontSize = 14.0,
    this.onResize,
    this.onSetSelection,
    this.onClearSelection,
    this.selectionTextProvider,
  }) : reportResize = false,
       selectable = onSetSelection != null;

  final TerminalSnapshotProvider snapshotProvider;

  /// Bumped by the feeder after each feed / clear / resize / selection change.
  /// The view re-pulls a snapshot and repaints on every notify.
  final Listenable repaint;

  final double fontSize;

  /// Whether the convenience constructor wires the controller's `resize` as
  /// [onResize] so the grid fits the laid-out viewport.
  final bool reportResize;

  /// Whether drag-select + copy is enabled. False = zero interaction.
  final bool selectable;

  /// Viewport size in cells changed (resize / first layout). Null leaves the
  /// grid at its constructed size (fixed-grid surfaces like recording
  /// playback).
  final void Function(int cols, int rows)? onResize;

  /// Apply a selection to the engine. Null when [selectable] is false.
  final ReadOnlySetSelection? onSetSelection;

  /// Clear the active selection. Null when [selectable] is false.
  final VoidCallback? onClearSelection;

  /// Read the active selection's text. Null when [selectable] is false.
  final ReadOnlySelectionText? selectionTextProvider;

  @override
  State<ReadOnlyTerminalGridView> createState() =>
      _ReadOnlyTerminalGridViewState();
}

class _ReadOnlyTerminalGridViewState extends State<ReadOnlyTerminalGridView> {
  static const EdgeInsets _padding = EdgeInsets.all(kTerminalPadding);

  /// Plain `Ctrl+C` / `Cmd+C` copy. This surface renders a log / replay, not a
  /// live PTY, so the Unix convention of reserving `Ctrl+C` for SIGINT does
  /// not apply — the prior read-only view bound plain `Ctrl+C` here. The live
  /// pane's `Ctrl+Shift+C` ([AppShortcut.terminalCopy]) is also accepted so
  /// muscle memory from the interactive pane works on these surfaces too.
  static const _copyActivators = <ShortcutActivator>[
    SingleActivator(LogicalKeyboardKey.keyC, control: true),
    SingleActivator(LogicalKeyboardKey.keyC, meta: true),
    SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true),
  ];

  late TerminalFrame _frame;
  int _frameRevision = 0;

  int? _lastCols;
  int? _lastRows;

  /// Cell pitch from the last build, captured so pointer handlers (which run
  /// outside build) map pixels to cells with the metrics the painter used.
  Size _cellSize = Size.zero;

  /// The anchor cell of an in-progress selection drag, in absolute grid-line
  /// coordinates. Null when no drag is active.
  TerminalCellCoord? _selectionAnchor;

  /// Multi-tap run state for word/line selection — folded forward by
  /// [nextTapCount] on each press, exactly as the live grid does.
  int _tapCount = 0;
  TerminalCellCoord? _lastPressCell;
  DateTime _lastPressTime = DateTime.fromMillisecondsSinceEpoch(0);
  TerminalSelectionKind _tapKind = TerminalSelectionKind.simple;

  /// Owned focus node so the copy shortcuts reach [_handleKey] once a click
  /// has focused the surface.
  final FocusNode _focus = FocusNode(debugLabel: 'ReadOnlyTerminalGridView');

  @override
  void initState() {
    super.initState();
    _frame = widget.snapshotProvider();
    widget.repaint.addListener(_onRepaint);
  }

  @override
  void didUpdateWidget(ReadOnlyTerminalGridView old) {
    super.didUpdateWidget(old);
    if (old.repaint != widget.repaint) {
      old.repaint.removeListener(_onRepaint);
      widget.repaint.addListener(_onRepaint);
    }
    if (old.snapshotProvider != widget.snapshotProvider) {
      _pullFrame();
    }
  }

  void _onRepaint() {
    if (!mounted) return;
    _pullFrame();
  }

  void _pullFrame() {
    setState(() {
      _frame = widget.snapshotProvider();
      _frameRevision++;
    });
  }

  @override
  void dispose() {
    widget.repaint.removeListener(_onRepaint);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cellSize = measureMonoCell(
      fontSize: widget.fontSize,
      textScaler: MediaQuery.textScalerOf(context),
    );
    _cellSize = cellSize;
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
              showCursor: false,
            ),
          ),
        );
        if (!widget.selectable) return grid;
        return Focus(
          focusNode: _focus,
          onKeyEvent: _handleKey,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: grid,
          ),
        );
      },
    );
  }

  /// Map a pointer event's local position to a cell using the last-built cell
  /// metrics and the current frame's scroll offset. Returns null before the
  /// first build measures the metrics, so an early event is a no-op.
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

  /// Primary-button press: focus the surface (so the copy shortcuts arm),
  /// fold the multi-tap count, clear any prior selection, and anchor a new
  /// drag. Secondary / tertiary buttons open the context menu instead and do
  /// not start a selection. Right-click handling is in [_onPointerUp] so a
  /// drag-then-release does not also trigger it.
  void _onPointerDown(PointerDownEvent event) {
    final cell = _cellFor(event);
    if (cell == null) return;
    if (event.buttons & kSecondaryButton != 0) {
      _showContextMenu(event.position);
      return;
    }
    if (event.buttons & kPrimaryMouseButton == 0) return;
    _focus.requestFocus();
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
    final anchor = _selectionAnchor;
    if (anchor == null) return;
    final cell = _cellFor(event);
    if (cell == null) return;
    // Keep the press's geometry while dragging — a double-click-then-drag
    // extends the word selection, not a character one.
    _setSelection(anchor, cell, _tapKind);
  }

  void _onPointerUp(PointerUpEvent event) {
    final anchor = _selectionAnchor;
    _selectionAnchor = null;
    final cell = _cellFor(event);
    // A single click that did not move leaves a collapsed 1-cell selection the
    // user did not intend — clear it so a later copy does not grab a stray
    // glyph. A drag that moved, or a double / triple click (expanded to a word
    // / line by the engine), keeps its selection.
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
    widget.onSetSelection?.call(
      start.absoluteRow,
      start.col,
      end.absoluteRow,
      end.col,
      kind,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    for (final activator in _copyActivators) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        _copySelection();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Read the engine's current selection text and route it through the same
  /// [TerminalClipboard] path the live pane uses (sensitive-content routing +
  /// 30 s auto-wipe), then clear the highlight. No-op when nothing is selected.
  void _copySelection() {
    final text = widget.selectionTextProvider?.call();
    if (text == null || text.isEmpty) return;
    TerminalClipboard.copyText(text);
    widget.onClearSelection?.call();
  }

  void _selectAll() {
    final rows = _frame.rows;
    final cols = _frame.cols;
    if (rows <= 0 || cols <= 0) return;
    // Cover the whole scrollback + viewport: from the top of history
    // (`-scrollbackLines`) to the bottom of the live screen, as a Lines
    // selection so the engine trims trailing blanks per row.
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
    final hasSelection =
        (widget.selectionTextProvider?.call() ?? '').isNotEmpty;
    unawaited(
      showAppContextMenu(
        context: context,
        position: position,
        items: [
          if (hasSelection)
            StandardMenuAction.copy.item(
              context,
              shortcut: AppShortcut.fileCopy,
              onTap: _copySelection,
            ),
          ContextMenuItem(
            label: S.of(context).selectAll,
            icon: Icons.select_all,
            onTap: _selectAll,
          ),
        ],
      ),
    );
  }

  /// Compute whole cells that fit the constraint and report when it changes.
  /// Floors to whole cells so a partial trailing cell never invites a wrap
  /// into a column the grid can't show.
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
    // Defer out of layout — a synchronous callback during LayoutBuilder build
    // would re-enter the host's setState mid-layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onResize?.call(cols, rows);
    });
  }
}
