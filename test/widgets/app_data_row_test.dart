import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/core/app_data_row.dart';

void main() {
  group('AppDataRow', () {
    testWidgets(
      'single-line row is padded to the shared minHeight so a tag row cannot '
      'visually shrink against a 3-line snippet row',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AppDataRow(icon: Icons.tag, title: 'tag'),
            ),
          ),
        );
        final size = tester.getSize(find.byType(AppDataRow));
        expect(size.height, greaterThanOrEqualTo(AppDataRow.minHeight));
      },
    );

    testWidgets('multi-line row still respects minHeight as a floor', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppDataRow(
              icon: Icons.code,
              title: 'title',
              secondary: 'command',
              secondaryMono: true,
              tertiary: 'description',
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(AppDataRow));
      expect(size.height, greaterThanOrEqualTo(AppDataRow.minHeight));
      expect(find.text('title'), findsOneWidget);
      expect(find.text('command'), findsOneWidget);
      expect(find.text('description'), findsOneWidget);
    });

    testWidgets('trailing widgets render in order and fire callbacks', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDataRow(
              icon: Icons.tag,
              title: 'x',
              trailing: [
                IconButton(
                  icon: const Icon(Icons.delete, size: 14),
                  onPressed: () => tapped++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.delete));
      expect(tapped, 1);
    });

    testWidgets('tapping the row invokes onTap when supplied', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDataRow(
              icon: Icons.tag,
              title: 'tappable',
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('tappable'));
      expect(taps, 1);
    });

    // A tappable row wraps its content in `Semantics(button: true)` so
    // every list built on this shared primitive (tag / snippet /
    // recordings / key manager) inherits an accessible button target.
    final buttonSemantics = find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.button ?? false),
    );

    testWidgets('a tappable row wraps its content in button semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDataRow(icon: Icons.tag, title: 'prod-box', onTap: () {}),
          ),
        ),
      );
      expect(buttonSemantics, findsOneWidget);
    });

    testWidgets('a non-tappable row has no button semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppDataRow(icon: Icons.tag, title: 'static'),
          ),
        ),
      );
      expect(buttonSemantics, findsNothing);
    });
  });
}
