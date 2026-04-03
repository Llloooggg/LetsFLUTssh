import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/clipped_row.dart';

void main() {
  group('ClippedRow', () {
    testWidgets('renders children normally when they fit', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 400,
            height: 40,
            child: ClippedRow(
              children: [
                SizedBox(width: 100, child: Text('A')),
                SizedBox(width: 100, child: Text('B')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('clips overflow without error', (tester) async {
      // Children total 600px in a 200px container — overflow is clipped.
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 200,
            height: 40,
            child: ClippedRow(
              children: [
                SizedBox(width: 300, child: Text('Wide1')),
                SizedBox(width: 300, child: Text('Wide2')),
              ],
            ),
          ),
        ),
      );

      // No FlutterError should be reported — the custom RenderFlex
      // silently clips instead of painting the overflow indicator.
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports Expanded children', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 400,
            height: 40,
            child: ClippedRow(
              children: [
                SizedBox(width: 50),
                Expanded(child: Text('Fills remaining')),
                SizedBox(width: 50),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Fills remaining'), findsOneWidget);
    });
  });
}
