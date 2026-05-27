/// Widget tests for [SshDirImportDialog] — the unified `~/.ssh` import
/// pick-list (hosts from `config` + keys in the dir).
///
/// FRB is loaded because the dialog computes key fingerprints
/// (`privateKeyFingerprint` → `keys_normalized_text_fingerprint`,
/// sync) in `initState` and parses PEMs (`importSshKey`, async) on
/// submit. No DB is touched, so no `frb_global_store` isolation is
/// needed — the calls are pure crypto over the process-global Rust
/// core. A real key pair is minted once for the submit-with-key case
/// so the PEM actually parses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/export_import.dart';
import 'package:letsflutssh/core/import/openssh_config_importer.dart';
import 'package:letsflutssh/core/import/ssh_dir_key_scanner.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/core/app_button.dart';
import 'package:letsflutssh/widgets/core/data_checkboxes.dart';
import 'package:letsflutssh/widgets/import_export/ssh_dir_import_dialog.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A real, parseable PEM for the submit-with-key path. Synthetic
  // strings parse to nothing (importSshKey throws and the dialog skips
  // them), which is fine for the selection-UI tests but can't prove a
  // managerKey lands in the result.
  late String realPem;

  setUpAll(() async {
    await requireFrbLoaded();
    final generated = await generateSshKeyPair(SshKeyType.ed25519, 'fixture');
    realPem = generated.privateKey;
  });

  Session host(
    String id,
    String label, {
    String hostname = 'h.example',
    String user = 'root',
    int port = 22,
    String keyId = '',
  }) {
    return Session(
      id: id,
      label: label,
      server: ServerAddress(host: hostname, port: port, user: user),
      auth: SessionAuth(keyId: keyId),
    );
  }

  SshDirImportSource source({
    List<Session> hosts = const [],
    List<ScannedKey> keys = const [],
    Set<String> existingSessionAddresses = const {},
    Set<String> existingKeyFingerprints = const {},
    List<String> hostsWithMissingKeys = const [],
  }) {
    return SshDirImportSource(
      hostsPreview: hosts.isEmpty
          ? null
          : OpenSshConfigImportPreview(
              result: ImportResult(sessions: hosts, mode: ImportMode.merge),
              parsedHosts: hosts.length,
              hostsWithMissingKeys: hostsWithMissingKeys,
            ),
      keys: keys,
      folderLabel: 'Imported',
      existingSessionAddresses: existingSessionAddresses,
      existingKeyFingerprints: existingKeyFingerprints,
    );
  }

  ScannedKey scannedKey(String label, String pem) =>
      ScannedKey(path: '/home/u/.ssh/$label', pem: pem, suggestedLabel: label);

  /// Mount the dialog behind an opener button so its `Navigator.pop`
  /// result is captured. Returns a getter for the captured result.
  Future<ImportResult? Function()> open(
    WidgetTester tester,
    SshDirImportSource src, {
    PickConfigCallback? onPickConfigFile,
    PickKeysCallback? onPickKeyFiles,
  }) async {
    ImportResult? captured;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await SshDirImportDialog.show(
                  context,
                  source: src,
                  onPickConfigFile: onPickConfigFile,
                  onPickKeyFiles: onPickKeyFiles,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => done ? captured : null;
  }

  bool? rowValue(WidgetTester tester, String label) {
    final row = tester.widget<DataCheckboxRow>(
      find.byWidgetPredicate((w) => w is DataCheckboxRow && w.label == label),
    );
    return row.value;
  }

  DataCheckboxRow selectAllRow(WidgetTester tester) {
    return tester.widget<DataCheckboxRow>(
      find.byWidgetPredicate(
        (w) => w is DataCheckboxRow && w.tristate && w.icon == Icons.done_all,
      ),
    );
  }

  /// Pump frames + real event-loop ticks until [predicate] holds, for
  /// the submit path whose `_buildResult` awaits the async `importSshKey`.
  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() predicate, {
    int maxTicks = 60,
  }) async {
    for (var i = 0; i < maxTicks && !predicate(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  group('host selection', () {
    testWidgets('fresh hosts default checked, dups default unchecked', (
      tester,
    ) async {
      await open(
        tester,
        source(
          hosts: [
            host('h1', 'web-1', hostname: 'a'),
            host('h2', 'web-2'),
          ],
          existingSessionAddresses: {'root@h.example:22'},
        ),
      );
      expect(rowValue(tester, 'web-1'), isTrue);
      expect(rowValue(tester, 'web-2'), isFalse);
      expect(find.text('already in sessions'), findsOneWidget);
    });

    testWidgets('tapping a host row toggles its checkbox', (tester) async {
      await open(tester, source(hosts: [host('h1', 'web-1', hostname: 'a')]));
      expect(rowValue(tester, 'web-1'), isTrue);
      await tester.tap(find.text('web-1'));
      await tester.pumpAndSettle();
      expect(rowValue(tester, 'web-1'), isFalse);
    });

    testWidgets('select-all is tristate and flips every host', (tester) async {
      await open(
        tester,
        source(
          hosts: [
            host('h1', 'web-1', hostname: 'a'),
            host('h2', 'web-2'),
          ],
          existingSessionAddresses: {'root@h.example:22'},
        ),
      );
      // One of two checked → indeterminate.
      expect(selectAllRow(tester).value, isNull);
      await tester.tap(find.byWidget(selectAllRow(tester)));
      await tester.pumpAndSettle();
      expect(rowValue(tester, 'web-1'), isTrue);
      expect(rowValue(tester, 'web-2'), isTrue);
      await tester.tap(find.byWidget(selectAllRow(tester)));
      await tester.pumpAndSettle();
      expect(rowValue(tester, 'web-1'), isFalse);
      expect(rowValue(tester, 'web-2'), isFalse);
    });
  });

  group('key selection', () {
    testWidgets('keys already in the store default unchecked', (tester) async {
      final fpA = privateKeyFingerprint('pem-A');
      await open(
        tester,
        source(
          keys: [scannedKey('id_a', 'pem-A'), scannedKey('id_b', 'pem-B')],
          existingKeyFingerprints: {fpA},
        ),
      );
      expect(rowValue(tester, 'id_a'), isFalse);
      expect(rowValue(tester, 'id_b'), isTrue);
      expect(find.text('already in store'), findsOneWidget);
    });

    testWidgets('select-all flips every key', (tester) async {
      await open(
        tester,
        source(
          keys: [scannedKey('id_a', 'pem-A'), scannedKey('id_b', 'pem-B')],
        ),
      );
      expect(selectAllRow(tester).value, isTrue);
      await tester.tap(find.byWidget(selectAllRow(tester)));
      await tester.pumpAndSettle();
      expect(rowValue(tester, 'id_a'), isFalse);
      expect(rowValue(tester, 'id_b'), isFalse);
    });
  });

  group('import button gating', () {
    bool importEnabled(WidgetTester tester) {
      return tester
          .widget<AppButton>(
            find.byWidgetPredicate(
              (w) => w is AppButton && w.label == 'Import Data',
            ),
          )
          .enabled;
    }

    testWidgets('disabled when nothing is selected, enabled after a pick', (
      tester,
    ) async {
      await open(
        tester,
        source(
          hosts: [host('h1', 'web-1')],
          existingSessionAddresses: {'root@h.example:22'},
        ),
      );
      // The only host is already imported → default unchecked → nothing
      // selected → Import is disabled.
      expect(rowValue(tester, 'web-1'), isFalse);
      expect(importEnabled(tester), isFalse);

      await tester.tap(find.text('web-1'));
      await tester.pumpAndSettle();
      expect(rowValue(tester, 'web-1'), isTrue);
      expect(importEnabled(tester), isTrue);
    });
  });

  group('submit', () {
    testWidgets('returns the selected sessions and the import folder', (
      tester,
    ) async {
      final result = await open(
        tester,
        source(
          hosts: [
            host('h1', 'web-1', hostname: 'a'),
            host('h2', 'web-2'),
          ],
        ),
      );
      // Drop web-2, keep web-1.
      await tester.tap(find.text('web-2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      final r = result()!;
      expect(r.sessions.map((s) => s.id), ['h1']);
      expect(r.mode, ImportMode.merge);
      expect(r.emptyFolders, {'Imported'});
    });

    testWidgets('a selected real key is parsed into managerKeys', (
      tester,
    ) async {
      final result = await open(
        tester,
        source(keys: [scannedKey('id_real', realPem)]),
      );
      expect(rowValue(tester, 'id_real'), isTrue);
      await tester.tap(find.text('Import Data'));
      await settleUntil(tester, () => result() != null);

      final r = result()!;
      expect(r.managerKeys, hasLength(1));
      expect(r.sessions, isEmpty);
      // No sessions selected → no import folder is materialised.
      expect(r.emptyFolders, isEmpty);
    });
  });

  group('browse callbacks', () {
    testWidgets('no Browse button when the callbacks are null', (tester) async {
      await open(tester, source(hosts: [host('h1', 'web-1')]));
      expect(find.text('Browse files…'), findsNothing);
    });

    testWidgets('browsing a config merges new hosts into the list', (
      tester,
    ) async {
      await open(
        tester,
        source(hosts: [host('h1', 'web-1')]),
        onPickConfigFile: () async => PickedConfigResult(
          sessions: [
            Session(
              id: 'h2',
              label: 'web-2',
              server: const ServerAddress(host: 'b.example', user: 'root'),
            ),
          ],
        ),
      );
      expect(find.text('web-2'), findsNothing);
      await tester.tap(find.text('Browse files…'));
      await tester.pumpAndSettle();
      expect(find.text('web-2'), findsOneWidget);
      expect(rowValue(tester, 'web-2'), isTrue); // newly picked → checked
    });

    testWidgets('browsing keys appends a new key, deduped by fingerprint', (
      tester,
    ) async {
      await open(
        tester,
        source(keys: [scannedKey('id_a', 'pem-A')]),
        onPickKeyFiles: () async => [
          scannedKey('id_a', 'pem-A'), // duplicate fingerprint → skipped
          scannedKey('id_c', 'pem-C'), // new → appended
        ],
      );
      await tester.tap(find.text('Browse files…'));
      await tester.pumpAndSettle();
      expect(find.text('id_c'), findsOneWidget);
      expect(rowValue(tester, 'id_c'), isTrue);
    });
  });
}
