import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/quick_connect_dialog.dart';

void main() {
  SSHConfig? dialogResult;

  Widget buildApp() {
    dialogResult = null;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              dialogResult = await QuickConnectDialog.show(context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  group('QuickConnectDialog', () {
    testWidgets('shows dialog with title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Connect'), findsOneWidget);
    });

    testWidgets('has Host, Port, Username, Password fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Host *'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Username *'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('port defaults to 22', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('22'), findsOneWidget);
    });

    testWidgets('has Key File and Key Passphrase fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Key File'), findsOneWidget);
      expect(find.text('Key Passphrase'), findsOneWidget);
    });

    testWidgets('has Cancel and Connect buttons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('Cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be gone
      expect(find.text('Quick Connect'), findsNothing);
    });

    testWidgets('Connect validates required fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Connect without filling anything
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Validation errors should appear
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Initially password is obscured — visibility icon shown
      expect(find.byIcon(Icons.visibility), findsWidgets);

      // Tap visibility toggle (first one is password)
      await tester.tap(find.byIcon(Icons.visibility).first);
      await tester.pumpAndSettle();

      // Now should show visibility_off
      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });

    testWidgets('PEM text toggle expands key text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Initially hidden
      expect(find.text('Key Text (PEM)'), findsNothing);

      // Toggle PEM text
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      expect(find.text('Key Text (PEM)'), findsOneWidget);
    });

    testWidgets('Connect with valid fields returns SSHConfig', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Host *'), 'myhost.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Username *'), 'admin');
      await tester.enterText(find.widgetWithText(TextFormField, 'Port'), '2222');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.host, 'myhost.com');
      expect(dialogResult!.user, 'admin');
      expect(dialogResult!.port, 2222);
      expect(dialogResult!.password, 'secret');
    });

    testWidgets('Connect without required fields does not close', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Don't fill required fields
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
      expect(find.text('Quick Connect'), findsOneWidget);
    });

    testWidgets('Connect with PEM key data', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Host *'), 'h');
      await tester.enterText(find.widgetWithText(TextFormField, 'Username *'), 'u');

      // Toggle PEM and enter key data
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Key Text (PEM)'), 'PEM-DATA');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.keyData, 'PEM-DATA');
    });
  });
}
