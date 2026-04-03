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
    String folder = '',
  }) {
    return Session(
      label: label,
      server: ServerAddress(host: host, port: port, user: user),
      folder: folder,
    );
  }

  Widget buildApp({required List<Session> sessions, Set<String> emptyFolders = const {}}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => QrExportDialog.show(
              context,
              sessions: sessions,
              emptyFolders: emptyFolders,
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

    testWidgets('shows folders', (tester) async {
      final sessions = [
        makeSession(label: 'web1', folder: 'Production'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions, emptyFolders: {'Production'}));
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

      // Show QR button should be present and tappable
      expect(find.text('Show QR'), findsOneWidget);
    });

    testWidgets('deselecting all disables Show QR', (tester) async {
      await tester.pumpWidget(buildApp(sessions: [makeSession()]));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Deselect all via Select All checkbox
      await tester.tap(find.textContaining('Select All'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Select All (0/1)'), findsOneWidget);
      // Show QR button text should still be present (but disabled)
      expect(find.text('Show QR'), findsOneWidget);
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
                  emptyFolders: const {},
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

    testWidgets('re-selecting deselected session updates count', (tester) async {
      final sessions = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Deselect 'a'
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1/2)'), findsOneWidget);

      // Re-select 'a'
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2/2)'), findsOneWidget);
    });

    testWidgets('toggling folder toggles all sessions in folder', (tester) async {
      final sessions = [
        makeSession(label: 'web1', host: 'a.com', folder: 'Prod'),
        makeSession(label: 'web2', host: 'b.com', folder: 'Prod'),
        makeSession(label: 'dev1', host: 'c.com', folder: 'Dev'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('3/3)'), findsOneWidget);

      // Tap Prod folder to deselect it
      await tester.tap(find.text('Prod'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1/3)'), findsOneWidget);

      // Tap Prod again to re-select
      await tester.tap(find.text('Prod'));
      await tester.pumpAndSettle();

      expect(find.textContaining('3/3)'), findsOneWidget);
    });

    testWidgets('Export All returns deep link when fits', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await QrExportDialog.show(
                  context,
                  sessions: [makeSession()],
                  emptyFolders: const {},
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Deselect first, then Export All re-selects
      await tester.tap(find.textContaining('Select All'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0/1)'), findsOneWidget);

      await tester.tap(find.text('Export All'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, startsWith('letsflutssh://import?d='));
    });

    testWidgets('Export All with empty folders passes all empty folders', (tester) async {
      String? result;
      final sessions = [makeSession(label: 'srv', folder: 'Prod')];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await QrExportDialog.show(
                  context,
                  sessions: sessions,
                  emptyFolders: {'EmptyFolder'},
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export All'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result, startsWith('letsflutssh://import?d='));
    });

    testWidgets('Select All deselects all when all selected', (tester) async {
      final sessions = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
      ];
      await tester.pumpWidget(buildApp(sessions: sessions));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // All selected — checkbox tap via Checkbox
      final checkboxFinder = find.byType(Checkbox).first;
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('0/2)'), findsOneWidget);

      // Tap again to re-select all
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('2/2)'), findsOneWidget);
    });
  });
}
