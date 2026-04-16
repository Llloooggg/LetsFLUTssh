import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/link_import_preview_dialog.dart';

void main() {
  ExportPayloadData makePayload({
    int sessionsCount = 2,
    int managerKeys = 1,
    int tags = 3,
    int snippets = 4,
    bool config = true,
    bool knownHosts = true,
  }) {
    return ExportPayloadData(
      sessions: List.generate(
        sessionsCount,
        (i) => Session(
          id: 's$i',
          label: 'S$i',
          server: ServerAddress(host: 'h$i', user: 'u'),
        ),
      ),
      emptyFolders: const {},
      managerKeys: List.generate(
        managerKeys,
        (i) => SshKeyEntry(
          id: 'k$i',
          label: 'key$i',
          privateKey: 'p$i',
          publicKey: '',
          keyType: 'rsa',
          createdAt: DateTime(2025, 1, 1),
        ),
      ),
      tags: List.generate(
        tags,
        (i) => Tag(id: 't$i', name: 'tag$i', color: '#fff'),
      ),
      snippets: List.generate(
        snippets,
        (i) => Snippet(id: 'sn$i', title: 'sn$i', command: 'echo $i'),
      ),
      config: config ? const AppConfig() : null,
      knownHostsContent: knownHosts ? 'host ssh-rsa AAA' : null,
    );
  }

  Widget buildDialog(ExportPayloadData payload) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LinkImportPreviewDialog(payload: payload),
        ),
      ),
    );
  }

  group('LinkImportPreviewDialog', () {
    testWidgets('renders counts from payload', (tester) async {
      await tester.pumpWidget(buildDialog(makePayload()));
      await tester.pump();

      expect(find.text('Import Data'), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // sessions
      expect(find.text('3'), findsOneWidget); // tags
      expect(find.text('4'), findsOneWidget); // snippets
    });

    testWidgets('renders merge/replace selector', (tester) async {
      await tester.pumpWidget(buildDialog(makePayload()));
      await tester.pump();

      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
    });

    testWidgets('renders Cancel and Import actions', (tester) async {
      await tester.pumpWidget(buildDialog(makePayload()));
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('tapping Replace switches description text', (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDialog(makePayload()));
      await tester.pump();

      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await tester.pump();
      expect(find.text('Replace all sessions with imported'), findsOneWidget);
    });

    testWidgets('config:true shows "Yes" next to App Settings', (tester) async {
      await tester.pumpWidget(buildDialog(makePayload(config: true)));
      await tester.pump();

      // App Settings + Known Hosts rows each render "Yes" trailing label.
      expect(find.text('App Settings'), findsOneWidget);
      expect(find.text('Yes'), findsNWidgets(2));
    });

    testWidgets('config:false shows "No" next to App Settings', (tester) async {
      await tester.pumpWidget(
        buildDialog(makePayload(config: false, knownHosts: false)),
      );
      await tester.pump();

      // Both config and known_hosts absent → both rows render "No".
      expect(find.text('App Settings'), findsOneWidget);
      expect(find.text('No'), findsNWidgets(2));
      expect(find.text('Yes'), findsNothing);
    });

    testWidgets('Import result carries selected mode + options', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      LinkImportPreviewResult? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await LinkImportPreviewDialog.show(
                    ctx,
                    payload: makePayload(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.pump();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.mode, ImportMode.replace);
      expect(result!.options.includeSessions, isTrue);
    });
  });
}
