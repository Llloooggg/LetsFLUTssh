import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/app_collection_toolbar.dart';

Widget _host(Widget toolbar, {required double width}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: toolbar),
    ),
  ),
);

Widget _searchBox() =>
    const SizedBox(key: ValueKey('search'), height: 32, child: Placeholder());

List<Widget> _threeActions() => const [
  Text('Add', key: ValueKey('add')),
  Text('Import', key: ValueKey('import')),
  Text('Generate', key: ValueKey('generate')),
];

void main() {
  group('AppCollectionToolbar — wide layout', () {
    testWidgets('single row on a wide host', (tester) async {
      await tester.pumpWidget(
        _host(
          AppCollectionToolbar(
            hasItems: true,
            search: _searchBox(),
            countLabel: '3 items',
            actions: _threeActions(),
          ),
          width: 800,
        ),
      );
      // On the wide branch the inner Column is not used.
      expect(find.byType(Row), findsWidgets);
      expect(find.byKey(const ValueKey('search')), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.byKey(const ValueKey('add')), findsOneWidget);
      expect(find.byKey(const ValueKey('generate')), findsOneWidget);
    });

    testWidgets('hides search + count on the empty branch', (tester) async {
      await tester.pumpWidget(
        _host(
          AppCollectionToolbar(
            hasItems: false,
            search: _searchBox(),
            countLabel: '0 items',
            actions: const [Text('Add')],
          ),
          width: 800,
        ),
      );
      expect(find.byKey(const ValueKey('search')), findsNothing);
      expect(find.text('0 items'), findsNothing);
      expect(find.text('Add'), findsOneWidget);
    });
  });

  group('AppCollectionToolbar — narrow layout', () {
    testWidgets('stacks vertically below the breakpoint', (tester) async {
      await tester.pumpWidget(
        _host(
          AppCollectionToolbar(
            hasItems: true,
            search: _searchBox(),
            countLabel: '3 items',
            actions: _threeActions(),
          ),
          width: 360,
        ),
      );
      // Narrow hosts render the search, count, and action Wrap as
      // rows inside a single outer Column.
      expect(find.byKey(const ValueKey('search')), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.byKey(const ValueKey('add')), findsOneWidget);
      expect(find.byKey(const ValueKey('import')), findsOneWidget);
      expect(find.byKey(const ValueKey('generate')), findsOneWidget);
    });

    testWidgets('no overflow with three wide buttons on a narrow host', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppCollectionToolbar(
            hasItems: true,
            search: _searchBox(),
            countLabel: '3 items',
            actions: const [
              SizedBox(width: 200, height: 30, child: Text('Add long label')),
              SizedBox(
                width: 200,
                height: 30,
                child: Text('Import long label'),
              ),
              SizedBox(
                width: 200,
                height: 30,
                child: Text('Generate long label'),
              ),
            ],
          ),
          width: 320,
        ),
      );
      // No layout overflow — three 200-px buttons flow to multiple
      // lines inside the narrow-branch Wrap instead of clipping.
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow empty-state renders only the action Wrap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppCollectionToolbar(
            hasItems: false,
            search: _searchBox(),
            countLabel: '0 items',
            actions: const [Text('Add')],
          ),
          width: 320,
        ),
      );
      expect(find.byKey(const ValueKey('search')), findsNothing);
      expect(find.text('0 items'), findsNothing);
      expect(find.text('Add'), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
    });
  });
}
