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

    testWidgets('per-host rows are indented relative to the select-all row', (
      tester,
    ) async {
      // Visual scoping: the "select all" tristate sits flush, individual host
      // rows live inside a left-padded container so the user can tell them
      // apart at a glance even though they share the same row primitive.
      await tester.pumpWidget(
        wrap(
          SshDirImportDialog(
            source: SshDirImportSource(
              hostsPreview: makeHostsPreview(hosts: 2),
              keys: const [],
              folderLabel: '.ssh 2026-04-15',
            ),
          ),
        ),
      );
      await tester.pump();

      final selectAll = tester.getRect(find.text('2 host(s) found'));
      final firstHost = tester.getRect(find.text('h0'));
      // First host row label sits to the right of the select-all label.
      expect(firstHost.left, greaterThan(selectAll.left));
    });

    testWidgets('Browse... button only appears when picker callback is wired', (
      tester,
    ) async {
      // Without a callback: no button.
      await tester.pumpWidget(
        wrap(
          SshDirImportDialog(
            source: SshDirImportSource(
              hostsPreview: makeHostsPreview(hosts: 1),
              keys: [makeKey(0)],
              folderLabel: '.ssh 2026-04-15',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.folder_open), findsNothing);

      // With both callbacks: one button per section.
      await tester.pumpWidget(
        wrap(
          SshDirImportDialog(
            source: SshDirImportSource(
              hostsPreview: makeHostsPreview(hosts: 1),
              keys: [makeKey(0)],
              folderLabel: '.ssh 2026-04-15',
            ),
            onPickConfigFile: () async => null,
            onPickKeyFiles: () async => null,
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.folder_open), findsNWidgets(2));
    });

    testWidgets(
      'browsing for an extra config appends new hosts and auto-selects them',
      (tester) async {
        final extra = Session(
          label: 'extra',
          server: const ServerAddress(host: 'extra.example.com', user: 'u'),
        );

        await tester.pumpWidget(
          wrap(
            SshDirImportDialog(
              source: SshDirImportSource(
                hostsPreview: makeHostsPreview(hosts: 1),
                keys: const [],
                folderLabel: '.ssh 2026-04-15',
              ),
              onPickConfigFile: () async =>
                  PickedConfigResult(sessions: [extra]),
            ),
          ),
        );
        await tester.pump();

        // 1 initial host + select-all = "1 host(s) found" trailing.
        expect(find.text('h0'), findsOneWidget);
        expect(find.text('extra'), findsNothing);

        await tester.tap(find.byIcon(Icons.folder_open).first);
        await tester.pumpAndSettle();

        expect(find.text('extra'), findsOneWidget);
        // Both rows checked → tristate select-all is fully on (value=true).
        final selectAllValue = (tester.widget<Checkbox>(
          find.byType(Checkbox).first,
        )).value;
        expect(selectAllValue, isTrue);
      },
    );

    testWidgets(
      'browsing for an extra key dedups by fingerprint (no double row)',
      (tester) async {
        final existing = makeKey(0);
        await tester.pumpWidget(
          wrap(
            SshDirImportDialog(
              source: SshDirImportSource(
                hostsPreview: null,
                keys: [existing],
                folderLabel: '.ssh',
              ),
              onPickKeyFiles: () async => [existing],
            ),
          ),
        );
        await tester.pump();
        expect(find.text('id_ed25519_0'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.folder_open).first);
        await tester.pumpAndSettle();

        expect(find.text('id_ed25519_0'), findsOneWidget); // still 1, not 2
      },
    );

    testWidgets(
      'hosts whose user@host:port already exists start unchecked with the '
      '"already in sessions" badge',
      (tester) async {
        // One of the parsed hosts (h0 → u@h0.example.com:22) matches a
        // session already in the store. That row must default to unchecked
        // so the user doesn't accidentally create a duplicate on import.
        await tester.pumpWidget(
          wrap(
            SshDirImportDialog(
              source: SshDirImportSource(
                hostsPreview: makeHostsPreview(hosts: 2),
                keys: const [],
                folderLabel: '.ssh 2026-04-15',
                existingSessionAddresses: {'u@h0.example.com:22'},
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('already in sessions'), findsOneWidget);

        // Boxes: select-all (tristate, null because 1 of 2 checked) +
        // h0 (off) + h1 (on).
        final boxes = tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .toList();
        expect(boxes[0].value, isNull, reason: 'mixed → tristate null');
        // The two host rows — one off, one on.
        final hostValues = boxes.sublist(1).map((c) => c.value).toList();
        expect(hostValues.where((v) => v == true).length, 1);
        expect(hostValues.where((v) => v == false).length, 1);
      },
    );

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
