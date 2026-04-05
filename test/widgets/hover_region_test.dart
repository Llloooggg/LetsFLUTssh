import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/widgets/hover_region.dart';

void main() {
  Widget buildApp(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('HoverRegion', () {
    testWidgets('builder receives false by default', (tester) async {
      bool? received;
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            builder: (hovered) {
              received = hovered;
              return const SizedBox(width: 50, height: 50);
            },
          ),
        ),
      );
      expect(received, isFalse);
    });

    testWidgets('builder receives true on mouse enter', (tester) async {
      bool? received;
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            builder: (hovered) {
              received = hovered;
              return const SizedBox(width: 50, height: 50);
            },
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(received, isTrue);
    });

    testWidgets('builder receives false on mouse exit', (tester) async {
      bool? received;
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            builder: (hovered) {
              received = hovered;
              return const SizedBox(width: 50, height: 50);
            },
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      expect(received, isTrue);

      await gesture.moveTo(const Offset(999, 999));
      await tester.pump();
      expect(received, isFalse);
    });

    testWidgets('onTap fires callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            onTap: () => tapped = true,
            builder: (_) => const SizedBox(width: 50, height: 50),
          ),
        ),
      );

      await tester.tap(find.byType(HoverRegion));
      expect(tapped, isTrue);
    });

    testWidgets('onDoubleTap fires callback', (tester) async {
      var doubleTapped = false;
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            onDoubleTap: () => doubleTapped = true,
            builder: (_) => const SizedBox(width: 50, height: 50),
          ),
        ),
      );

      await tester.tap(find.byType(HoverRegion));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(HoverRegion));
      await tester.pumpAndSettle();
      expect(doubleTapped, isTrue);
    });

    testWidgets('onSecondaryTapUp fires callback', (tester) async {
      TapUpDetails? details;
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            onSecondaryTapUp: (d) => details = d,
            builder: (_) => const SizedBox(width: 50, height: 50),
          ),
        ),
      );

      await tester.tapAt(
        tester.getCenter(find.byType(HoverRegion)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(details, isNotNull);
    });

    testWidgets('cursor defaults to basic', (tester) async {
      await tester.pumpWidget(
        buildApp(
          HoverRegion(builder: (_) => const SizedBox(width: 50, height: 50)),
        ),
      );

      final mouseRegion = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(HoverRegion),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(mouseRegion.cursor, SystemMouseCursors.basic);
    });

    testWidgets('custom cursor is applied', (tester) async {
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            cursor: SystemMouseCursors.resizeColumn,
            builder: (_) => const SizedBox(width: 50, height: 50),
          ),
        ),
      );

      final mouseRegion = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(HoverRegion),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(mouseRegion.cursor, SystemMouseCursors.resizeColumn);
    });

    testWidgets('no GestureDetector when no gestures', (tester) async {
      await tester.pumpWidget(
        buildApp(
          HoverRegion(builder: (_) => const SizedBox(width: 50, height: 50)),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(HoverRegion),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('GestureDetector present when onTap set', (tester) async {
      await tester.pumpWidget(
        buildApp(
          HoverRegion(
            onTap: () {},
            builder: (_) => const SizedBox(width: 50, height: 50),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(HoverRegion),
          matching: find.byType(GestureDetector),
        ),
        findsOneWidget,
      );
    });
  });
}
