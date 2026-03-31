import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mixin providing marquee (lasso) selection with drag-aware pointer handling.
///
/// Used by session tree view and both file panes (local/remote SFTP).
///
/// Subclasses implement:
/// - [marqueeRowHeight], [marqueeItemCount] — geometry
/// - [isMarqueeItemSelected] — hit-test for drag suppression
/// - [applyMarqueeSelection] — apply range selection to domain model
///
/// The mixin owns a [ScrollController] — use [marqueeScrollController] in
/// the ListView and call [disposeMarquee] from the host State's dispose().
mixin MarqueeMixin<T extends StatefulWidget> on State<T> {
  // ── State ──

  Offset? _mAnchor;
  Offset? _mStart;
  Offset? _mCurrent;
  bool _mActive = false;
  bool marqueeDragActive = false;
  DateTime _mLastUpdate = DateTime(0);

  final marqueeScrollController = ScrollController();

  static const _kThreshold = 5.0;

  // ── Abstract / overridable ──

  double get marqueeRowHeight;
  int get marqueeItemCount;
  double get marqueeListPadding => 0.0;

  bool isMarqueeItemSelected(int index);
  void applyMarqueeSelection(int firstIndex, int lastIndex,
      {required bool ctrlHeld});

  /// Called at pointer-down before any marquee logic (e.g. request focus).
  void onMarqueePointerDown() {}

  /// Called when marquee rectangle first appears.
  void onMarqueeActivated() {}

  /// Called when marquee rectangle disappears.
  void onMarqueeDeactivated() {}

  /// Called on click without drag on a non-selected row.
  void onMarqueeClickEmpty(int rowIndex) {}

  // ── Helpers ──

  bool get isCtrlHeld =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.controlRight);

  int marqueeRowIndexAt(double localY) {
    final scroll =
        marqueeScrollController.hasClients ? marqueeScrollController.offset : 0.0;
    return ((localY + scroll - marqueeListPadding) / marqueeRowHeight).floor();
  }

  // ── Pointer handlers ──

  void handleMarqueePointerDown(PointerDownEvent e) {
    onMarqueePointerDown();
    if (e.buttons != kPrimaryButton) return;

    final idx = marqueeRowIndexAt(e.localPosition.dy);
    final onRow = idx >= 0 && idx < marqueeItemCount;
    if (onRow && isMarqueeItemSelected(idx)) return;

    setState(() => _mAnchor = e.localPosition);
  }

  void handleMarqueePointerMove(PointerMoveEvent e) {
    if (marqueeDragActive || _mAnchor == null) return;

    final distance = (e.localPosition - _mAnchor!).distance;
    if (!_mActive && distance < _kThreshold) return;

    if (!_mActive) {
      _mActive = true;
      onMarqueeActivated();
    }

    setState(() {
      _mStart = _mAnchor;
      _mCurrent = e.localPosition;
    });
    _updateSelection();
  }

  void handleMarqueePointerUp(PointerUpEvent _) {
    if (_mActive) {
      setState(() {
        _mAnchor = null;
        _mStart = null;
        _mCurrent = null;
        _mActive = false;
      });
      onMarqueeDeactivated();
    } else if (!marqueeDragActive) {
      if (_mAnchor != null && !isCtrlHeld) {
        onMarqueeClickEmpty(marqueeRowIndexAt(_mAnchor!.dy));
      }
      _mAnchor = null;
    }
  }

  // ── Selection ──

  void _updateSelection() {
    if (_mStart == null || _mCurrent == null) return;

    final now = DateTime.now();
    if (now.difference(_mLastUpdate).inMilliseconds < 50) return;
    _mLastUpdate = now;

    final scroll =
        marqueeScrollController.hasClients ? marqueeScrollController.offset : 0.0;
    final startY = _mStart!.dy + scroll;
    final endY = _mCurrent!.dy + scroll;
    final minY = (startY < endY ? startY : endY) - marqueeListPadding;
    final maxY = (startY > endY ? startY : endY) - marqueeListPadding;

    final maxIdx = marqueeItemCount - 1;
    if (maxIdx < 0) return;

    applyMarqueeSelection(
      (minY / marqueeRowHeight).floor().clamp(0, maxIdx),
      (maxY / marqueeRowHeight).floor().clamp(0, maxIdx),
      ctrlHeld: isCtrlHeld,
    );
  }

  // ── Overlay ──

  bool get marqueeVisible => _mActive && _mStart != null && _mCurrent != null;

  Widget buildMarqueeOverlay(Color color) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: IgnorePointer(
          child: CustomPaint(
            painter: MarqueePainter(
              start: _mStart!,
              end: _mCurrent!,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  // ── Drag callbacks (wire to Draggable) ──

  void onDragStarted() => marqueeDragActive = true;
  void onDragEnd(DraggableDetails _) => marqueeDragActive = false;
  void onDragCanceled(Velocity _, Offset _) => marqueeDragActive = false;

  // ── Cleanup ──

  void disposeMarquee() {
    marqueeScrollController.dispose();
  }

  // ── Access for cross-marquee (session panel) ──

  Offset? get marqueeAnchor => _mAnchor;
  set marqueeAnchor(Offset? v) => _mAnchor = v;
  bool get marqueeActive => _mActive;
  set marqueeActive(bool v) => _mActive = v;
  Offset? get marqueeStart => _mStart;
  set marqueeStart(Offset? v) => _mStart = v;
  Offset? get marqueeCurrent => _mCurrent;
  set marqueeCurrent(Offset? v) => _mCurrent = v;
}

/// Draws the translucent marquee rectangle.
class MarqueePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  MarqueePainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);

    // Fill
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(MarqueePainter oldDelegate) {
    return start != oldDelegate.start || end != oldDelegate.end;
  }
}
