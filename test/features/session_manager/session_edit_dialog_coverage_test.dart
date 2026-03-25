import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';
import 'package:letsflutssh/core/session/session.dart';

void main() {
  SessionDialogResult? dialogResult;

  Widget buildApp({Session? session, List<String> existingGroups = const []}) {
    dialogResult = null;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              dialogResult = await SessionEditDialog.show(
                context,
                session: session,
                existingGroups: existingGroups,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  Future<void> fillRequiredFields(WidgetTester tester,
      {String host = 'example.com', String user = 'testuser'}) async {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Host *'), host);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Username *'), user);
    await tester.pumpAndSettle();
  }

  group('SessionEditDialog — Key+Pass auth with key data', () {
    testWidgets('Save with Key+Pass auth preserves keyData', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key+Pass
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      // Scroll to PEM toggle
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Enter PEM text
      await tester.scrollUntilVisible(
        find.text('Key Text (PEM)'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      // Scroll back to action buttons
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.authType, AuthType.keyWithPassword);
      expect(result.session.keyData, contains('PRIVATE KEY'));
    });
  });

  group('SessionEditDialog — editing session with keyWithPassword auth', () {
    testWidgets('editing Key+Pass session shows both password and key fields',
        (tester) async {
      final session = Session(
        label: 'kp-server',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.keyWithPassword,
        password: 'secret',
        keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
        passphrase: 'kp123',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      // Both password and key fields should be present
      expect(find.text('Password'), findsWidgets); // segment + field
      expect(find.text('Key Passphrase'), findsOneWidget);
      // PEM text should be visible since keyData is not empty
      expect(find.text('Key Text (PEM)'), findsOneWidget);
    });
  });

  group('SessionEditDialog — password visibility toggle in Key+Pass mode', () {
    testWidgets('toggling password visibility in Key+Pass mode', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key+Pass
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      // Scroll to the password visibility icon
      await tester.scrollUntilVisible(
        find.byIcon(Icons.visibility).first,
        100,
        scrollable: find.byType(Scrollable).last,
      );

      // Both password and passphrase should have visibility toggles
      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      // Toggle the first visibility icon (password field)
      await tester.tap(visIcons.first);
      await tester.pumpAndSettle();

      // Should now show visibility_off for that field
      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });
  });

  group('SessionEditDialog — port edge cases', () {
    testWidgets('port 0 shows validation error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'root');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Port'), '0');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });

    testWidgets('empty port shows validation error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'root');
      // Clear port field
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Port'), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });
  });

  group('SessionEditDialog — Connect with key path', () {
    testWidgets('Connect with Key auth includes key path', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Enter key path (scroll first if needed)
      await tester.scrollUntilVisible(
        find.text('Key File'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      // On desktop, the field is 'Key File', on mobile 'Key File Path'
      final keyField = find.widgetWithText(TextFormField, 'Key File');
      if (keyField.evaluate().isNotEmpty) {
        await tester.enterText(keyField, '/home/user/.ssh/id_rsa');
        await tester.pumpAndSettle();
      }

      // Scroll back to Connect button
      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.keyPath, '/home/user/.ssh/id_rsa');
    });
  });

  group('SessionEditDialog — editing session preserves auth type', () {
    testWidgets('editing password session has Password selected',
        (tester) async {
      final session = Session(
        label: 'pw-server',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.password,
        password: 'pass',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Password field should be visible (not key fields)
      expect(find.text('Password'), findsWidgets);
      // Key fields should NOT be visible
      expect(find.text('Key Passphrase'), findsNothing);
    });
  });

  group('SessionEditDialog — switching auth types clears visibility', () {
    testWidgets('switching from Password to Key and back', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Start with Password auth — password field visible
      expect(find.text('Password'), findsWidgets);

      // Switch to Key
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Password field should be hidden, key fields visible
      expect(find.text('Key Passphrase'), findsOneWidget);

      // Switch back to Password
      await tester.tap(find.text('Password'));
      await tester.pumpAndSettle();

      // Password field should be visible again
      expect(find.text('Password'), findsWidgets);
      // Key fields hidden
      expect(find.text('Key Passphrase'), findsNothing);
    });
  });

  group('SessionEditDialog — Save & Connect with Key auth', () {
    testWidgets('Save & Connect with Key auth includes key auth type',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Scroll to action buttons
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.authType, AuthType.key);
    });
  });

  group('SessionEditDialog — passphrase visibility toggle in Key+Pass', () {
    testWidgets('toggling passphrase visibility works in Key+Pass mode',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      // Scroll to passphrase
      await tester.scrollUntilVisible(
        find.text('Key Passphrase'),
        100,
        scrollable: find.byType(Scrollable).last,
      );

      // Find both visibility icons (password + passphrase)
      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons.evaluate().length, greaterThanOrEqualTo(2));

      // Toggle the last one (passphrase)
      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });
  });

  group('SessionEditDialog — group field with defaultGroup', () {
    testWidgets('autocomplete with empty text shows all groups', (tester) async {
      await tester.pumpWidget(
          buildApp(existingGroups: ['Production', 'Staging', 'Dev']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus group field to trigger autocomplete
      final groupField = find.widgetWithText(TextFormField, 'Group');
      await tester.tap(groupField);
      await tester.pumpAndSettle();

      // All groups should be visible
      expect(find.text('Production'), findsWidgets);
      expect(find.text('Staging'), findsWidgets);
      expect(find.text('Dev'), findsWidgets);
    });
  });
}
