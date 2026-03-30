import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tabs/welcome_screen.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget buildApp({required VoidCallback onNewSession}) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: WelcomeScreen(onNewSession: onNewSession),
      ),
    );
  }

  group('WelcomeScreen', () {
    testWidgets('shows heading and description', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.text('No active session'), findsOneWidget);
      expect(
        find.text(
            'Create a new connection or select one from the sidebar'),
        findsOneWidget,
      );
    });

    testWidgets('shows terminal icon in container', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.byIcon(Icons.terminal), findsOneWidget);

      // Icon should be 22px inside a 48×48 container
      final icon = tester.widget<Icon>(find.byIcon(Icons.terminal));
      expect(icon.size, 22);

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(Icons.terminal),
          matching: find.byType(Container),
        ).first,
      );
      final box = container.constraints;
      expect(box, isNotNull);
    });

    testWidgets('shows New Connection button', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.text('New Connection'), findsOneWidget);
    });

    testWidgets('shows keyboard shortcuts', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.text('Ctrl+N'), findsOneWidget);
      expect(find.text('New Terminal'), findsOneWidget);
      expect(find.text('Ctrl+Shift+N'), findsOneWidget);
      expect(find.text('New File Transfer'), findsOneWidget);
      expect(find.text('Ctrl+B'), findsOneWidget);
      expect(find.text('Toggle Sidebar'), findsOneWidget);
      expect(find.text('Ctrl+,'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('New Connection button triggers callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildApp(onNewSession: () => tapped = true));
      await tester.tap(find.text('New Connection'));
      expect(tapped, isTrue);
    });

    testWidgets('shortcut badges use JetBrains Mono font', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      final ctrlN = tester.widget<Text>(find.text('Ctrl+N'));
      expect(ctrlN.style?.fontFamily, 'JetBrains Mono');
    });
  });
}
