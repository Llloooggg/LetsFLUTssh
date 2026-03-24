import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/split_view.dart';

void main() {
  Widget buildApp({
    double initialLeftWidth = 220,
    double minLeftWidth = 150,
    double maxLeftWidth = 400,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: SplitView(
            initialLeftWidth: initialLeftWidth,
            minLeftWidth: minLeftWidth,
            maxLeftWidth: maxLeftWidth,
            left: const Text('LEFT'),
            right: const Text('RIGHT'),
          ),
        ),
      ),
    );
  }

  group('SplitView', () {
    testWidgets('renders left and right children', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('LEFT'), findsOneWidget);
      expect(find.text('RIGHT'), findsOneWidget);
    });

    testWidgets('has a draggable divider with resize cursor', (tester) async {
      await tester.pumpWidget(buildApp());
      // Find the specific MouseRegion with resizeColumn cursor
      final resizeCursors = tester.widgetList<MouseRegion>(find.byType(MouseRegion))
          .where((m) => m.cursor == SystemMouseCursors.resizeColumn);
      expect(resizeCursors.length, 1);
    });

    testWidgets('left pane has initial width', (tester) async {
      await tester.pumpWidget(buildApp(initialLeftWidth: 250));
      await tester.pumpAndSettle();

      // The SplitView creates a SizedBox with the left width
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox))
          .where((s) => s.width == 250);
      expect(sizedBoxes.length, 1);
    });
  });
}
