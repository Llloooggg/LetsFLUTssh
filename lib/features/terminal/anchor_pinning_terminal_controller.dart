import 'package:xterm/xterm.dart';

/// `TerminalController` that pins the **base** anchor of a drag-driven
/// selection while a pointer is held down.
///
/// xterm's drag handler stores the drag-start position as a local widget
/// pixel and recomputes both endpoints via `getCellOffset(localPx)` on
/// every drag update. A wheel scroll between drag-start and drag-update
/// changes `_scrollOffset`, so the same start pixel resolves to a
/// different buffer row and the anchor silently jumps. Pinning the
/// first observed `(line, x)` keeps the selection stable across scroll.
///
/// Implementation note: we cannot simply hold the first `CellAnchor` —
/// `TerminalController.setSelection` disposes the prior `_selectionBase`
/// before assigning the new one, so the pinned anchor would detach
/// after the first reuse. We pin the `BufferLine` + column instead and
/// mint a fresh anchor on each call.
class AnchorPinningTerminalController extends TerminalController {
  bool _dragActive = false;
  BufferLine? _pinnedLine;
  int _pinnedX = 0;

  /// Mark the start of a pointer-driven selection drag. Subsequent
  /// `setSelection` calls reuse the first observed `(line, x)` until
  /// [endDrag] (or [clearSelection]) fires.
  void beginDrag() {
    _dragActive = true;
    _pinnedLine = null;
  }

  /// Release the pin — call on pointer-up / cancel.
  void endDrag() {
    _dragActive = false;
    _pinnedLine = null;
  }

  @override
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    if (!_dragActive) {
      super.setSelection(base, extent, mode: mode);
      return;
    }
    final pinnedLine = _pinnedLine;
    if (pinnedLine == null || !pinnedLine.attached) {
      // First setSelection of this drag (or pinned line rotated out
      // of the scrollback): adopt this base as the pin.
      _pinnedLine = base.line;
      _pinnedX = base.x;
      super.setSelection(base, extent, mode: mode);
    } else {
      // Discard xterm's recomputed `base` — its line/column reflects
      // the current scroll, not the drag start. Dispose it so it does
      // not linger in `line._anchors`.
      base.dispose();
      final pinnedBase = pinnedLine.createAnchor(_pinnedX);
      super.setSelection(pinnedBase, extent, mode: mode);
    }
  }

  @override
  void clearSelection() {
    _pinnedLine = null;
    super.clearSelection();
  }
}
