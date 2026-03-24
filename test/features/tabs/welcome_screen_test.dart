import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/tabs/welcome_screen.dart';

void main() {
  Widget buildApp({required VoidCallback onNewSession}) {
    return MaterialApp(
      home: Scaffold(
        body: WelcomeScreen(onNewSession: onNewSession),
      ),
    );
  }

  group('WelcomeScreen', () {
    testWidgets('shows app name and subtitle', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });

    testWidgets('shows terminal icon', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.byIcon(Icons.terminal), findsOneWidget);
    });

    testWidgets('shows New Session button', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.text('New Session'), findsOneWidget);
    });

    testWidgets('shows keyboard shortcut hint', (tester) async {
      await tester.pumpWidget(buildApp(onNewSession: () {}));
      expect(find.text('Ctrl+N to connect'), findsOneWidget);
    });

    testWidgets('New Session button triggers callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildApp(onNewSession: () => tapped = true));
      await tester.tap(find.text('New Session'));
      expect(tapped, isTrue);
    });
  });
}
