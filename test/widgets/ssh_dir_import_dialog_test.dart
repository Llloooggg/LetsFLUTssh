import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/openssh_config_importer.dart';
import 'package:letsflutssh/core/import/ssh_dir_key_scanner.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/ssh_dir_import_dialog.dart';

void main() {
  OpenSshConfigImportPreview makeHostsPreview({
    int hosts = 2,
    List<String> missingKeys = const [],
    String folder = '.ssh 2026-04-15',
  }) {
    final sessions = List.generate(
      hosts,
      (i) => Session(
        label: 'h$i',
        folder: folder,
        server: ServerAddress(host: 'h$i.example.com', user: 'u'),
      ),
    );
    return OpenSshConfigImportPreview(
      result: ImportResult(sessions: sessions, mode: ImportMode.merge),
      parsedHosts: hosts,
      hostsWithMissingKeys: missingKeys,
    );
  }

  ScannedKey makeKey(int i) => ScannedKey(
    path: '/home/u/.ssh/id_ed25519_$i',
    pem:
        '-----BEGIN OPENSSH PRIVATE KEY-----\nbogus$i\n-----END OPENSSH PRIVATE KEY-----',
    suggestedLabel: 'id_ed25519_$i',
  );

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: AppTheme.dark(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('SshDirImportDialog', () {
    testWidgets('renders both sections when hosts and keys are present', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SshDirImportDialog(
            source: SshDirImportSource(
              hostsPreview: makeHostsPreview(hosts: 2),
              keys: [makeKey(0), makeKey(1)],
              folderLabel: '.ssh 2026-04-15',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Hosts from config'), findsOneWidget);
      expect(find.text('Keys in ~/.ssh'), findsOneWidget);
      expect(find.text('h0'), findsOneWidget);
      expect(find.text('id_ed25519_0'), findsOneWidget);
    });

    testWidgets('hosts-only source shows the keys-empty state', (tester) async {
      await tester.pumpWidget(
        wrap(
          SshDirImportDialog(
            source: SshDirImportSource(
              hostsPreview: makeHostsPreview(hosts: 1),
              keys: const [],
              folderLabel: '.ssh 2026-04-15',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No private keys found in ~/.ssh.'), findsWidgets);
    });

    testWidgets(
      'keys-only source (no config) hides host rows but keeps the keys section',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            SshDirImportDialog(
              source: SshDirImportSource(
                hostsPreview: null,
                keys: [makeKey(0)],
                folderLabel: '.ssh 2026-04-15',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('No importable hosts found in this file.'),
          findsWidgets,
        );
        expect(find.text('id_ed25519_0'), findsOneWidget);
      },
    );

    testWidgets('all host checkboxes default to checked', (tester) async {
      await tester.pumpWidget(
        wrap(
          SshDirImportDialog(
            source: SshDirImportSource(
              hostsPreview: makeHostsPreview(hosts: 3),
              keys: const [],
              folderLabel: '.ssh 2026-04-15',
            ),
          ),
        ),
      );
      await tester.pump();

      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      // 3 host rows + 1 "select all" tristate = all should start checked.
      expect(
        boxes.where((c) => c.value == true).length,
        greaterThanOrEqualTo(3),
      );
    });

    testWidgets(
      'already-imported keys start unchecked with the "already in store" badge',
      (tester) async {
        final key = makeKey(0);
        await tester.pumpWidget(
          wrap(
            SshDirImportDialog(
              source: SshDirImportSource(
                hostsPreview: null,
                keys: [key],
                folderLabel: '.ssh 2026-04-15',
                existingKeyFingerprints: {
                  KeyStore.privateKeyFingerprint(key.pem),
                },
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('already in store'), findsOneWidget);
        // The one key row's checkbox is off. The tristate for the Keys
        // section is also off (nothing selected). Hosts section is empty so
        // only these two Checkboxes exist.
        final boxes = tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .toList();
        expect(boxes.every((c) => c.value == false), isTrue);
      },
    );
  });
}
