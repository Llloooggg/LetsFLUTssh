import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';
import 'package:letsflutssh/core/session/session.dart';

void main() {
  Widget buildApp({Session? session, List<String> existingGroups = const []}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              SessionEditDialog.show(
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
