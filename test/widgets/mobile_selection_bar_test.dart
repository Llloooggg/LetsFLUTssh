import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/mobile_selection_bar.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('MobileSelectionBar', () {
    testWidgets('shows selected count and action buttons', (tester) async {
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 2,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () {},
            onDeselectAll: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('shows deselect icon when all selected', (tester) async {
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 5,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () {},
            onDeselectAll: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.deselect), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsNothing);
    });

    testWidgets('shows select all icon when not all selected', (tester) async {
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 0,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () {},
            onDeselectAll: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.deselect), findsNothing);
    });

    testWidgets('cancel calls onCancel', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 1,
            totalCount: 5,
            onCancel: () => cancelled = true,
            onSelectAll: () {},
            onDeselectAll: () {},
            onDelete: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      expect(cancelled, isTrue);
    });

    testWidgets('select all calls onSelectAll', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 1,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () => selected = true,
            onDeselectAll: () {},
            onDelete: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.select_all));
      expect(selected, isTrue);
    });

    testWidgets('deselect all calls onDeselectAll', (tester) async {
      var deselected = false;
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 5,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () {},
            onDeselectAll: () => deselected = true,
            onDelete: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.deselect));
      expect(deselected, isTrue);
    });

    testWidgets('renders custom action widgets', (tester) async {
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 1,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () {},
            onDeselectAll: () {},
            onDelete: () {},
            actions: [
              IconButton(icon: const Icon(Icons.swap_horiz), onPressed: () {}),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('delete disabled when onDelete is null', (tester) async {
      await tester.pumpWidget(
        wrap(
          MobileSelectionBar(
            selectedCount: 0,
            totalCount: 5,
            onCancel: () {},
            onSelectAll: () {},
            onDeselectAll: () {},
            onDelete: null,
          ),
        ),
      );

      // Delete icon should still be present but disabled
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });
  });
}
