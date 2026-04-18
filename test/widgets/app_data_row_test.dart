import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/app_data_row.dart';

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
  });
}
