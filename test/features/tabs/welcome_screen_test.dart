import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tabs/welcome_screen.dart';

void main() {
  Widget buildApp({required VoidCallback onQuickConnect}) {
    return MaterialApp(
      home: Scaffold(
        body: WelcomeScreen(onQuickConnect: onQuickConnect),
      ),
    );
  }

  group('WelcomeScreen', () {
    testWidgets('shows app name and subtitle', (tester) async {
      await tester.pumpWidget(buildApp(onQuickConnect: () {}));
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });

    testWidgets('shows terminal icon', (tester) async {
      await tester.pumpWidget(buildApp(onQuickConnect: () {}));
      expect(find.byIcon(Icons.terminal), findsOneWidget);
    });

    testWidgets('shows Quick Connect button', (tester) async {
      await tester.pumpWidget(buildApp(onQuickConnect: () {}));
      expect(find.text('Quick Connect'), findsOneWidget);
    });

    testWidgets('shows keyboard shortcut hint', (tester) async {
      await tester.pumpWidget(buildApp(onQuickConnect: () {}));
      expect(find.text('Ctrl+N to quick connect'), findsOneWidget);
    });

    testWidgets('Quick Connect button triggers callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildApp(onQuickConnect: () => tapped = true));
      await tester.tap(find.text('Quick Connect'));
      expect(tapped, isTrue);
    });
  });
}
