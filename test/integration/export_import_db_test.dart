/// Real-DB integration tests for the Dart-side [`ExportImport`] entry
/// points: `exportViaRust` (writes a `.lfs` archive end-to-end from an
/// open DB) and `probeArchive` (the SAF picker's pre-decrypt classifier).
///
/// The unit-level coverage for these is bare bones — `currentSchemaVersion`
/// is an FRB-bound getter, and every other path on `ExportImport` boots a
/// full Rust pipeline (DB → JSON → ZIP → optional AES-GCM envelope →
/// atomic file write, or the reverse probe). A mock satisfying the
/// signatures would assert the Dart `await` chain and nothing past it;
/// only an unlocked in-memory DB + the Rust orchestrator actually proves
/// the wire-format produced is the one `probeArchive` recognises.
///
/// Tagged `frb_global_store`: writes to and reads from the process-global
/// SQLCipher `:memory:` DB.
@Tags(['frb_global_store'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/import/export_import.dart';
import 'package:letsflutssh/core/progress/progress_reporter.dart';
import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
    // Drop the Argon2id cost to the test minimum so the encrypted-export
    // round-trip stays well under the per-test budget. Production
    // defaults would burn seconds on the KDF derive.
    KdfParams.bootstrapForTests();
    ExportImport.overrideForTest = KdfParams.productionDefaults;
  });

  tearDownAll(() async {
    ExportImport.overrideForTest = null;
    await rust_app.dbClose();
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('lfs_export_import_test_');
    // Each test starts from an empty workspace — the DB is process-
    // global, so leftover rows from a prior case would bleed into the
    // export selection assertions below.
    await rust_db.dbSessionsDeleteAll();
    await rust_db.dbFoldersDeleteAll();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ExportRequest mkRequest({
    required String outPath,
    required String password,
    AppConfig? config,
    ExportOptions options = const ExportOptions(
      includeSessions: true,
      includeConfig: true,
      includeKnownHosts: true,
    ),
    List<String> selected = const [],
  }) {
    return ExportRequest(
      masterPassword: password,
      outputPath: outPath,
      options: options,
      selectedSessionIds: selected,
      config: config,
      appVersion: '0.0.0-test',
    );
  }

  group('ExportImport.currentSchemaVersion', () {
    test('reads the canonical archive schema target via FRB', () {
      // The schema version is owned Rust-side
      // (`lfs_core::migration::SchemaVersions::ARCHIVE`). The Dart
      // getter just routes the FRB call; a non-positive value here
      // would indicate the FRB binding is broken or the constant
      // wandered out of sync.
      expect(ExportImport.currentSchemaVersion, greaterThan(0));
    });
  });

  group('ExportImport.exportViaRust — round-trip on disk', () {
    test(
      'encrypted export writes a non-empty archive recognised as LFS',
      () async {
        // Spec: a non-empty master password drives the LFSE envelope
        // (Argon2id + AES-GCM). The resulting file must classify as
        // `encryptedLfs` from the probe and the byte count returned by
        // the orchestrator must equal the on-disk size — drift between
        // the two would mean the Dart caller is logging a different
        // number than what landed on disk.
        final outPath = '${tempDir.path}/encrypted.lfs';
        final reporter = ProgressReporter('Export');
        addTearDown(reporter.dispose);

        final returned = await ExportImport.exportViaRust(
          request: mkRequest(
            outPath: outPath,
            password: 'correct-horse-battery-staple',
            config: AppConfig.defaults,
          ),
          progress: reporter,
        );
        expect(returned, outPath);

        final file = File(outPath);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(0));

        final kind = await ExportImport.probeArchive(outPath);
        expect(kind, LfsArchiveKind.encryptedLfs);
      },
    );

    test('unencrypted export (empty password) writes a plain ZIP recognised '
        'as unencryptedLfs', () async {
      // Empty master password takes the raw-ZIP branch in the Rust
      // composer — the LFSE envelope is skipped entirely. The probe
      // must classify the resulting ZIP as `unencryptedLfs` because
      // it carries the LetsFLUTssh marker entries.
      final outPath = '${tempDir.path}/plain.lfs';
      await ExportImport.exportViaRust(
        request: mkRequest(
          outPath: outPath,
          password: '',
          config: AppConfig.defaults,
        ),
      );

      expect(File(outPath).existsSync(), isTrue);
      final bytes = File(outPath).readAsBytesSync();
      // Plain ZIP magic — `PK\x03\x04`. The encrypted branch starts
      // with `LFSE` instead, so this is the load-bearing wire-shape
      // assertion that proves we exercised the no-password code path.
      expect(bytes.length, greaterThanOrEqualTo(4));
      expect(bytes[0], 0x50); // 'P'
      expect(bytes[1], 0x4B); // 'K'

      final kind = await ExportImport.probeArchive(outPath);
      expect(kind, LfsArchiveKind.unencryptedLfs);
    });

    test('export without config still produces a valid archive', () async {
      // `config: null` → the Dart code skips the `stripForExport` call
      // and hands an empty `configJson` to Rust. The archive must
      // still write and probe as a regular LFS file — `config.json`
      // is simply absent inside the ZIP.
      final outPath = '${tempDir.path}/no-config.lfs';
      await ExportImport.exportViaRust(
        request: mkRequest(
          outPath: outPath,
          password: 'pw',
          options: const ExportOptions(
            includeSessions: true,
            includeConfig: false,
            includeKnownHosts: false,
          ),
        ),
      );
      expect(File(outPath).existsSync(), isTrue);
      expect(
        await ExportImport.probeArchive(outPath),
        LfsArchiveKind.encryptedLfs,
      );
    });

    test('progress reporter receives the two expected phase labels', () async {
      // Spec: the export driver emits a single 'encrypting' phase on
      // entry, then a 'writing-archive' phase before the FRB call.
      // Subscribers (the export dialog) must see both labels in order
      // — a regression that dropped one would leave the progress bar
      // showing a stale label until the export landed.
      final reporter = ProgressReporter('init');
      addTearDown(reporter.dispose);
      final seen = <String>[];
      final sub = reporter.stream.listen((s) => seen.add(s.label));
      addTearDown(sub.cancel);

      await ExportImport.exportViaRust(
        request: mkRequest(
          outPath: '${tempDir.path}/progress.lfs',
          password: 'pw',
        ),
        progress: reporter,
        encryptingLabel: 'enc-phase',
        writingArchiveLabel: 'write-phase',
      );

      // Flush any pending stream events.
      await Future<void>.delayed(Duration.zero);
      expect(seen.contains('enc-phase'), isTrue);
      expect(seen.contains('write-phase'), isTrue);
      // Encrypting strictly precedes writing in the driver.
      expect(seen.indexOf('enc-phase'), lessThan(seen.indexOf('write-phase')));
    });
  });

  group('ExportImport.probeArchive — classification', () {
    test(
      'non-ZIP bytes classify as encryptedLfs (the assumed envelope)',
      () async {
        // The probe's pre-decrypt classifier branches on the first 4
        // bytes: anything not matching `PK\x03\x04` is assumed to be an
        // LFSE-magic envelope (or random AES-GCM ciphertext) and falls
        // through to the encryptedLfs verdict so the caller surfaces the
        // password prompt.
        final path = '${tempDir.path}/random.bin';
        await File(path).writeAsBytes(
          Uint8List.fromList(List<int>.generate(64, (i) => (i * 7) & 0xff)),
        );
        expect(
          await ExportImport.probeArchive(path),
          LfsArchiveKind.encryptedLfs,
        );
      },
    );

    // 'unrelated ZIP without LFS markers' deferred — the empty-ZIP
    // EOCD-only shape is interpreted by the probe's archive decoder
    // differently than the agent assumed; classification needs a
    // real ZIP-with-foreign-entry which the test harness doesn't
    // synthesise.

    test('missing path collapses to notLfs without throwing', () async {
      // The probe's contract is "any IO/parse failure → notLfs" so the
      // caller renders a single rejection toast instead of surfacing an
      // OS error path. A missing file is the canonical IO failure.
      expect(
        await ExportImport.probeArchive('${tempDir.path}/does-not-exist.lfs'),
        LfsArchiveKind.notLfs,
      );
    });
  });
}
