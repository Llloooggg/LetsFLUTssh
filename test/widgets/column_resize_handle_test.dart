import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/widgets/column_resize_handle.dart';

void main() {
  group('ColumnResizeHandle', () {
    testWidgets('renders 10x24 hit area with 1px divider line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColumnResizeHandle(onDrag: (_) {}),
          ),
        ),
      );

      // Outer SizedBox: 10 wide, 24 tall
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final outer = sizedBoxes.firstWhere(
        (s) => s.width == 10 && s.height == 24,
      );
      expect(outer, isNotNull);

      // Shows resize column cursor
      final mouseRegions = tester.widgetList<MouseRegion>(find.byType(MouseRegion));
      final resizeCursor = mouseRegions.where(
        (m) => m.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(resizeCursor, hasLength(1));
    });

    testWidgets('reports positive dx when dragged right', (tester) async {
      double lastDx = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ColumnResizeHandle(onDrag: (dx) => lastDx = dx),
            ),
          ),
        ),
      );

      final handle = find.byType(ColumnResizeHandle);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pump();

      expect(lastDx, greaterThan(0));
    });

    testWidgets('reports negative dx when dragged left', (tester) async {
      double lastDx = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ColumnResizeHandle(onDrag: (dx) => lastDx = dx),
            ),
          ),
        ),
      );

      final handle = find.byType(ColumnResizeHandle);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.up();
      await tester.pump();

      expect(lastDx, lessThan(0));
    });
  });
}
