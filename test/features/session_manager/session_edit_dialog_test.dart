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

  Future<void> fillRequiredFields(WidgetTester tester, {String host = 'example.com', String user = 'testuser'}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Host *'), host);
    await tester.enterText(find.widgetWithText(TextFormField, 'Username *'), user);
    await tester.pumpAndSettle();
  }

  group('SessionEditDialog — new session', () {
    testWidgets('shows New Session title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('New Session'), findsOneWidget);
    });

    testWidgets('has all required fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Label'), findsOneWidget);
      expect(find.text('Group'), findsOneWidget);
      expect(find.text('Host *'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Username *'), findsOneWidget);
    });

    testWidgets('has auth type selector', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Authentication'), findsOneWidget);
      expect(find.text('Password'), findsWidgets); // segment + field
      expect(find.text('Key'), findsOneWidget);
      expect(find.text('Key+Pass'), findsOneWidget);
    });

    testWidgets('action buttons present for new session', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save & Connect'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('validates required fields on submit', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('Cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Session'), findsNothing);
    });

    testWidgets('switching to Key auth shows key fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Key segment
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      expect(find.text('Key File'), findsOneWidget);
      expect(find.text('Key Passphrase'), findsOneWidget);
    });

    testWidgets('port defaults to 22', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('22'), findsOneWidget);
    });
  });

  group('SessionEditDialog — submit actions', () {
    testWidgets('Connect returns ConnectOnlyResult with SSHConfig', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.host, 'example.com');
      expect(result.config.user, 'testuser');
      expect(result.config.port, 22);
    });

    testWidgets('Save & Connect returns SaveResult with connect=true', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, 'example.com');
      expect(result.session.user, 'testuser');
      expect(result.connect, isTrue);
    });

    testWidgets('Save & Connect with label and group', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'My Server');
      await fillRequiredFields(tester, host: '10.0.0.1', user: 'root');

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      final result = dialogResult as SaveResult;
      expect(result.session.label, 'My Server');
      expect(result.session.host, '10.0.0.1');
      expect(result.session.user, 'root');
    });

    testWidgets('Connect without valid fields does not close', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Don't fill required fields
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
      expect(find.text('New Session'), findsOneWidget);
    });

    testWidgets('Save & Connect with custom port', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Port'), '2222');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      final result = dialogResult as SaveResult;
      expect(result.session.port, 2222);
    });

    testWidgets('Connect with password auth', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.password, 'secret123');
    });
  });

  group('SessionEditDialog — edit session submit', () {
    testWidgets('Save returns SaveResult with connect=false', (tester) async {
      final session = Session(
        label: 'test-server',
        host: '10.0.0.1',
        user: 'root',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.host, '10.0.0.1');
      expect(result.session.user, 'root');
      expect(result.connect, isFalse);
    });

    testWidgets('Save preserves edited fields', (tester) async {
      final session = Session(
        label: 'old-label',
        host: '10.0.0.1',
        user: 'root',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear and re-enter label
      await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'new-label');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final result = dialogResult as SaveResult;
      expect(result.session.label, 'new-label');
      expect(result.session.id, session.id);
    });
  });

  group('SessionEditDialog — Key auth fields', () {
    testWidgets('Key auth shows key path and passphrase fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      expect(find.text('Key Passphrase'), findsOneWidget);
      // PEM toggle should be present
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('PEM toggle shows and hides key text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Click toggle to show PEM text — scroll down to find it first
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // PEM field should now be visible
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Hide PEM text'), findsOneWidget);

      // Click toggle to hide PEM text
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      expect(find.text('Hide PEM text'), findsNothing);
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('Connect with Key auth includes passphrase in config', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Scroll to passphrase field and fill it
      await tester.scrollUntilVisible(
        find.text('Key Passphrase'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Passphrase'),
        'mypassphrase',
      );
      await tester.pumpAndSettle();

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
      expect(result.config.passphrase, 'mypassphrase');
    });
  });

  group('SessionEditDialog — Key+Pass auth', () {
    testWidgets('Key+Pass shows both password and key fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      expect(find.text('Password'), findsWidgets); // segment label + field
      expect(find.text('Key Passphrase'), findsOneWidget);
    });

    testWidgets('Save & Connect with Key+Pass auth', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      // Scroll to password field
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret',
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
      expect(result.session.password, 'secret');
    });
  });

  group('SessionEditDialog — password visibility toggle', () {
    testWidgets('password field toggle changes icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Scroll to password area
      await tester.scrollUntilVisible(
        find.byIcon(Icons.visibility),
        100,
        scrollable: find.byType(Scrollable).last,
      );

      // Find visibility icon and tap it
      final visibilityIcon = find.byIcon(Icons.visibility);
      expect(visibilityIcon, findsOneWidget);

      await tester.tap(visibilityIcon);
      await tester.pumpAndSettle();

      // Now it should show visibility_off
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });
  });

  group('SessionEditDialog — group autocomplete', () {
    testWidgets('group field shows autocomplete suggestions', (tester) async {
      await tester.pumpWidget(buildApp(existingGroups: ['Production', 'Staging', 'Dev']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The group field should show suggestions
      final groupField = find.widgetWithText(TextFormField, 'Group');
      expect(groupField, findsOneWidget);

      // Type to filter
      await tester.enterText(groupField, 'Prod');
      await tester.pumpAndSettle();

      // Production should appear as suggestion
      expect(find.text('Production'), findsWidgets);
    });

    testWidgets('selecting autocomplete suggestion fills group field', (tester) async {
      await tester.pumpWidget(buildApp(existingGroups: ['Production', 'Staging']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final groupField = find.widgetWithText(TextFormField, 'Group');
      await tester.enterText(groupField, 'Stag');
      await tester.pumpAndSettle();

      // Tap the "Staging" suggestion from autocomplete
      final suggestion = find.text('Staging');
      if (suggestion.evaluate().length > 1) {
        // Tap the last one (the suggestion, not the field text)
        await tester.tap(suggestion.last);
      } else {
        await tester.tap(suggestion);
      }
      await tester.pumpAndSettle();

      // Field should now contain 'Staging'
      expect(find.text('Staging'), findsWidgets);
    });

    testWidgets('empty text shows all groups', (tester) async {
      await tester.pumpWidget(buildApp(existingGroups: ['Alpha', 'Beta']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus the group field — all options should appear
      final groupField = find.widgetWithText(TextFormField, 'Group');
      await tester.tap(groupField);
      await tester.pumpAndSettle();

      // Both options should be listed in the autocomplete overlay
      expect(find.text('Alpha'), findsWidgets);
      expect(find.text('Beta'), findsWidgets);
    });
  });

  group('SessionEditDialog — port validation', () {
    testWidgets('invalid port shows error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Host *'), 'example.com');
      await tester.enterText(find.widgetWithText(TextFormField, 'Username *'), 'root');
      await tester.enterText(find.widgetWithText(TextFormField, 'Port'), '99999');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });
  });

  group('SessionEditDialog — edit with key auth', () {
    testWidgets('editing session with key auth shows key fields pre-filled', (tester) async {
      final session = Session(
        label: 'key-server',
        host: '10.0.0.1',
        user: 'ubuntu',
        authType: AuthType.key,
        keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
        passphrase: 'pass123',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      // Key auth should be selected
      expect(find.text('Key Passphrase'), findsOneWidget);
      // PEM text should be visible since keyData is not empty
      expect(find.text('Key Text (PEM)'), findsOneWidget);
    });
  });

  group('SessionEditDialog — defaultGroup parameter', () {
    testWidgets('defaultGroup pre-fills group field', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await SessionEditDialog.show(
                  context,
                  defaultGroup: 'Production/Web',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Group field should have the default group
      expect(find.text('Production/Web'), findsWidgets);
    });
  });

  group('SessionEditDialog — passphrase visibility toggle', () {
    testWidgets('passphrase field has visibility toggle in Key auth', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Scroll to passphrase field
      await tester.scrollUntilVisible(
        find.text('Key Passphrase'),
        100,
        scrollable: find.byType(Scrollable).last,
      );

      // Find visibility icons — there should be one for passphrase
      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      // Tap the passphrase visibility icon (last one since password isn't shown in Key mode)
      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      // Should now show visibility_off
      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });
  });

  group('SessionEditDialog — edit session', () {
    testWidgets('shows Edit Session title', (tester) async {
      final session = Session(
        label: 'test-server',
        host: '10.0.0.1',
        user: 'root',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
    });

    testWidgets('Save button present for edit mode', (tester) async {
      final session = Session(
        label: 'test',
        host: 'h',
        user: 'u',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('fields pre-populated from session', (tester) async {
      final session = Session(
        label: 'my-server',
        host: '192.168.1.1',
        port: 2222,
        user: 'admin',
        group: 'Production',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('my-server'), findsOneWidget);
      // Host appears in both TextFormField and possibly autocomplete
      expect(find.text('192.168.1.1'), findsWidgets);
      expect(find.text('2222'), findsOneWidget);
      expect(find.text('admin'), findsWidgets);
    });
  });
}
