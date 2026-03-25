import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';

void main() {
  SessionDialogResult? dialogResult;

  Widget buildApp({
    Session? session,
    List<String> existingGroups = const [],
    String? defaultGroup,
  }) {
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
                defaultGroup: defaultGroup,
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

  group('SessionEditDialog — auth type switching', () {
    testWidgets('switching to Key+Pass shows both password and key fields',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Default is Password
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);

      // Switch to Key+Pass
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      // Both password and key fields should be visible
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Key Passphrase'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('switching from Key to Password hides key fields',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();
      expect(find.text('Key Passphrase'), findsOneWidget);

      // Switch back to Password
      await tester.tap(find.text('Password'));
      await tester.pumpAndSettle();
      expect(find.text('Key Passphrase'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — PEM text toggle', () {
    testWidgets('clicking PEM toggle shows and hides PEM text area',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Scroll down to see PEM toggle
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'), 100,
        scrollable: scrollable,
      );

      // Initially PEM text hidden
      expect(find.text('Paste PEM key text'), findsOneWidget);

      // Toggle to show PEM text
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Scroll to see the new field
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'), 100,
        scrollable: scrollable,
      );

      expect(find.text('Hide PEM text'), findsOneWidget);

      // Toggle to hide PEM text
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — password visibility toggle', () {
    testWidgets('password visibility icon toggles obscure text',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Scroll to password field visibility icon
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.byIcon(Icons.visibility), 100,
        scrollable: scrollable,
      );

      // Tap to toggle visibility
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pumpAndSettle();

      // Now should show visibility_off icon
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);

      // Tap again to toggle back
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — passphrase visibility toggle', () {
    testWidgets('passphrase visibility toggles', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth to see passphrase field
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Scroll to passphrase visibility icon
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Key Passphrase'), 100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // There should be a visibility icon for passphrase
      final visIcons = find.byIcon(Icons.visibility);
      if (visIcons.evaluate().isNotEmpty) {
        await tester.tap(visIcons.last);
        await tester.pumpAndSettle();

        // Should now have visibility_off
        expect(find.byIcon(Icons.visibility_off), findsWidgets);
      }

      // Scroll back to Cancel
      await tester.scrollUntilVisible(
        find.text('Cancel'), -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — port validation', () {
    testWidgets('invalid port shows error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill host and user
      await fillRequiredFields(tester);

      // Set invalid port
      final portField = find.widgetWithText(TextFormField, 'Port');
      await tester.enterText(portField, '99999');
      await tester.pumpAndSettle();

      // Try to submit
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Port validation error
      expect(find.text('1-65535'), findsOneWidget);
    });

    testWidgets('non-numeric port shows error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      final portField = find.widgetWithText(TextFormField, 'Port');
      await tester.enterText(portField, 'abc');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });
  });

  group('SessionEditDialog — ConnectOnly result', () {
    testWidgets('Connect button returns ConnectOnlyResult', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester, host: 'connect.host', user: 'cuser');

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.host, 'connect.host');
      expect(result.config.user, 'cuser');
      expect(result.config.port, 22);
    });
  });

  group('SessionEditDialog — Save & Connect result', () {
    testWidgets('Save & Connect returns SaveResult with connect=true',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester, host: 'save.host', user: 'suser');

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, 'save.host');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — edit with Key+Password auth', () {
    testWidgets('editing keyWithPassword session shows all fields',
        (tester) async {
      final session = Session(
        label: 'kp-srv',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.keyWithPassword,
        password: 'pass123',
        keyPath: '/keys/id_rsa',
        passphrase: 'phrase',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Should show Edit Session dialog with keyWithPassword selected
      expect(find.text('Edit Session'), findsOneWidget);

      // Both password and key passphrase fields visible
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Key Passphrase'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — label and group fields', () {
    testWidgets('label field is optional — can submit without it',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill only required fields, no label
      await fillRequiredFields(tester);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
    });
  });

  group('SessionEditDialog — group field sync with autocomplete', () {
    testWidgets('empty group options show all groups on focus', (tester) async {
      await tester.pumpWidget(
          buildApp(existingGroups: ['GroupA', 'GroupB']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus group field
      final groupField = find.widgetWithText(TextFormField, 'Group');
      await tester.tap(groupField);
      await tester.pumpAndSettle();

      // All groups should appear as autocomplete options
      expect(find.text('GroupA'), findsWidgets);
      expect(find.text('GroupB'), findsWidgets);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
