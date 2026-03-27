import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/qr_export_dialog.dart';

void main() {
  Session makeSession({
    String label = 'test',
    String host = 'example.com',
    int port = 22,
    String user = 'root',
    String group = '',
  }) {
    return Session(
      label: label,
      server: ServerAddress(host: host, port: port, user: user),
      group: group,
    );
  }

  Widget buildApp({required List<Session> sessions, Set<String> emptyGroups = const {}}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => QrExportDialog.show(
              context,
              sessions: sessions,
              emptyGroups: emptyGroups,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
  }

  group('QrExportDialog', () {
    testWidgets('shows disclaimer about no credentials', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Passwords and SSH keys are NOT included'), findsOneWidget);
    });

    testWidgets('shows Select All with correct count', (tester) async {
      final sessions = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Select All (2/2)'), findsOneWidget);
    });

    testWidgets('shows session labels', (tester) async {
      final sessions = [
        makeSession(label: 'nginx', host: 'a.com'),
        makeSession(label: 'api', host: 'b.com'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('nginx'), findsOneWidget);
      expect(find.text('api'), findsOneWidget);
    });

    testWidgets('shows group folders', (tester) async {
      final sessions = [
        makeSession(label: 'web1', group: 'Production'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions, emptyGroups: {'Production'}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Production'), findsOneWidget);
    });

    testWidgets('shows payload size indicator', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('KB'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('Cancel button closes dialog', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Export Sessions via QR'), findsNothing);
    });

    testWidgets('Show QR button is enabled when selection fits', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Show QR'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('deselecting all disables Show QR', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Deselect all via Select All checkbox
      await tester.tap(find.textContaining('Select All'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Select All (0/1)'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Show QR'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('toggling individual session updates count', (tester) async {
      final sessions = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Both selected initially
      expect(find.textContaining('Select All (2/2)'), findsOneWidget);

      // Tap on first session to deselect
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1/2)'), findsOneWidget);
    });

    testWidgets('Export All button exists', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Export All'), findsOneWidget);
    });

    testWidgets('Show QR returns deep link URL', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await QrExportDialog.show(
                  context,
                  sessions: [makeSession()],
                  emptyGroups: const {},
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show QR'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, startsWith('letsflutssh://import?d='));
    });

    testWidgets('shows host:port for each session', (tester) async {
      final sessions = [makeSession(label: 'srv', host: 'myhost.com')];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('root@myhost.com'), findsOneWidget);
    });
  });
}
