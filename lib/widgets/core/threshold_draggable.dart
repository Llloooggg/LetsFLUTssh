import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// [Draggable] variant that requires [moveThreshold] pixels of pointer
/// movement before initiating a drag.
///
/// Standard [Draggable] starts on ~1 px of mouse movement, which causes
/// accidental drags when clicking close buttons or double-clicking items.
/// [LongPressDraggable] uses a time delay, but double-tap detection in
/// [GestureDetector] defers `onTap` by ~300 ms, so the delay-based
/// approach is unreliable.
///
/// This widget solves both problems: clicks and double-clicks with normal
/// hand tremor (< [moveThreshold] px) never trigger a drag, while
/// intentional drags start as soon as the pointer moves far enough.
class ThresholdDraggable<T extends Object> extends Draggable<T> {
  const ThresholdDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.axis,
    super.childWhenDragging,
    super.feedbackOffset,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDraggableCanceled,
    super.onDragEnd,
    super.onDragCompleted,
    super.ignoringFeedbackSemantics,
    super.ignoringFeedbackPointer,
    super.rootOverlay,
    super.hitTestBehavior,
    super.allowedButtonsFilter,
    this.moveThreshold = 8.0,
  });

  /// Minimum pointer movement in logical pixels before drag begins.
  final double moveThreshold;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _ThresholdMultiDragRecognizer(
      moveThreshold: moveThreshold,
      debugOwner: this,
      allowedButtonsFilter: allowedButtonsFilter,
    )..onStart = onStart;
  }
}

class _ThresholdMultiDragRecognizer extends MultiDragGestureRecognizer {
  _ThresholdMultiDragRecognizer({
    required this.moveThreshold,
    required super.debugOwner,
    super.allowedButtonsFilter,
  });

  final double moveThreshold;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _ThresholdPointerState(
      event.position,
      moveThreshold,
      event.kind,
      gestureSettings,
    );
  }

  @override
  String get debugDescription => 'threshold multidrag';
}

class _ThresholdPointerState extends MultiDragPointerState {
  _ThresholdPointerState(
    super.initialPosition,
    this.moveThreshold,
    super.kind,
    super.gestureSettings,
  );

  final double moveThreshold;

  @override
  void checkForResolutionAfterMove() {
    assert(pendingDelta != null);
    if (pendingDelta!.distance > moveThreshold) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}
