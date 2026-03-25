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
