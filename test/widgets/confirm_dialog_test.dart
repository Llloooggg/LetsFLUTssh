import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/confirm_dialog.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('ConfirmDialog', () {
    testWidgets('shows title, content, and buttons', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => ConfirmDialog.show(
              ctx,
              title: 'Delete Item',
              content: const Text('Are you sure?'),
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Item'), findsOneWidget);
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('returns true on confirm', (tester) async {
      bool? result;
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await ConfirmDialog.show(
                ctx,
                title: 'Test',
                content: const Text('Confirm?'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('returns false on cancel', (tester) async {
      bool? result;
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await ConfirmDialog.show(
                ctx,
                title: 'Test',
                content: const Text('Cancel?'),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('shows custom confirm label', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => ConfirmDialog.show(
              ctx,
              title: 'Test',
              content: const Text('Content'),
              confirmLabel: 'Delete All',
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete All'), findsOneWidget);
    });

    testWidgets('non-destructive style does not use red', (tester) async {
      await tester.pumpWidget(wrap(
        const ConfirmDialog(
          title: 'Save',
          content: Text('Save changes?'),
          confirmLabel: 'Save',
          destructive: false,
        ),
      ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      // Non-destructive should not have explicit background color override
      expect(button.style?.backgroundColor, isNull);
    });
  });
}
