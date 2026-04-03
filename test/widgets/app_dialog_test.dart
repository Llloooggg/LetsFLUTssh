import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/app_dialog.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('AppDialog', () {
    testWidgets('renders title, content, and actions', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppDialog.show(
              ctx,
              builder: (_) => AppDialog(
                title: 'Test Title',
                content: const Text('Body text'),
                actions: [
                  const AppDialogAction.cancel(),
                  AppDialogAction.primary(label: 'OK', onTap: () {}),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Body text'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('close button pops dialog', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppDialog.show(
              ctx,
              builder: (_) => const AppDialog(
                title: 'Closeable',
                content: Text('content'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Closeable'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Closeable'), findsNothing);
    });
  });

  group('AppDialogFooter', () {
    testWidgets('uses Wrap for action layout', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppDialog.show(
              ctx,
              builder: (_) => AppDialog(
                title: 'Footer Test',
                content: const Text('content'),
                actions: [
                  const AppDialogAction.cancel(),
                  AppDialogAction.secondary(label: 'Skip', onTap: () {}),
                  AppDialogAction.primary(label: 'Open', onTap: () {}),
                ],
              ),
            ),
            child: const Text('Show'),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Footer uses Wrap so actions can flow to next line on narrow screens
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('footer wraps actions on narrow screen', (tester) async {
      // Use a very narrow surface to force wrapping
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppDialog.show(
              ctx,
              builder: (_) => AppDialog(
                title: 'Narrow',
                content: const Text('content'),
                actions: [
                  const AppDialogAction.cancel(),
                  AppDialogAction.secondary(
                    label: 'Skip This Version',
                    onTap: () {},
                  ),
                  AppDialogAction.primary(
                    label: 'Open in Browser',
                    onTap: () {},
                  ),
                ],
              ),
            ),
            child: const Text('Show'),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // All three actions should still be visible (Wrap prevents overflow)
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Skip This Version'), findsOneWidget);
      expect(find.text('Open in Browser'), findsOneWidget);

      // Verify no overflow errors occurred during layout
      expect(tester.takeException(), isNull);
    });
  });

  group('AppDialogAction', () {
    testWidgets('primary action has accent background', (tester) async {
      await tester.pumpWidget(wrap(
        AppDialogAction.primary(label: 'Save', onTap: () {}),
      ));

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('secondary action renders label', (tester) async {
      await tester.pumpWidget(wrap(
        AppDialogAction.secondary(label: 'Skip', onTap: () {}),
      ));

      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('destructive action renders label', (tester) async {
      await tester.pumpWidget(wrap(
        AppDialogAction.destructive(label: 'Delete', onTap: () {}),
      ));

      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('disabled action does not trigger onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(
        AppDialogAction.primary(
          label: 'Disabled',
          onTap: () => tapped = true,
          enabled: false,
        ),
      ));

      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(tapped, isFalse);
    });
  });

  group('AppProgressDialog', () {
    testWidgets('shows spinner', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppProgressDialog.show(ctx),
            child: const Text('Load'),
          ),
        ),
      ));

      await tester.tap(find.text('Load'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
