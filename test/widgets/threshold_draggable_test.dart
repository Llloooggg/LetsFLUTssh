import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/threshold_draggable.dart';

void main() {
  Widget buildApp({
    required double moveThreshold,
    VoidCallback? onDragStarted,
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: ThresholdDraggable<String>(
          data: 'test',
          moveThreshold: moveThreshold,
          onDragStarted: onDragStarted,
          feedback: const Material(
            child: SizedBox(width: 50, height: 50, key: Key('feedback')),
          ),
          child: const SizedBox(width: 100, height: 100, key: Key('draggable')),
        ),
      ),
    );
  }

  group('ThresholdDraggable', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(buildApp(moveThreshold: 8.0));
      expect(find.byKey(const Key('draggable')), findsOneWidget);
    });

    testWidgets('does not start drag with movement below threshold', (
      tester,
    ) async {
      var dragStarted = false;
      await tester.pumpWidget(
        buildApp(moveThreshold: 20.0, onDragStarted: () => dragStarted = true),
      );

      final center = tester.getCenter(find.byKey(const Key('draggable')));
      final gesture = await tester.startGesture(center);
      // Move only 5 pixels — well below 20px threshold
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();

      expect(dragStarted, isFalse);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('default moveThreshold is 8', (tester) async {
      const draggable = ThresholdDraggable<String>(
        data: 'test',
        feedback: SizedBox(),
        child: SizedBox(),
      );
      expect(draggable.moveThreshold, 8.0);
    });

    test('createRecognizer returns threshold-based recognizer', () {
      const draggable = ThresholdDraggable<String>(
        moveThreshold: 12.0,
        feedback: SizedBox(),
        child: SizedBox(),
      );
      final recognizer = draggable.createRecognizer((_) => null);
      expect(recognizer, isA<MultiDragGestureRecognizer>());
      expect(recognizer.debugDescription, 'threshold multidrag');
      recognizer.dispose();
    });

    testWidgets('custom moveThreshold is preserved', (tester) async {
      await tester.pumpWidget(buildApp(moveThreshold: 25.0));
      final widget = tester.widget<ThresholdDraggable<String>>(
        find.byType(ThresholdDraggable<String>),
      );
      expect(widget.moveThreshold, 25.0);
    });
  });
}
