import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/features/session_manager/session_edit_dialog.dart';

void main() {
  SessionDialogResult? dialogResult;

  Widget buildApp({
    Session? session,
    List<String> existingGroups = const [],
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
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  group('SessionEditDialog — desktop key path field (lines 368-397)', () {
    // On desktop (Linux in test), the _buildDesktopKeyPathField is used
    // which includes DropTarget for drag&drop key files.
    testWidgets('key auth shows Key File field with DropTarget on desktop',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Key File field should be present
      expect(find.text('Key File'), findsOneWidget);

      // The hint text for desktop key path
      expect(find.text('~/.ssh/id_rsa'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('key path field accepts text input', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      // Scroll to find Key File field
      final scrollable = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key File'),
        100,
        scrollable: scrollable,
      );

      // Enter a key path
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Key File'), '/home/user/.ssh/id_ed25519');
      await tester.pumpAndSettle();

      // Fill required fields
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Host *'),
        -200,
        scrollable: scrollable,
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'host.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'user');
      await tester.pumpAndSettle();

      // Scroll to Connect button
      await tester.scrollUntilVisible(
        find.text('Connect'),
        -100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(dialogResult, isA<ConnectOnlyResult>());
      final result = dialogResult as ConnectOnlyResult;
      expect(result.config.keyPath, '/home/user/.ssh/id_ed25519');
    });
  });

  group('SessionEditDialog — PEM toggle and text field (lines 346-348)', () {
    testWidgets('PEM toggle shows/hides PEM text field', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;

      // Find PEM toggle
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );

      // Tap to show PEM text field
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // PEM text field should appear
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      expect(find.widgetWithText(TextFormField, 'Key Text (PEM)'), findsOneWidget);

      // Toggle should now show "Hide PEM text"
      expect(find.text('Hide PEM text'), findsOneWidget);

      // Tap to hide
      await tester.tap(find.text('Hide PEM text'));
      await tester.pumpAndSettle();

      expect(find.text('Paste PEM key text'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('entering PEM key data is included in connect result',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;

      // Fill required fields first
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'h.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'u');
      await tester.pumpAndSettle();

      // Show PEM field
      await tester.scrollUntilVisible(
        find.text('Paste PEM key text'),
        100,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Paste PEM key text'));
      await tester.pumpAndSettle();

      // Enter PEM data
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Text (PEM)'),
        100,
        scrollable: scrollable,
      );
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Key Text (PEM)'),
          '-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----');
      await tester.pumpAndSettle();

      // Scroll to Connect
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

  group('SessionEditDialog — edit session with keyData shows PEM expanded', () {
    testWidgets('editing session with keyData auto-expands PEM field',
        (tester) async {
      final session = Session(
        label: 'key-srv',
        host: '10.0.0.1',
        user: 'root',
        authType: AuthType.key,
        keyData: '-----BEGIN OPENSSH PRIVATE KEY-----\ndata\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.pumpWidget(buildApp(session: session));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // PEM field should be auto-expanded since keyData is non-empty
      expect(find.text('Hide PEM text'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SessionEditDialog — passphrase field visibility toggle', () {
    testWidgets('passphrase visibility toggle works', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Switch to Key auth
      await tester.tap(find.text('Key'));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).last;

      // Scroll to passphrase field
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Key Passphrase'),
        100,
        scrollable: scrollable,
      );

      // Find the visibility toggle for passphrase
      final visIcons = find.byIcon(Icons.visibility);
      expect(visIcons, findsWidgets);

      // Tap the last visibility icon (passphrase field's toggle)
      await tester.tap(visIcons.last);
      await tester.pumpAndSettle();

      // Should now show visibility_off
      expect(find.byIcon(Icons.visibility_off), findsWidgets);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
