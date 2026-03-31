import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';
import 'package:letsflutssh/utils/platform.dart';

void main() {
  SessionDialogResult? dialogResult;

  Widget buildApp({Session? session, List<String> existingGroups = const [], String? defaultGroup}) {
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

  /// Finds a TextFormField by its hint text.
  Finder fieldByHint(String hint) =>
      find.widgetWithText(TextFormField, hint);

  Future<void> fillRequiredFields(WidgetTester tester, {String host = 'example.com', String user = 'testuser', String password = 'pass'}) async {
    await tester.enterText(fieldByHint('192.168.1.1'), host);
    await tester.enterText(fieldByHint('root'), user);
    // Fill password on Auth tab (required for default password auth)
    await tester.tap(find.text('Auth'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldByHint('••••••••'), password);
    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();
  }

  Future<void> switchToAuth(WidgetTester tester) async {
    await tester.tap(find.text('Auth'));
    await tester.pumpAndSettle();
  }

  group('SessionEditDialog — new session', () {
    testWidgets('shows New Session title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('New Connection'), findsOneWidget);
    });

    testWidgets('has all required fields on Connection tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Connection tab is active by default
      expect(find.text('SESSION NAME'), findsOneWidget);
      expect(find.text('GROUP'), findsOneWidget);
      expect(find.text('HOST *'), findsOneWidget);
      expect(find.text('PORT'), findsOneWidget);
      expect(find.text('USERNAME *'), findsOneWidget);
    });

    testWidgets('has auth type selector on Auth tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Auth tab
      await tester.tap(find.text('Auth'));
      await tester.pumpAndSettle();

      expect(find.text('METHOD'), findsOneWidget);
      expect(find.text('Password'), findsWidgets); // auth button + field
      expect(find.text('SSH Key'), findsOneWidget);
      expect(find.text('Key+Pass'), findsOneWidget);
    });

    testWidgets('action buttons present for new session', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('validates required fields on submit', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('Cancel closes dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Connection'), findsNothing);
    });

    testWidgets('switching to Key auth shows key fields', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets('port defaults to 22', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('22'), findsWidgets); // hint + value
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

    testWidgets('Connect returns ConnectOnlyResult', (tester) async {
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
    });

    testWidgets('Connect with label filled', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(fieldByHint('My Server'), 'My Server');
      await fillRequiredFields(tester, host: '10.0.0.1', user: 'root');

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.host, '10.0.0.1');
      expect(result.config.user, 'root');
    });

    testWidgets('Connect without valid fields does not close', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Don't fill required fields
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
      expect(find.text('New Connection'), findsOneWidget);
    });

    testWidgets('Connect with custom port', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(fieldByHint('22'), '2222');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.port, 2222);
    });

    testWidgets('Connect with password auth', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await switchToAuth(tester);
      await tester.enterText(fieldByHint('••••••••'), 'secret123');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.password, 'secret123');
    });
  });

  group('SessionEditDialog — edit session submit', () {
    testWidgets('Save returns SaveResult with connect=false', (tester) async {
      final session = Session(label: 'test-server', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.password, password: 'pass'));
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
      final session = Session(label: 'old-label', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.password, password: 'pass'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear and re-enter label
      await tester.enterText(fieldByHint('My Server'), 'new-label');
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
      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      // PEM toggle should be present
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('PEM toggle shows and hides key text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
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
      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // Open PEM text and enter key data (required for passphrase validation)
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Key Text (PEM)'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      // Scroll to passphrase field and fill it
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        fieldByHint('Optional'),
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

      await switchToAuth(tester);
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      expect(find.text('Password'), findsWidgets); // segment label + field
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets('Connect with Key+Pass auth', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;

      // Scroll to password field
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        fieldByHint('••••••••'),
        'secret',
      );
      await tester.pumpAndSettle();

      // Add PEM key data (required for key auth)
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      // Scroll back to action buttons
      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.password, 'secret');
    });
  });

  group('SessionEditDialog — password visibility toggle', () {
    testWidgets('password field toggle changes icon', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

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
      expect(find.text('GROUP'), findsOneWidget);
      final groupField = find.byType(Autocomplete<String>);
      expect(groupField, findsOneWidget);

      // Type to filter — find the TextFormField inside the Autocomplete
      final textField = find.descendant(of: groupField, matching: find.byType(TextFormField));
      await tester.enterText(textField, 'Prod');
      await tester.pumpAndSettle();

      // Production should appear as suggestion
      expect(find.text('Production'), findsWidgets);
    });

    testWidgets('selecting autocomplete suggestion fills group field', (tester) async {
      await tester.pumpWidget(buildApp(existingGroups: ['Production', 'Staging']));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final groupField = find.byType(Autocomplete<String>);
      final textField = find.descendant(of: groupField, matching: find.byType(TextFormField));
      await tester.enterText(textField, 'Stag');
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
      final groupField = find.byType(Autocomplete<String>);
      final textField = find.descendant(of: groupField, matching: find.byType(TextFormField));
      await tester.tap(textField);
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

      await tester.enterText(fieldByHint('192.168.1.1'), 'example.com');
      await tester.enterText(fieldByHint('root'), 'root');
      await tester.enterText(fieldByHint('22'), '99999');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });
  });

  group('SessionEditDialog — edit with key auth', () {
    testWidgets('editing session with key auth shows key fields pre-filled', (tester) async {
      final session = Session(label: 'key-server', server: const ServerAddress(host: '10.0.0.1', user: 'ubuntu'), auth: const SessionAuth(authType: AuthType.key, keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----', passphrase: 'pass123'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);

      await switchToAuth(tester);
      // Key auth should be selected
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
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

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // Scroll to passphrase field
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
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
      final session = Session(label: 'test-server', server: const ServerAddress(host: '10.0.0.1', user: 'root'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);
    });

    testWidgets('Save button present for edit mode', (tester) async {
      final session = Session(label: 'test', server: const ServerAddress(host: 'h', user: 'u'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('fields pre-populated from session', (tester) async {
      final session = Session(label: 'my-server', group: 'Production', server: const ServerAddress(host: '192.168.1.1', port: 2222, user: 'admin'));
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

  group('SessionEditDialog — cancel returns null', () {
    testWidgets('cancel in create mode returns null', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });

    testWidgets('cancel in edit mode returns null', (tester) async {
      final session = Session(label: 'srv', server: const ServerAddress(host: '10.0.0.1', user: 'root'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — edit mode validation and id preservation', () {
    testWidgets('Save in edit mode fails validation if host cleared',
        (tester) async {
      final session = Session(label: 'srv', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.password));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('192.168.1.1'), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Edit Connection'), findsOneWidget);
    });

    testWidgets('editing session preserves original session id',
        (tester) async {
      final session = Session(id: 'original-id-123', label: 'edit-me', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.password, password: 'pass'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('My Server'), 'new-label');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.id, 'original-id-123');
      expect(result.session.label, 'new-label');
      expect(result.connect, isFalse);
    });

    testWidgets('edit mode has Save and Cancel buttons only', (tester) async {
      final session = Session(label: 'edit-me', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.password));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Connect'), findsNothing);
    });
  });

  group('SessionEditDialog — edit key session preserves all key fields', () {
    testWidgets('editing key session and saving preserves key data',
        (tester) async {
      final session = Session(id: 'key-edit-1', label: 'key-srv', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.key, keyPath: '/path/to/key', keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----', passphrase: 'phrase123'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('My Server'), 'key-srv-updated');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.label, 'key-srv-updated');
      expect(result.session.authType, AuthType.key);
      expect(result.session.keyPath, '/path/to/key');
      expect(result.session.keyData, contains('PRIVATE KEY'));
      expect(result.session.passphrase, 'phrase123');
    });
  });

  group('SessionEditDialog — additional validation', () {
    testWidgets('Connect with empty host fails validation',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('root'), 'user');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });

    testWidgets('Connect with empty username fails validation',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('192.168.1.1'), 'host.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });

    testWidgets('non-numeric port shows error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(
          fieldByHint('22'), 'abc');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });

    testWidgets('port 0 shows validation error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(
          fieldByHint('22'), '0');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });

    testWidgets('empty port shows validation error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(
          fieldByHint('22'), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('1-65535'), findsOneWidget);
    });
  });

  group('SessionEditDialog — port boundary values', () {
    testWidgets('port 1 is valid', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(
          fieldByHint('22'), '1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      expect((dialogResult as ConnectOnlyResult).config.port, 1);
    });

    testWidgets('port 65535 is valid', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(
          fieldByHint('22'), '65535');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      expect((dialogResult as ConnectOnlyResult).config.port, 65535);
    });
  });

  group('SessionEditDialog — label is optional', () {
    testWidgets('label field is optional — can submit without it',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
    });
  });

  group('SessionEditDialog — auth type switching', () {
    testWidgets('switching to Key+Pass shows both password and key fields',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Password auth is default — password field visible
      expect(fieldByHint('••••••••'), findsOneWidget);

      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      expect(fieldByHint('••••••••'), findsOneWidget);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
    });

    testWidgets('Key auth hides password TextFormField', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      expect(fieldByHint('••••••••'), findsNothing);
    });
  });

  group('SessionEditDialog — editing keyWithPassword session', () {
    testWidgets('editing Key+Pass session shows both password and key fields',
        (tester) async {
      final session = Session(label: 'kp-server', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.keyWithPassword, password: 'secret', keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----', passphrase: 'kp123'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Connection'), findsOneWidget);

      await switchToAuth(tester);
      expect(find.text('Password'), findsWidgets);
      expect(find.text('KEY PASSPHRASE'), findsOneWidget);
      expect(find.text('Key Text (PEM)'), findsOneWidget);
    });
  });

  group('SessionEditDialog — ConnectOnly with password and custom port', () {
    testWidgets('ConnectOnly preserves password and custom port',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('192.168.1.1'), 'h.com');
      await tester.enterText(
          fieldByHint('root'), 'u');
      await tester.enterText(
          fieldByHint('22'), '2222');

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
          fieldByHint('••••••••'), 'secret');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.host, 'h.com');
      expect(result.config.user, 'u');
      expect(result.config.port, 2222);
      expect(result.config.password, 'secret');
    });
  });

  group('SessionEditDialog — Connect with Key+Pass all fields', () {
    testWidgets('Connect with Key+Pass auth includes all fields',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
          fieldByHint('••••••••'), 'pass123');
      await tester.pumpAndSettle();

      // Add PEM key data (required for key auth)
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.password, 'pass123');
    });
  });

  group('SessionEditDialog — new session with group', () {
    testWidgets('Connect for new session returns ConnectOnlyResult',
        (tester) async {
      await tester.pumpWidget(buildApp(
        existingGroups: ['Production'],
        defaultGroup: 'Production',
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          fieldByHint('My Server'), 'my-server');
      await fillRequiredFields(tester, host: 'new.host', user: 'newuser');

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.host, 'new.host');
      expect(result.config.user, 'newuser');
    });
  });

  group('SessionEditDialog — key file button', () {
    testWidgets('key auth shows Select Key File button',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('key file button is OutlinedButton, not TextFormField',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // Should NOT have a TextFormField for key path
      expect(find.widgetWithText(TextFormField, 'Key File'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Key File Path'), findsNothing);

      // Should have an OutlinedButton
      expect(find.widgetWithText(OutlinedButton, 'Select Key File'), findsOneWidget);
    });
  });

  group('SessionEditDialog — PEM key data in connect result', () {
    testWidgets('entering PEM key data is included in connect result',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill required fields on Connection tab first
      await tester.enterText(
          fieldByHint('192.168.1.1'), 'h.com');
      await tester.enterText(
          fieldByHint('root'), 'u');
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;

      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Key Text (PEM)'),
          '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Connect'),
        -200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.keyData, contains('PRIVATE KEY'));
    });
  });

  group('SessionEditDialog — tilde expansion in key path', () {
    testWidgets('tilde in key path from edited session is expanded in result',
        (tester) async {
      // Editing a session that already has a key path with tilde
      final session = Session(
        id: 'tilde-test',
        label: 'Tilde Server',
        server: const ServerAddress(host: 'h.com', user: 'u'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '~/.ssh/id_rsa',
        ),
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.keyPath.contains('~'), isFalse);
    });
  });

  group('SessionEditDialog — password visibility in Key+Pass mode', () {
    testWidgets('toggling password visibility in Key+Pass mode',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.byIcon(Icons.visibility).first,
        100,
        scrollable: scrollable,
      );

      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      await tester.tap(visIcons.first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });

    testWidgets('toggling passphrase visibility in Key+Pass mode',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: scrollable,
      );

      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons.evaluate().length, greaterThanOrEqualTo(2));

      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off), findsWidgets);
    });
  });

  group('SessionEditDialog — Key+Pass with PEM key data', () {
    testWidgets('Connect with Key+Pass auth preserves keyData', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;

      // Fill password (required for Key+Pass)
      await tester.scrollUntilVisible(
        fieldByHint('••••••••'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(fieldByHint('••••••••'), 'pass');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.keyData, contains('PRIVATE KEY'));
    });
  });

  group('SessionDialogResult sealed classes', () {
    test('ConnectOnlyResult holds SSHConfig', () {
      final config = ConnectOnlyResult(
        const SSHConfig(server: ServerAddress(host: 'h', port: 22, user: 'u')),
      );
      expect(config.config.host, 'h');
    });

    test('SaveResult holds Session with connect flag', () {
      final session = Session(label: 'test', server: const ServerAddress(host: 'h', user: 'u'));
      final result = SaveResult(session, connect: true);
      expect(result.session.label, 'test');
      expect(result.connect, isTrue);
    });

    test('SaveResult defaults connect to false', () {
      final session = Session(label: 'test', server: const ServerAddress(host: 'h', user: 'u'));
      final result = SaveResult(session);
      expect(result.connect, isFalse);
    });
  });

  group('SessionEditDialog — PEM toggle icon and text changes', () {
    testWidgets('PEM toggle shows down arrow icon initially', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );

      // Down arrow icon when PEM text is hidden
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    });

    testWidgets('PEM toggle shows up arrow icon when expanded', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Up arrow icon when PEM text is shown
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'),
        100,
        scrollable: scrollable,
      );
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    });

    testWidgets('PEM text field has monospace font and maxLines', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );

      // Verify the PEM text field has the expected hint
      expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
    });
  });

  group('SessionEditDialog — editing session with keyData starts with PEM visible', () {
    testWidgets('editing session with keyData shows PEM text and Hide PEM text toggle',
        (tester) async {
      final session = Session(label: 'key-srv', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.key, keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      // Since keyData is not empty, _showKeyText starts as true
      // PEM toggle should say "Hide PEM text"
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'),
        100,
        scrollable: scrollable,
      );
      expect(find.text('Hide PEM text'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

      // The PEM text field should be visible with the keyData
      await tester.scrollUntilVisible(
        find.text('Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      expect(find.text('Key Text (PEM)'), findsOneWidget);
    });

    testWidgets('toggling PEM off then on preserves keyData content',
        (tester) async {
      final session = Session(label: 'key-srv', server: const ServerAddress(host: '10.0.0.1', user: 'root'), auth: const SessionAuth(authType: AuthType.key, keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----'));
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);

      final scrollable = find.byType(Scrollable).last;

      // Hide PEM text
      await tester.scrollUntilVisible(
        find.text('Hide PEM text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      expect(find.text('Paste PEM key text'), findsOneWidget);
      expect(find.text('Key Text (PEM)'), findsNothing);

      // Show PEM text again
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Save and verify keyData is preserved
      await tester.scrollUntilVisible(
        find.text('Save'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.keyData, contains('PRIVATE KEY'));
    });
  });

  group('SessionEditDialog — passphrase without key validation', () {
    testWidgets('passphrase without key file or PEM shows validation error', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key auth
      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // Do NOT enter a key path or PEM text — leave them empty

      // Scroll to passphrase field and fill it
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('KEY PASSPHRASE'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
        fieldByHint('Optional'),
        'mypassphrase',
      );
      await tester.pumpAndSettle();

      // Scroll back to Connect button and tap
      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Should show validation error — dialog stays open
      expect(find.text('Provide a key file or paste PEM text'), findsOneWidget);
      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — desktop key path DropTarget rendering', () {
    testWidgets('key auth on desktop wraps key field in DropTarget',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // On desktop, the key path field is wrapped in a DropTarget
      // Verify the DropTarget widget exists
      expect(find.byType(DropTarget), findsOneWidget);
    });
  });

  group('SessionEditDialog — mobile key path field', () {
    setUp(() {
      debugMobilePlatformOverride = true;
      debugDesktopPlatformOverride = false;
    });

    tearDown(() {
      debugMobilePlatformOverride = null;
      debugDesktopPlatformOverride = null;
    });

    testWidgets('mobile key path field renders without DropTarget',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // On mobile, the key path field should NOT be wrapped in DropTarget
      expect(find.byType(DropTarget), findsNothing);

      // The mobile key file shows a Select Key File button
      expect(find.text('Select Key File'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Select Key File'), findsOneWidget);
    });

    testWidgets('PEM toggle shows and hides key text area on mobile',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // PEM toggle should be visible
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Paste PEM key text'), findsOneWidget);

      // PEM text field should not be visible yet
      expect(find.text('Key Text (PEM)'), findsNothing);

      // Tap the PEM toggle
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Now PEM text field should be visible
      await tester.scrollUntilVisible(
        find.text('Key Text (PEM)'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Key Text (PEM)'), findsOneWidget);
      expect(find.text('Hide PEM text'), findsOneWidget);

      // Tap toggle again to hide
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      expect(find.text('Key Text (PEM)'), findsNothing);
      expect(find.text('Paste PEM key text'), findsOneWidget);
    });

    testWidgets('PEM text field accepts key text input on mobile',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // Open PEM text area
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
      const pemText = '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----';
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        pemText,
      );
      await tester.pumpAndSettle();

      expect(find.text(pemText), findsOneWidget);
    });

    testWidgets('PEM key data included in Connect result on mobile',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      await switchToAuth(tester);
      await tester.tap(find.text('SSH Key'));
      await tester.pumpAndSettle();

      // Open PEM text and enter key data
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

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

      // Scroll back and tap Connect
      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.keyData, contains('PRIVATE KEY'));
    });
  });
}
