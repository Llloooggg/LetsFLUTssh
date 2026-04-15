import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/data_checkboxes.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: child),
  );

  group('DataCheckboxRow', () {
    testWidgets('renders label, trailing text, and checkbox state', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          DataCheckboxRow(
            icon: Icons.tag,
            label: 'Tags',
            value: true,
            onTap: () {},
            trailingLabel: '42',
          ),
        ),
      );

      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('taps anywhere on the row fire onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          DataCheckboxRow(
            icon: Icons.tag,
            label: 'Tags',
            value: false,
            onTap: () => taps++,
            trailingLabel: '0',
          ),
        ),
      );

      // Whole row clickable — tapping the label (not the checkbox) still toggles.
      await tester.tap(find.text('Tags'));
      await tester.pump();
      expect(taps, 1);

      // Checkbox itself also fires onTap (via onChanged).
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('warning text is shown under the label', (tester) async {
      await tester.pumpWidget(
        wrap(
          DataCheckboxRow(
            icon: Icons.warning,
            label: 'Danger',
            value: true,
            onTap: () {},
            warningText: 'Heads up!',
          ),
        ),
      );

      expect(find.text('Danger'), findsOneWidget);
      expect(find.text('Heads up!'), findsOneWidget);
    });

    testWidgets('trailing label is optional', (tester) async {
      await tester.pumpWidget(
        wrap(
          DataCheckboxRow(
            icon: Icons.tag,
            label: 'Tags',
            value: false,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Tags'), findsOneWidget);
    });
  });

  group('CollapsibleCheckboxesSection', () {
    testWidgets('collapsed: body is not in the tree', (tester) async {
      await tester.pumpWidget(
        wrap(
          CollapsibleCheckboxesSection(
            title: 'What',
            trailingLabel: 'Preset',
            expanded: false,
            onToggle: () {},
            body: const Text('row-1'),
          ),
        ),
      );

      expect(find.text('What'), findsOneWidget);
      expect(find.text('Preset'), findsOneWidget);
      expect(find.text('row-1'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('expanded: body is rendered and chevron flips', (tester) async {
      await tester.pumpWidget(
        wrap(
          CollapsibleCheckboxesSection(
            title: 'What',
            expanded: true,
            onToggle: () {},
            body: const Text('row-1'),
          ),
        ),
      );

      expect(find.text('row-1'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('tap on header fires onToggle', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        wrap(
          CollapsibleCheckboxesSection(
            title: 'What',
            expanded: false,
            onToggle: () => toggles++,
            body: const Text('row-1'),
          ),
        ),
      );

      await tester.tap(find.text('What'));
      await tester.pump();
      expect(toggles, 1);
    });
  });
}
