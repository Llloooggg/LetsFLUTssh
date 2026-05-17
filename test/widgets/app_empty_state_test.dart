/// Coverage for [AppEmptyState] — every collection-dialog placeholder
/// (snippet manager, key manager, tag manager, session picker)
/// renders through this single widget so the gutter / alignment /
/// typography stay consistent.
///
/// Asserts the three optional-slot branches the build() method
/// switches on: message-only (no icon, no action), message + icon,
/// message + action, message + both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/app_empty_state.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('AppEmptyState', () {
    testWidgets('renders the message text', (tester) async {
      await tester.pumpWidget(
        wrap(const AppEmptyState(message: 'No items yet')),
      );
      expect(find.text('No items yet'), findsOneWidget);
    });

    testWidgets('does not render an icon when none is provided', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const AppEmptyState(message: 'Empty')));
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('renders the icon when provided', (tester) async {
      await tester.pumpWidget(
        wrap(const AppEmptyState(message: 'Empty', icon: Icons.inbox)),
      );
      // Find the specific icon — there should be exactly one Icon
      // widget, and it should match the provided IconData.
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.inbox);
    });

    testWidgets('does not render the action slot when null', (tester) async {
      await tester.pumpWidget(wrap(const AppEmptyState(message: 'Empty')));
      // No TextButton / ElevatedButton / any widget in the action
      // slot. We pump a known marker key in the action below; here
      // we assert nothing of that shape appears by accident.
      expect(find.byKey(const ValueKey('action-marker')), findsNothing);
    });

    testWidgets('renders the action when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppEmptyState(
            message: 'Empty',
            action: TextButton(
              key: const ValueKey('action-marker'),
              onPressed: () {},
              child: const Text('Add one'),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('action-marker')), findsOneWidget);
      expect(find.text('Add one'), findsOneWidget);
    });

    testWidgets('renders icon + message + action together', (tester) async {
      await tester.pumpWidget(
        wrap(
          AppEmptyState(
            message: 'Empty',
            icon: Icons.list,
            action: TextButton(
              key: const ValueKey('action-marker'),
              onPressed: () {},
              child: const Text('Refresh'),
            ),
          ),
        ),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(find.text('Empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('action-marker')), findsOneWidget);
    });

    testWidgets('message wraps with TextAlign.center', (tester) async {
      await tester.pumpWidget(
        wrap(const AppEmptyState(message: 'A long empty-state message body')),
      );
      // Find the Text widget rendering the message and verify the
      // textAlign contract — long-locale strings (RU / DE) on mobile
      // wrap and must stay centered, not glue to the left edge.
      final text = tester.widget<Text>(
        find.text('A long empty-state message body'),
      );
      expect(text.textAlign, TextAlign.center);
    });
  });
}
