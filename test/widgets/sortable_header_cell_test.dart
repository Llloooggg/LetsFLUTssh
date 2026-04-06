import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/hover_region.dart';
import 'package:letsflutssh/widgets/sortable_header_cell.dart';

void main() {
  const style = TextStyle(fontSize: 12);

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('SortableHeaderCell', () {
    testWidgets('shows label without arrow when inactive', (tester) async {
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: false,
            sortAscending: true,
            onTap: () {},
            style: style,
          ),
        ),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.textContaining('↑'), findsNothing);
      expect(find.textContaining('↓'), findsNothing);
    });

    testWidgets('shows ascending arrow when active and ascending', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: true,
            sortAscending: true,
            onTap: () {},
            style: style,
          ),
        ),
      );

      expect(find.text('Name ↑'), findsOneWidget);
    });

    testWidgets('shows descending arrow when active and descending', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: true,
            sortAscending: false,
            onTap: () {},
            style: style,
          ),
        ),
      );

      expect(find.text('Name ↓'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: false,
            sortAscending: true,
            onTap: () => tapped = true,
            style: style,
          ),
        ),
      );

      await tester.tap(find.text('Name'));
      expect(tapped, isTrue);
    });

    testWidgets('uses click cursor', (tester) async {
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: false,
            sortAscending: true,
            onTap: () {},
            style: style,
          ),
        ),
      );

      final hoverRegion = tester.widget<HoverRegion>(find.byType(HoverRegion));
      expect(hoverRegion.cursor, SystemMouseCursors.click);
    });

    testWidgets('respects width parameter', (tester) async {
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: false,
            sortAscending: true,
            onTap: () {},
            style: style,
            width: 100,
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(of: find.text('Name'), matching: find.byType(SizedBox)),
      );
      expect(sizedBox.width, 100);
    });

    testWidgets('respects textAlign parameter', (tester) async {
      await tester.pumpWidget(
        wrap(
          SortableHeaderCell(
            label: 'Name',
            isActive: false,
            sortAscending: true,
            onTap: () {},
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('Name'));
      expect(text.textAlign, TextAlign.right);
    });
  });

  group('columnDivider', () {
    testWidgets('renders thin vertical divider', (tester) async {
      await tester.pumpWidget(wrap(Row(children: [columnDivider()])));

      final outerBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(outerBox.width, 10);

      final innerContainer = tester.widget<Container>(
        find.byType(Container).last,
      );
      expect(innerContainer.constraints?.maxWidth, 1);
    });
  });
}
