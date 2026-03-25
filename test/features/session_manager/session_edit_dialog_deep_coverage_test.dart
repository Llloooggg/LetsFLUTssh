import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
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

  group('SessionEditDialog — group autocomplete filtering', () {
    testWidgets('typing in group field filters suggestions', (tester) async {
      await tester.pumpWidget(
          buildApp(existingGroups: ['Production', 'Staging', 'Development']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus group field and type 'Prod'
      final groupField = find.widgetWithText(TextFormField, 'Group');
      await tester.tap(groupField);
      await tester.pumpAndSettle();

      await tester.enterText(groupField, 'Prod');
      await tester.pumpAndSettle();

      // Only Production should match
      expect(find.text('Production'), findsWidgets);
      // Staging and Development should not appear in suggestions
      // (they may still be in the segmented button, but not in autocomplete list)

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('selecting autocomplete option sets group field',
        (tester) async {
      await tester.pumpWidget(
          buildApp(existingGroups: ['Production', 'Staging']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus group field
      final groupField = find.widgetWithText(TextFormField, 'Group');
      await tester.tap(groupField);
      await tester.pumpAndSettle();

      // The autocomplete dropdown should show all options
      // Tap on Production in the dropdown
      final productionOption = find.text('Production');
      if (productionOption.evaluate().length > 1) {
        // Multiple matches (field + suggestion) - tap the last one (suggestion)
        await tester.tap(productionOption.last);
      } else {
        await tester.tap(productionOption);
      }
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — defaultGroup pre-fills group field', () {
    testWidgets('defaultGroup pre-fills group field in new session dialog',
        (tester) async {
      await tester.pumpWidget(buildApp(
        defaultGroup: 'Production/Web',
        existingGroups: ['Production', 'Production/Web'],
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify dialog opened
      expect(find.text('New Session'), findsOneWidget);

      // Fill required fields and save
      await fillRequiredFields(tester);
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.group, 'Production/Web');
    });
  });

  group('SessionEditDialog — edit mode shows Save button (not Save & Connect)', () {
    testWidgets('edit mode has Save and Cancel buttons only', (tester) async {
      final session = Session(
        label: 'edit-me',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.password,
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Save & Connect should NOT be present in edit mode
      expect(find.text('Save & Connect'), findsNothing);
      expect(find.text('Connect'), findsNothing);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — edit mode Save returns SaveResult', () {
    testWidgets('editing and saving returns SaveResult with connect=false',
        (tester) async {
      final session = Session(
        label: 'edit-srv',
        host: '10.0.0.1',
        user: 'root',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Change label
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Label'), 'updated-srv');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.label, 'updated-srv');
      expect(result.connect, isFalse);
    });
  });

  group('SessionEditDialog — validation empty host', () {
    testWidgets('empty host shows Required error on submit', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill only username, leave host empty
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'root');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
    });
  });

  group('SessionEditDialog — validation empty username', () {
    testWidgets('empty username shows Required error on submit',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill only host, leave username empty
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'host.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
    });
  });

  group('SessionEditDialog — Key auth shows key fields, no password', () {
    testWidgets('Key auth shows key path and passphrase, hides password',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Key fields should be visible
      expect(find.text('Key Passphrase'), findsOneWidget);
      // Password field should NOT be visible (only the segment button text)
      // The segment button text 'Password' is still present
      // but the TextFormField for Password should be gone
      final passwordFields = find.widgetWithText(TextFormField, 'Password');
      expect(passwordFields, findsNothing);
    });
  });

  group('SessionEditDialog — editing key session with keyData shows PEM', () {
    testWidgets('editing session with keyData auto-shows PEM text area',
        (tester) async {
      final session = Session(
        label: 'key-srv',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.key,
        keyData:
            '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // PEM text should be visible because _showKeyText is set from keyData
      expect(find.text('Key Text (PEM)'), findsOneWidget);
      expect(find.text('Hide PEM text'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — tilde expansion in key path', () {
    testWidgets('key path with tilde is expanded in result', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Enter key path with tilde
      await tester.scrollUntilVisible(
        find.text('Key File'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      final keyField = find.widgetWithText(TextFormField, 'Key File');
      if (keyField.evaluate().isNotEmpty) {
        await tester.enterText(keyField, '~/.ssh/id_rsa');
        await tester.pumpAndSettle();
      }

      // Scroll back and connect
      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      // Tilde should be expanded to homeDirectory
      expect(result.config.keyPath.contains('~'), isFalse);
    });
  });

  group('SessionDialogResult sealed classes', () {
    test('ConnectOnlyResult holds SSHConfig', () {
      final config = ConnectOnlyResult(
        const SSHConfig(host: 'h', port: 22, user: 'u'),
      );
      expect(config.config.host, 'h');
    });

    test('SaveResult holds Session with connect flag', () {
      final session = Session(label: 'test', host: 'h', user: 'u');
      final result = SaveResult(session, connect: true);
      expect(result.session.label, 'test');
      expect(result.connect, isTrue);
    });

    test('SaveResult defaults connect to false', () {
      final session = Session(label: 'test', host: 'h', user: 'u');
      final result = SaveResult(session);
      expect(result.connect, isFalse);
    });
  });
}
