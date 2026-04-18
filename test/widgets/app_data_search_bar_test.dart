import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/app_data_search_bar.dart';

void main() {
  group('AppDataSearchBar', () {
    testWidgets('propagates text edits through onChanged', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDataSearchBar(
              onChanged: changes.add,
              hintText: 'Search hosts',
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'foo');
      expect(changes, ['foo']);
    });

    testWidgets('renders the hint and the search icon so the role is obvious '
        'without any typing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDataSearchBar(
              onChanged: (_) {},
              hintText: 'Filter snippets',
            ),
          ),
        ),
      );

      expect(find.text('Filter snippets'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('seeds the controller from initialText so callers can restore '
        'a saved query across rebuilds', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDataSearchBar(
              onChanged: (_) {},
              hintText: 'x',
              initialText: 'persisted-query',
            ),
          ),
        ),
      );

      expect(find.text('persisted-query'), findsOneWidget);
    });
  });
}
