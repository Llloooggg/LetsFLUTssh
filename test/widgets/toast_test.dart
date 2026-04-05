import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/toast.dart';

void main() {
  Widget buildApp({required void Function(BuildContext) onPressed}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('Show Toast'),
          ),
        ),
      ),
    );
  }

  tearDown(() {
    Toast.clearAllForTest();
  });

  group('Toast — basic display', () {
    testWidgets('shows info toast with message', (tester) async {
      await tester.pumpWidget(
        buildApp(onPressed: (ctx) => Toast.show(ctx, message: 'Hello info')),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Hello info'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows success toast', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) =>
              Toast.show(ctx, message: 'Done!', level: ToastLevel.success),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Done!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows warning toast', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) =>
              Toast.show(ctx, message: 'Watch out', level: ToastLevel.warning),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Watch out'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows error toast', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) =>
              Toast.show(ctx, message: 'Oops', level: ToastLevel.error),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Oops'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('Toast — auto-dismiss', () {
    testWidgets('toast disappears after duration', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) => Toast.show(
            ctx,
            message: 'Temp',
            duration: const Duration(seconds: 1),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Temp'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Temp'), findsNothing);
    });

    testWidgets('auto-dismiss triggers reverse animation', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) => Toast.show(
            ctx,
            message: 'Auto Close',
            duration: const Duration(milliseconds: 500),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Auto Close'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('Auto Close'), findsNothing);
    });
  });

  group('Toast — manual dismiss', () {
    testWidgets('tapping close icon dismisses toast', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) => Toast.show(
            ctx,
            message: 'Closeable',
            duration: const Duration(seconds: 30),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Closeable'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Closeable'), findsNothing);
    });

    testWidgets('reverse animation completes on dismiss', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) => Toast.show(
            ctx,
            message: 'Dismiss Me',
            duration: const Duration(seconds: 30),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Dismiss Me'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Dismiss Me'), findsNothing);
    });
  });

  group('Toast — stacking and clearing', () {
    testWidgets('multiple toasts stack vertically', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => Toast.show(
                      context,
                      message: 'Toast 1',
                      duration: const Duration(seconds: 10),
                    ),
                    child: const Text('Toast 1'),
                  ),
                  ElevatedButton(
                    onPressed: () => Toast.show(
                      context,
                      message: 'Toast 2',
                      duration: const Duration(seconds: 10),
                    ),
                    child: const Text('Toast 2 btn'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Toast 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Toast 1'), findsWidgets);

      await tester.tap(find.text('Toast 2 btn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Toast 1'), findsWidgets);
      expect(find.text('Toast 2'), findsOneWidget);

      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
    });

    testWidgets('dismissing first toast updates remaining positions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => Toast.show(
                      context,
                      message: 'First',
                      duration: const Duration(seconds: 5),
                    ),
                    child: const Text('Show First'),
                  ),
                  ElevatedButton(
                    onPressed: () => Toast.show(
                      context,
                      message: 'Second',
                      duration: const Duration(seconds: 5),
                    ),
                    child: const Text('Show Second'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show First'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('Show Second'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);

      final closeIcons = find.byIcon(Icons.close);
      expect(closeIcons, findsNWidgets(2));

      await tester.tap(closeIcons.first);
      await tester.pumpAndSettle();

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);

      // Wait for remaining timer to expire
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('three stacked toasts are all visible', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            Toast.show(
              ctx,
              message: 'Stack1',
              duration: const Duration(seconds: 2),
            );
            Toast.show(
              ctx,
              message: 'Stack2',
              duration: const Duration(seconds: 2),
            );
            Toast.show(
              ctx,
              message: 'Stack3',
              duration: const Duration(seconds: 2),
            );
          },
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Stack1'), findsOneWidget);
      expect(find.text('Stack2'), findsOneWidget);
      expect(find.text('Stack3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('Toast — positioning', () {
    testWidgets('toast is positioned at top-right', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) => Toast.show(
            ctx,
            message: 'Top Right',
            duration: const Duration(seconds: 2),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned.right, 16);
      expect(positioned.top, 16.0);
      expect(positioned.bottom, isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('stacked toasts offset by 52px each', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            Toast.show(
              ctx,
              message: 'Pos1',
              duration: const Duration(seconds: 2),
            );
            Toast.show(
              ctx,
              message: 'Pos2',
              duration: const Duration(seconds: 2),
            );
          },
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final positioned = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .toList();
      // First toast at top=16, second at top=68
      expect(positioned[0].top, 16.0);
      expect(positioned[1].top, 68.0);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('Toast — clearAllForTest', () {
    testWidgets('removes all pending toasts', (tester) async {
      await tester.pumpWidget(
        buildApp(
          onPressed: (ctx) {
            Toast.show(ctx, message: 'A', duration: const Duration(seconds: 2));
            Toast.show(ctx, message: 'B', duration: const Duration(seconds: 2));
            Toast.show(ctx, message: 'C', duration: const Duration(seconds: 2));
          },
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);

      Toast.clearAllForTest();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('on empty list does not crash', (tester) async {
      await tester.pumpWidget(buildApp(onPressed: (_) {}));
      Toast.clearAllForTest();
    });
  });
}
