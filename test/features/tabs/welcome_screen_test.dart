import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tabs/welcome_screen.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget buildApp() {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: WelcomeScreen(),
      ),
    );
  }

  group('WelcomeScreen', () {
    testWidgets('shows heading and description', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.text('No active session'), findsOneWidget);
      expect(
        find.text(
            'Create a new connection or select one from the sidebar'),
        findsOneWidget,
      );
    });

    testWidgets('shows terminal icon in container', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byIcon(Icons.terminal), findsOneWidget);

      // Icon should be 22px inside a 48×48 container
      final icon = tester.widget<Icon>(find.byIcon(Icons.terminal));
      expect(icon.size, 22);
    });

    testWidgets('does not show any buttons or shortcuts', (tester) async {
      await tester.pumpWidget(buildApp());
      expect(find.byType(TextButton), findsNothing);
      expect(find.text('New Connection'), findsNothing);
      expect(find.text('Ctrl+N'), findsNothing);
      expect(find.text('Ctrl+Shift+N'), findsNothing);
      expect(find.text('Ctrl+B'), findsNothing);
      expect(find.text('Ctrl+,'), findsNothing);
    });
  });
}
