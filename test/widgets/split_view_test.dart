import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/split_view.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

void main() {
  Widget buildApp({double initialLeftWidth = 220, double minLeftWidth = 150, double maxLeftWidth = 400}) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
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
      final resizeCursors = tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .where((m) => m.cursor == SystemMouseCursors.resizeColumn);
      expect(resizeCursors.length, 1);
    });

    testWidgets('left pane has initial width', (tester) async {
      await tester.pumpWidget(buildApp(initialLeftWidth: 250));
      await tester.pumpAndSettle();

      // The SplitView creates a SizedBox with the left width
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).where((s) => s.width == 250);
      expect(sizedBoxes.length, 1);
    });

    testWidgets('dragging divider changes left width', (tester) async {
      await tester.pumpWidget(buildApp(initialLeftWidth: 220));
      await tester.pumpAndSettle();

      // Find the divider (MouseRegion with resizeColumn cursor)
      final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
      expect(divider, findsOneWidget);

      // Drag right by 50px
      await tester.drag(divider, const Offset(50, 0));
      await tester.pumpAndSettle();

      // Left pane should now be 270px
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).where((s) => s.width == 270);
      expect(sizedBoxes.length, 1);
    });

    testWidgets('dragging divider respects min/max bounds', (tester) async {
      await tester.pumpWidget(buildApp(initialLeftWidth: 220, minLeftWidth: 150, maxLeftWidth: 400));
      await tester.pumpAndSettle();

      final divider = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);

      // Drag far left (below min)
      await tester.drag(divider, const Offset(-200, 0));
      await tester.pumpAndSettle();

      // Should clamp to minLeftWidth (150)
      final minBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).where((s) => s.width == 150);
      expect(minBoxes.length, 1);
    });
  });
}
