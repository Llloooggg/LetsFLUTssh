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

  group('SessionEditDialog — Save in edit mode with validation failure', () {
    testWidgets('Save in edit mode fails validation if host cleared',
        (tester) async {
      final session = Session(
        label: 'srv',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.password,
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear the host field to trigger validation failure
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), '');
      await tester.pumpAndSettle();

      // Tap Save — should fail validation
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Validation error should show
      expect(find.text('Required'), findsOneWidget);
      // Dialog should still be open
      expect(find.text('Edit Session'), findsOneWidget);
    });
  });

  group('SessionEditDialog — edit mode preserves session id via copyWith', () {
    testWidgets('editing session preserves original session id',
        (tester) async {
      final session = Session(
        id: 'original-id-123',
        label: 'edit-me',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.password,
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Change the label
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Label'), 'new-label');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.id, 'original-id-123');
      expect(result.session.label, 'new-label');
      expect(result.connect, isFalse);
    });
  });

  group('SessionEditDialog — connect-only validation fail', () {
    testWidgets('Connect button with empty username fails validation',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Only fill host, not username
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'host.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Validation should fail
      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — save&connect validation fail', () {
    testWidgets('Save&Connect with empty host fails validation',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Only fill username, not host
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'user');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      // Validation should fail
      expect(find.text('Required'), findsOneWidget);
      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — Save&Connect with full key+pass auth', () {
    testWidgets('Save&Connect with Key+Pass auth includes all fields',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);

      // Switch to Key+Pass
      await tester.tap(find.text('Key+Pass'));
      await tester.pumpAndSettle();

      // Enter password
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'pass123');
      await tester.pumpAndSettle();

      // Scroll to Save & Connect and tap
      await tester.scrollUntilVisible(
        find.text('Save & Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.authType, AuthType.keyWithPassword);
      expect(result.session.password, 'pass123');
      expect(result.connect, isTrue);
    });
  });

  group('SessionEditDialog — edit key session save preserves all key fields', () {
    testWidgets('editing key session and saving preserves key data',
        (tester) async {
      final session = Session(
        id: 'key-edit-1',
        label: 'key-srv',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.key,
        keyPath: '/path/to/key',
        keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
        passphrase: 'phrase123',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Just change the label and save
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Label'), 'key-srv-updated');
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

  group('SessionEditDialog — ConnectOnly builds SSHConfig correctly', () {
    testWidgets('ConnectOnly preserves password and custom port',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'h.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'u');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Port'), '2222');

      // Enter password
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Password'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'secret');
      await tester.pumpAndSettle();

      // Scroll back to Connect
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

  group('SessionEditDialog — new session builds correctly (not edit)', () {
    testWidgets('Save&Connect for new session creates new Session with group',
        (tester) async {
      await tester.pumpWidget(buildApp(
        existingGroups: ['Production'],
        defaultGroup: 'Production',
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Fill label
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Label'), 'my-server');

      await fillRequiredFields(tester, host: 'new.host', user: 'newuser');

      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<SaveResult>());
      final result = dialogResult as SaveResult;
      expect(result.session.label, 'my-server');
      expect(result.session.group, 'Production');
      expect(result.session.host, 'new.host');
      expect(result.session.user, 'newuser');
      expect(result.connect, isTrue);
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
      final session = Session(
        label: 'srv',
        host: '10.0.0.1',
        user: 'root',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });
  });

  group('SessionEditDialog — port validation boundary', () {
    testWidgets('port 1 is valid', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await fillRequiredFields(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Port'), '1');
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
          find.widgetWithText(TextFormField, 'Port'), '65535');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      expect((dialogResult as ConnectOnlyResult).config.port, 65535);
    });
  });
}
