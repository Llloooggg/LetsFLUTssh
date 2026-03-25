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

  group('Toast — basic display', () {
    testWidgets('shows info toast with message', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) => Toast.show(ctx, message: 'Hello info'),
      ));

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Hello info'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      // Wait for auto-dismiss
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows success toast', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) => Toast.show(ctx, message: 'Done!', level: ToastLevel.success),
      ));

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Done!'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows warning toast', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) => Toast.show(ctx, message: 'Watch out', level: ToastLevel.warning),
      ));

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Watch out'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('shows error toast', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) => Toast.show(ctx, message: 'Oops', level: ToastLevel.error),
      ));

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
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) => Toast.show(
          ctx,
          message: 'Temp',
          duration: const Duration(seconds: 1),
        ),
      ));

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Temp'), findsOneWidget);

      // Wait for the duration + animation
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Temp'), findsNothing);
    });
  });

  group('Toast — manual dismiss', () {
    testWidgets('tapping close icon dismisses toast', (tester) async {
      await tester.pumpWidget(buildApp(
        onPressed: (ctx) => Toast.show(
          ctx,
          message: 'Closeable',
          duration: const Duration(seconds: 30), // long so auto-dismiss won't interfere
        ),
      ));

      await tester.tap(find.text('Show Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Closeable'), findsOneWidget);

      // Tap the close icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Closeable'), findsNothing);
    });
  });

  group('Toast — stacking multiple toasts', () {
    testWidgets('multiple toasts stack vertically', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));

      // Show first toast
      await tester.tap(find.text('Toast 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Toast 1'), findsWidgets); // button + toast

      // Show second toast
      await tester.tap(find.text('Toast 2 btn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Both toasts should be visible
      expect(find.text('Toast 1'), findsWidgets);
      expect(find.text('Toast 2'), findsOneWidget);

      // Clean up - wait for auto-dismiss
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
    });
  });
}
