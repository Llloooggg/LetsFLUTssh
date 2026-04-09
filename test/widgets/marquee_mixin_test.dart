import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/marquee_mixin.dart';

void main() {
  group('MarqueePainter', () {
    test('shouldRepaint returns true when start changes', () {
      final oldPainter = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      final newPainter = MarqueePainter(
        start: const Offset(10, 10),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('shouldRepaint returns true when end changes', () {
      final oldPainter = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      final newPainter = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(200, 200),
        color: Colors.blue,
      );
      expect(newPainter.shouldRepaint(oldPainter), isTrue);
    });

    test('shouldRepaint returns false when start and end are same', () {
      final oldPainter = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      final newPainter = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.red,
      );
      expect(newPainter.shouldRepaint(oldPainter), isFalse);
    });

    test('paint draws fill and border rectangles', () {
      final painter = MarqueePainter(
        start: const Offset(10, 10),
        end: const Offset(50, 50),
        color: Colors.blue,
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(100, 100));
      // If no exception is thrown, painting succeeded
      recorder.endRecording();
    });
  });

  group('MarqueeMixin', () {
    testWidgets('marqueeRowIndexAt calculates correct index', (tester) async {
      late _TestMarqueeState state;
      await tester.pumpWidget(
        MaterialApp(home: _TestMarqueeWidget(onStateCreated: (s) => state = s)),
      );

      // With rowHeight=30 and no scroll, row at y=0 → index 0
      expect(state.marqueeRowIndexAt(0), 0);
      // y=29 → still row 0
      expect(state.marqueeRowIndexAt(29), 0);
      // y=30 → row 1
      expect(state.marqueeRowIndexAt(30), 1);
      // y=90 → row 3
      expect(state.marqueeRowIndexAt(90), 3);
    });

    testWidgets('marqueeRowIndexAt accounts for list padding', (tester) async {
      late _TestMarqueeState state;
      await tester.pumpWidget(
        MaterialApp(
          home: _TestMarqueeWidget(
            listPadding: 10.0,
            onStateCreated: (s) => state = s,
          ),
        ),
      );

      // With padding=10, y=10 maps to scroll-adjusted 0 → row 0
      expect(state.marqueeRowIndexAt(10), 0);
      // y=0 maps to -10/30 = negative → row -1 (above list)
      expect(state.marqueeRowIndexAt(0), lessThan(0));
    });

    testWidgets('marqueeVisible is false by default', (tester) async {
      late _TestMarqueeState state;
      await tester.pumpWidget(
        MaterialApp(home: _TestMarqueeWidget(onStateCreated: (s) => state = s)),
      );

      expect(state.marqueeVisible, isFalse);
    });

    testWidgets('marqueeScrollController is accessible', (tester) async {
      late _TestMarqueeState state;
      await tester.pumpWidget(
        MaterialApp(home: _TestMarqueeWidget(onStateCreated: (s) => state = s)),
      );

      expect(state.marqueeScrollController, isA<ScrollController>());
    });

    testWidgets('drag callbacks update marqueeDragActive', (tester) async {
      late _TestMarqueeState state;
      await tester.pumpWidget(
        MaterialApp(home: _TestMarqueeWidget(onStateCreated: (s) => state = s)),
      );

      expect(state.marqueeDragActive, isFalse);

      state.onDragStarted();
      expect(state.marqueeDragActive, isTrue);

      state.onDragEnd(
        DraggableDetails(velocity: Velocity.zero, offset: Offset.zero),
      );
      expect(state.marqueeDragActive, isFalse);
    });
  });
}

// ── Test helpers ──

class _TestMarqueeWidget extends StatefulWidget {
  final void Function(_TestMarqueeState) onStateCreated;
  final double listPadding;

  const _TestMarqueeWidget({
    required this.onStateCreated,
    this.listPadding = 0.0,
  });

  @override
  State<_TestMarqueeWidget> createState() => _TestMarqueeState();
}

class _TestMarqueeState extends State<_TestMarqueeWidget>
    with MarqueeMixin<_TestMarqueeWidget> {
  @override
  double get marqueeRowHeight => 30.0;

  @override
  int get marqueeItemCount => 10;

  @override
  double get marqueeListPadding => widget.listPadding;

  @override
  bool isMarqueeItemSelected(int index) => false;

  @override
  void applyMarqueeSelection(
    int firstIndex,
    int lastIndex, {
    required bool ctrlHeld,
  }) {}

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
  }

  @override
  void dispose() {
    disposeMarquee();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 200, height: 300);
  }
}
