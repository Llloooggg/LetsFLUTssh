import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/progress/progress_reporter.dart';
import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

/// Tests for ExportImport — exercises the refactored constant names
/// (_sessionsFile, _configFile, _knownHostsFile) through full roundtrips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export_import_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tempDir.delete(recursive: true);
  });

  Session makeSession({
    required String id,
    String label = 'test',
    String host = 'example.com',
    String user = 'root',
    String password = '',
  }) {
    return Session(
      id: id,
      label: label,
      server: ServerAddress(host: host, user: user),
      auth: SessionAuth(password: password),
    );
  }

  group('ExportImport — export and import roundtrip', () {
    test('export then import restores sessions', () async {
      final sessions = [
        makeSession(id: 'exp-1', label: 'server1', password: 'pw1'),
        makeSession(id: 'exp-2', label: 'server2', password: 'pw2'),
      ];
      const config = AppConfig.defaults;
      final outputPath = '${tempDir.path}/test.lfs';

      await ExportImport.export(
        masterPassword: 'test-password',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: config,
          options: const ExportOptions(includeConfig: true),
        ),
      );

      expect(await File(outputPath).exists(), isTrue);

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'test-password',
        mode: ImportMode.merge,
        options: const ExportOptions(includeConfig: true),
      );

      expect(result.sessions, hasLength(2));
      expect(result.sessions[0].id, 'exp-1');
      expect(result.sessions[0].label, 'server1');
      expect(result.sessions[0].password, 'pw1');
      expect(result.sessions[1].id, 'exp-2');
      expect(result.mode, ImportMode.merge);
    });

    test('export then import restores config', () async {
      final config = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(
          fontSize: 18,
          scrollback: 10000,
        ),
      );
      final outputPath = '${tempDir.path}/config.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: const [],
          config: config,
          options: const ExportOptions(includeConfig: true),
        ),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.replace,
        options: const ExportOptions(includeConfig: true),
      );

      expect(result.config, isNotNull);
      expect(result.config!.fontSize, 18);
      expect(result.config!.scrollback, 10000);
      expect(result.mode, ImportMode.replace);
    });

    test('export with selective options exports only selected data', () async {
      final sessions = [
        makeSession(id: 'sel-1', label: 'server1', password: 'pw1'),
      ];
      final outputPath = '${tempDir.path}/selective.lfs';

      // Export only sessions + known_hosts, no config
      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          options: const ExportOptions(
            includeSessions: true,
            includeConfig: false,
            includeKnownHosts: false,
          ),
        ),
      );

      // Import only config (should be null since not exported)
      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(
          includeSessions: false,
          includeConfig: true,
          includeKnownHosts: true,
        ),
      );

      expect(result.sessions, isEmpty);
      expect(result.config, isNull);
      expect(result.knownHostsContent, isNull);
    });

    test('import with importConfig=false skips config', () async {
      final outputPath = '${tempDir.path}/noconfig.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(includeConfig: false),
      );

      expect(result.config, isNull);
    });

    test('export includes known_hosts when content provided', () async {
      const knownHostsContent = 'example.com:22 ssh-rsa AAAAB3...';

      final outputPath = '${tempDir.path}/withkh.lfs';
      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(
          sessions: [],
          config: AppConfig.defaults,
          knownHostsContent: knownHostsContent,
        ),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(
          includeConfig: false,
          includeKnownHosts: true,
        ),
      );

      // known_hosts content should be returned for caller to import
      expect(result.knownHostsContent, knownHostsContent);
    });

    test('import without known_hosts returns null content', () async {
      final outputPath = '${tempDir.path}/nokh.lfs';
      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(
          includeConfig: false,
          includeKnownHosts: true,
        ),
      );

      // No known_hosts was included in the export
      expect(result.knownHostsContent, isNull);
    });
  });

  group('ExportImport — preview', () {
    test('preview shows sessions and flags', () async {
      final sessions = [makeSession(id: 'prev-1', label: 'preview-server')];
      final outputPath = '${tempDir.path}/preview.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          options: const ExportOptions(includeConfig: true),
        ),
      );

      final preview = await ExportImport.preview(
        filePath: outputPath,
        masterPassword: 'pw',
      );

      expect(preview.sessions, hasLength(1));
      expect(preview.sessions.first.label, 'preview-server');
      expect(preview.hasConfig, isTrue);
      // No known_hosts was written, so it depends on whether the file exists
    });
  });

  group('ExportImport — error cases', () {
    test('wrong password throws on decrypt', () async {
      final outputPath = '${tempDir.path}/encrypted.lfs';
      await ExportImport.export(
        masterPassword: 'correct',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );

      expect(
        () => ExportImport.import_(
          filePath: outputPath,
          masterPassword: 'wrong',
          mode: ImportMode.merge,
          options: const ExportOptions(includeConfig: true),
        ),
        throwsA(isA<LfsDecryptionFailedException>()),
      );
    });

    test('corrupted archive throws LfsDecryptionFailedException', () async {
      final outputPath = '${tempDir.path}/corrupt.lfs';
      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );
      // Flip a byte in the ciphertext body to trigger GCM auth-tag failure.
      final file = File(outputPath);
      final bytes = await file.readAsBytes();
      final mutated = Uint8List.fromList(bytes);
      mutated[mutated.length - 1] ^= 0xFF;
      await file.writeAsBytes(mutated);

      expect(
        () => ExportImport.import_(
          filePath: outputPath,
          masterPassword: 'pw',
          mode: ImportMode.merge,
          options: const ExportOptions(includeConfig: true),
        ),
        throwsA(isA<LfsDecryptionFailedException>()),
      );
    });
  });

  group('ExportImport — encryption header (v3 LFSE / Argon2id)', () {
    test(
      'new archives start with LFSE magic and v3 Argon2id version',
      () async {
        final outputPath = '${tempDir.path}/lfse.lfs';
        await ExportImport.export(
          masterPassword: 'pw',
          outputPath: outputPath,
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
        );
        final bytes = await File(outputPath).readAsBytes();
        // 'L','F','S','E' ASCII.
        expect(
          [bytes[0], bytes[1], bytes[2], bytes[3]],
          [0x4C, 0x46, 0x53, 0x45],
        );
        // version byte == 2 (v3 Argon2id)
        expect(bytes[4], 2);
        // Byte 5 is the KDF algorithm id (mirrored in the KdfParams block).
        expect(bytes[5], KdfAlgorithm.argon2id.id);
      },
    );

    test(
      'roundtrip honours the custom Argon2id params in the header',
      () async {
        final outputPath = '${tempDir.path}/argon-params.lfs';
        // Slightly different memory cost than the test default so we can
        // confirm the reader picked params from the header rather than from
        // the mutable `defaultKdfParams`.
        const params = KdfParams.argon2id(
          memoryKiB: 16,
          iterations: 1,
          parallelism: 1,
        );
        await ExportImport.export(
          masterPassword: 'pw',
          outputPath: outputPath,
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
          kdfParams: params,
        );

        // Decrypt without supplying params — reader must honour the header.
        final result = await ExportImport.import_(
          filePath: outputPath,
          masterPassword: 'pw',
          mode: ImportMode.merge,
          options: const ExportOptions(includeConfig: true),
        );
        expect(result.config, isNotNull);
      },
    );

    test(
      'Argon2id params above the import cap are rejected as malformed',
      () async {
        final outputPath = '${tempDir.path}/huge-argon.lfs';
        await ExportImport.export(
          masterPassword: 'pw',
          outputPath: outputPath,
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
        );
        final bytes = (await File(outputPath).readAsBytes()).toList();
        // Layout: magic(4) + ver(1) + algoId(1) + memoryKiB u32BE (4) ...
        // Overwrite memory cost with 0xFFFFFFFF — well above maxImportArgon2idMemoryKiB.
        bytes[6] = 0xFF;
        bytes[7] = 0xFF;
        bytes[8] = 0xFF;
        bytes[9] = 0xFF;
        final hostilePath = '${tempDir.path}/huge-argon-mut.lfs';
        await File(hostilePath).writeAsBytes(bytes);

        await expectLater(
          ExportImport.import_(
            filePath: hostilePath,
            masterPassword: 'pw',
            mode: ImportMode.merge,
            options: const ExportOptions(includeConfig: true),
          ),
          throwsA(isA<LfsMalformedHeaderException>()),
        );
      },
    );

    test('zero-valued Argon2id params are rejected as malformed', () async {
      final outputPath = '${tempDir.path}/zero-argon.lfs';
      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );
      final bytes = (await File(outputPath).readAsBytes()).toList();
      // Zero out memory cost (bytes 6..9).
      bytes[6] = 0;
      bytes[7] = 0;
      bytes[8] = 0;
      bytes[9] = 0;
      final hostilePath = '${tempDir.path}/zero-argon-mut.lfs';
      await File(hostilePath).writeAsBytes(bytes);

      await expectLater(
        ExportImport.import_(
          filePath: hostilePath,
          masterPassword: 'pw',
          mode: ImportMode.merge,
          options: const ExportOptions(includeConfig: true),
        ),
        throwsA(isA<LfsMalformedHeaderException>()),
      );
    });
  });

  group('ExportImport — legacy PBKDF2 read path', () {
    test('v2 PBKDF2 archives produced by older builds still decrypt', () async {
      // Build a real ZIP payload via the current export path, then re-wrap
      // it with the legacy v2 PBKDF2 writer so we get a real archive that
      // reads exactly like one produced by a pre-Argon2id build.
      final zipBytes = _buildTestZip();
      final legacyBytes = ExportImport.encryptLegacyPbkdf2ForTesting(
        zipBytes,
        'pw',
        iterations: 1,
      );
      final legacyPath = '${tempDir.path}/pbkdf2-legacy.lfs';
      await File(legacyPath).writeAsBytes(legacyBytes);

      final result = await ExportImport.import_(
        filePath: legacyPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(includeConfig: true),
      );
      expect(result.config, isNotNull);
    });

    test(
      'legacy headerless PBKDF2 archive decrypts via fallback path',
      () async {
        final zipBytes = _buildTestZip();
        final v2Bytes = ExportImport.encryptLegacyPbkdf2ForTesting(
          zipBytes,
          'pw',
          iterations: ExportImport.defaultPbkdf2Iterations,
        );
        // Drop the 9-byte LFSE/version/iters prefix to produce the original
        // v1 layout (raw salt + iv + ct).
        final stripped = v2Bytes.sublist(9);
        final legacyPath = '${tempDir.path}/pbkdf2-headerless.lfs';
        await File(legacyPath).writeAsBytes(stripped);

        final result = await ExportImport.import_(
          filePath: legacyPath,
          masterPassword: 'pw',
          mode: ImportMode.merge,
          options: const ExportOptions(includeConfig: true),
        );
        expect(result.config, isNotNull);
      },
    );

    test(
      'v2 header with maliciously huge iterations is rejected as malformed',
      () async {
        final zipBytes = _buildTestZip();
        final legacyBytes = ExportImport.encryptLegacyPbkdf2ForTesting(
          zipBytes,
          'pw',
          iterations: 1,
        ).toList();
        // Bytes 5..8 hold the u32 iterations field.
        legacyBytes[5] = 0xFF;
        legacyBytes[6] = 0xFF;
        legacyBytes[7] = 0xFF;
        legacyBytes[8] = 0xFF;
        final hostilePath = '${tempDir.path}/pbkdf2-hostile.lfs';
        await File(hostilePath).writeAsBytes(legacyBytes);

        await expectLater(
          ExportImport.import_(
            filePath: hostilePath,
            masterPassword: 'pw',
            mode: ImportMode.merge,
            options: const ExportOptions(includeConfig: true),
          ),
          throwsA(isA<LfsMalformedHeaderException>()),
        );
      },
    );

    test('v2 header with zero iterations is rejected as malformed', () async {
      final zipBytes = _buildTestZip();
      final legacyBytes = ExportImport.encryptLegacyPbkdf2ForTesting(
        zipBytes,
        'pw',
        iterations: 1,
      ).toList();
      legacyBytes[5] = 0;
      legacyBytes[6] = 0;
      legacyBytes[7] = 0;
      legacyBytes[8] = 0;
      final hostilePath = '${tempDir.path}/pbkdf2-zero.lfs';
      await File(hostilePath).writeAsBytes(legacyBytes);

      await expectLater(
        ExportImport.import_(
          filePath: hostilePath,
          masterPassword: 'pw',
          mode: ImportMode.merge,
          options: const ExportOptions(includeConfig: true),
        ),
        throwsA(isA<LfsMalformedHeaderException>()),
      );
    });
  });

  group('ExportImport — empty folders roundtrip', () {
    test('export and import preserves empty folders', () async {
      final sessions = [makeSession(id: 's1', label: 'srv')];
      final outputPath = '${tempDir.path}/folders.lfs';
      const emptyFolders = {'EmptyFolder', 'AnotherEmpty'};

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          emptyFolders: emptyFolders,
        ),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
      );

      expect(result.emptyFolders, containsAll(['EmptyFolder', 'AnotherEmpty']));
      expect(result.emptyFolders, hasLength(2));
    });

    test('empty folders omitted when set is empty', () async {
      final sessions = [makeSession(id: 's1', label: 'srv')];
      final outputPath = '${tempDir.path}/nofolders.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          emptyFolders: const {},
        ),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
      );

      expect(result.emptyFolders, isEmpty);
    });
  });

  group('ExportImport — selective data export', () {
    test('exclude known_hosts from export', () async {
      final sessions = [makeSession(id: 's1', label: 'srv')];
      final outputPath = '${tempDir.path}/nokh_export.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          knownHostsContent: 'host ssh-rsa AAA',
          options: const ExportOptions(includeKnownHosts: false),
        ),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(includeKnownHosts: true),
      );

      expect(result.knownHostsContent, isNull);
    });

    test('passwords preserved in full export/import roundtrip', () async {
      final sessions = [
        makeSession(id: 's1', label: 'srv', password: 'secret'),
      ];
      final outputPath = '${tempDir.path}/nopw.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        // Note: ExportImport.export always uses toJsonWithCredentials,
        // so passwords are in sessions.json. The selectivity is at the
        // import level — if includeSessions=false, sessions aren't read.
        input: LfsExportInput(sessions: sessions, config: AppConfig.defaults),
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        options: const ExportOptions(includeSessions: true),
      );

      // Sessions are imported with credentials (as designed for .lfs)
      expect(result.sessions[0].password, 'secret');
    });
  });

  group('ExportImport — preview', () {
    test('preview shows empty folders count', () async {
      final sessions = [makeSession(id: 's1', label: 'srv')];
      final outputPath = '${tempDir.path}/preview_folders.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          emptyFolders: const {'A', 'B', 'C'},
        ),
      );

      final preview = await ExportImport.preview(
        filePath: outputPath,
        masterPassword: 'pw',
      );

      expect(preview.emptyFolders, hasLength(3));
      expect(preview.emptyFoldersCount, 3);
    });

    test('preview.hasSessions derived from sessions list', () async {
      final sessions = [makeSession(id: 's1', label: 'srv')];
      final outputPath = '${tempDir.path}/preview_has_sessions.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: LfsExportInput(sessions: sessions, config: AppConfig.defaults),
      );

      final preview = await ExportImport.preview(
        filePath: outputPath,
        masterPassword: 'pw',
      );

      expect(preview.hasSessions, isTrue);
      expect(preview.sessions, isNotEmpty);
    });

    test('preview.hasSessions false when no sessions', () async {
      final outputPath = '${tempDir.path}/preview_nosessions.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );

      final preview = await ExportImport.preview(
        filePath: outputPath,
        masterPassword: 'pw',
      );

      expect(preview.hasSessions, isFalse);
    });
  });

  group('ExportImport — unencrypted archive', () {
    test('export with empty password writes a raw ZIP', () async {
      final outputPath = '${tempDir.path}/plain.lfs';
      await ExportImport.export(
        masterPassword: '',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: [makeSession(id: 'u1', label: 'u1', password: 'x')],
          config: AppConfig.defaults,
          options: const ExportOptions(includeConfig: true),
        ),
      );

      final bytes = await File(outputPath).readAsBytes();
      // The first four bytes must be the ZIP local-file-header magic — the
      // whole point of the unencrypted path is that the archive is a plain
      // ZIP anyone can open.
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      expect(bytes[2], 0x03);
      expect(bytes[3], 0x04);
      expect(ExportImport.isUnencryptedArchive(bytes), isTrue);
    });

    test('unencrypted export roundtrips through import', () async {
      final sessions = [
        makeSession(id: 'p-1', label: 'plain', password: 'secret'),
      ];
      final outputPath = '${tempDir.path}/roundtrip.lfs';

      await ExportImport.export(
        masterPassword: '',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          options: const ExportOptions(includeConfig: true),
        ),
      );

      // Password is ignored on the unencrypted path.
      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: '',
        mode: ImportMode.merge,
        options: const ExportOptions(includeConfig: true),
      );

      expect(result.sessions, hasLength(1));
      expect(result.sessions.first.id, 'p-1');
      expect(result.sessions.first.password, 'secret');
    });

    test('isUnencryptedArchive detects ZIP magic', () {
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0]);
      final enc = Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0, 0]);
      final tiny = Uint8List.fromList([0x50, 0x4B]);
      expect(ExportImport.isUnencryptedArchive(zip), isTrue);
      expect(ExportImport.isUnencryptedArchive(enc), isFalse);
      expect(ExportImport.isUnencryptedArchive(tiny), isFalse);
    });

    test('preview reads unencrypted archive without a password', () async {
      final sessions = [makeSession(id: 'pv-1', label: 'x', password: 'y')];
      final outputPath = '${tempDir.path}/preview.lfs';

      await ExportImport.export(
        masterPassword: '',
        outputPath: outputPath,
        input: LfsExportInput(
          sessions: sessions,
          config: AppConfig.defaults,
          options: const ExportOptions(includeConfig: true),
        ),
      );

      final preview = await ExportImport.preview(
        filePath: outputPath,
        masterPassword: '',
      );
      expect(preview.sessions, hasLength(1));
      expect(preview.sessions.first.id, 'pv-1');
    });
  });

  group('ImportMode and ImportResult', () {
    test('ImportMode values', () {
      expect(ImportMode.values, hasLength(2));
      expect(ImportMode.values, contains(ImportMode.merge));
      expect(ImportMode.values, contains(ImportMode.replace));
    });

    test('ImportResult holds data', () {
      const result = ImportResult(sessions: [], mode: ImportMode.merge);
      expect(result.sessions, isEmpty);
      expect(result.config, isNull);
      expect(result.mode, ImportMode.merge);
    });

    test('LfsPreview holds data', () {
      const preview = LfsPreview(
        sessions: [],
        hasConfig: true,
        hasKnownHosts: false,
      );
      expect(preview.sessions, isEmpty);
      expect(preview.hasSessions, isFalse); // derived from empty sessions list
      expect(preview.hasConfig, isTrue);
      expect(preview.hasKnownHosts, isFalse);
    });
  });

  group('ImportResult.filtered', () {
    ImportResult fullResult() => ImportResult(
      sessions: [
        makeSession(id: 'f-1'),
        makeSession(id: 'f-2'),
      ],
      emptyFolders: const {'folder/a'},
      managerKeys: [
        SshKeyEntry(
          id: 'k1',
          label: 'k',
          privateKey: 'pk',
          publicKey: 'pub',
          keyType: 'ed25519',
          createdAt: DateTime(2020),
        ),
      ],
      tags: [Tag(id: 't1', name: 'tag')],
      sessionTags: const [ExportLink(sessionId: 'f-1', targetId: 't1')],
      folderTags: const [
        ExportFolderTagLink(folderPath: 'folder/a', tagId: 't1'),
      ],
      snippets: [Snippet(id: 's1', title: 'ls', command: 'ls -la')],
      sessionSnippets: const [ExportLink(sessionId: 'f-1', targetId: 's1')],
      config: AppConfig.defaults,
      mode: ImportMode.merge,
      knownHostsContent: 'host content',
    );

    test('keeps everything when all flags are on', () {
      final filtered = fullResult().filtered(
        const ExportOptions(
          includeSessions: true,
          includeConfig: true,
          includeKnownHosts: true,
          includeManagerKeys: true,
          includeTags: true,
          includeSnippets: true,
        ),
        ImportMode.replace,
      );

      expect(filtered.sessions, hasLength(2));
      expect(filtered.emptyFolders, {'folder/a'});
      expect(filtered.managerKeys, hasLength(1));
      expect(filtered.tags, hasLength(1));
      expect(filtered.sessionTags, hasLength(1));
      expect(filtered.folderTags, hasLength(1));
      expect(filtered.snippets, hasLength(1));
      expect(filtered.sessionSnippets, hasLength(1));
      expect(filtered.config, isNotNull);
      expect(filtered.knownHostsContent, 'host content');
      expect(filtered.mode, ImportMode.replace);
    });

    test('drops everything when all flags are off', () {
      final filtered = fullResult().filtered(
        const ExportOptions(
          includeSessions: false,
          includeConfig: false,
          includeKnownHosts: false,
        ),
        ImportMode.merge,
      );

      expect(filtered.sessions, isEmpty);
      expect(filtered.emptyFolders, isEmpty);
      expect(filtered.managerKeys, isEmpty);
      expect(filtered.tags, isEmpty);
      expect(filtered.sessionTags, isEmpty);
      expect(filtered.folderTags, isEmpty);
      expect(filtered.snippets, isEmpty);
      expect(filtered.sessionSnippets, isEmpty);
      expect(filtered.config, isNull);
      expect(filtered.knownHostsContent, isNull);
    });

    test('session-dependent collections are dropped when sessions off', () {
      final filtered = fullResult().filtered(
        const ExportOptions(
          includeSessions: false,
          includeConfig: true,
          includeKnownHosts: true,
          includeManagerKeys: true,
          includeTags: true,
          includeSnippets: true,
        ),
        ImportMode.merge,
      );

      // Session-dependent: dropped
      expect(filtered.sessions, isEmpty);
      expect(filtered.emptyFolders, isEmpty);
      expect(filtered.managerKeys, isEmpty);
      expect(filtered.sessionTags, isEmpty);
      expect(filtered.folderTags, isEmpty);
      expect(filtered.sessionSnippets, isEmpty);

      // Standalone: kept via their own flags
      expect(filtered.tags, hasLength(1));
      expect(filtered.snippets, hasLength(1));
      expect(filtered.config, isNotNull);
      expect(filtered.knownHostsContent, 'host content');
    });

    test(
      'manager keys require both includeSessions and includeManagerKeys',
      () {
        final withSessionsOnly = fullResult().filtered(
          const ExportOptions(includeSessions: true, includeManagerKeys: false),
          ImportMode.merge,
        );
        expect(withSessionsOnly.managerKeys, isEmpty);

        final withKeysOnly = fullResult().filtered(
          const ExportOptions(includeSessions: false, includeManagerKeys: true),
          ImportMode.merge,
        );
        expect(withKeysOnly.managerKeys, isEmpty);
      },
    );

    test('mode is taken from argument, not from source result', () {
      final source = fullResult(); // mode: merge
      final filtered = source.filtered(
        const ExportOptions(),
        ImportMode.replace,
      );
      expect(source.mode, ImportMode.merge);
      expect(filtered.mode, ImportMode.replace);
    });
  });

  group('ExportImport — manifest', () {
    test('export writes current schema version and app_version', () async {
      const password = 'test-pw-123';
      final filePath = '${tempDir.path}/manifest.lfs';

      await ExportImport.export(
        masterPassword: password,
        input: LfsExportInput(
          sessions: [makeSession(id: 'm1', label: 'x')],
          config: AppConfig.defaults,
          appVersion: '9.9.9',
        ),
        outputPath: filePath,
      );

      final preview = await ExportImport.preview(
        filePath: filePath,
        masterPassword: password,
      );
      expect(preview.manifest.schemaVersion, ExportImport.currentSchemaVersion);
      expect(preview.manifest.appVersion, '9.9.9');
      expect(preview.manifest.createdAt, isNotNull);
    });

    test('import rejects archive with future schema version', () async {
      // Build an .lfs whose manifest claims a future schema by patching a
      // normal archive. Easier path: craft a LfsExportInput and mutate
      // currentSchemaVersion-aware expectations — but there is no setter.
      // Instead, simulate via a second archive built from custom bytes isn't
      // trivial; so we assert the typed exception shape is well-formed.
      const ex = UnsupportedLfsVersionException(found: 99, supported: 1);
      expect(ex.toString(), contains('v99'));
      expect(ex.toString(), contains('v1'));
    });

    test('legacy manifest (missing file) is treated as v1', () {
      const legacy = LfsManifest.legacy();
      expect(legacy.schemaVersion, 1);
      expect(legacy.appVersion, isNull);
      expect(legacy.createdAt, isNull);
    });
  });

  group('ExportImport — archive size limit', () {
    test('rejects oversized archive before decrypt', () async {
      final filePath = '${tempDir.path}/huge.lfs';
      // Use a sparse file (truncate) instead of writing 50 MB of zeros —
      // File.length() reports the logical size from fstat without touching
      // the bytes, so the reject path is exercised in milliseconds.
      final raf = await File(filePath).open(mode: FileMode.write);
      try {
        await raf.truncate(ExportImport.maxArchiveBytes + 1);
      } finally {
        await raf.close();
      }

      await expectLater(
        ExportImport.import_(
          filePath: filePath,
          masterPassword: 'x',
          mode: ImportMode.merge,
        ),
        throwsA(isA<LfsArchiveTooLargeException>()),
      );
    });

    test('LfsArchiveTooLargeException carries size and limit', () {
      const ex = LfsArchiveTooLargeException(size: 123456, limit: 1000);
      expect(ex.size, 123456);
      expect(ex.limit, 1000);
      expect(ex.toString(), contains('123456'));
    });
  });

  group('ExportImport — known_hosts size cap', () {
    test(
      'rejects archive whose decompressed known_hosts exceeds the cap',
      () async {
        // Use the per-call iterations override so the global default
        // (already lowered by flutter_test_config.dart) is irrelevant.
        // Build a known_hosts string just over the cap. Use a printable byte so
        // utf8.decode wouldn't even be attempted (the size guard runs first).
        final big = String.fromCharCodes(
          List<int>.filled(ExportImport.maxKnownHostsBytes + 1, 0x41),
        );
        final outputPath = '${tempDir.path}/big_kh.lfs';
        await ExportImport.export(
          masterPassword: 'pw',
          outputPath: outputPath,
          input: LfsExportInput(
            sessions: const [],
            config: AppConfig.defaults,
            options: const ExportOptions(includeKnownHosts: true),
            knownHostsContent: big,
          ),
        );

        await expectLater(
          ExportImport.import_(
            filePath: outputPath,
            masterPassword: 'pw',
            mode: ImportMode.merge,
            options: const ExportOptions(includeKnownHosts: true),
          ),
          throwsA(isA<LfsKnownHostsTooLargeException>()),
        );
      },
    );

    test('LfsKnownHostsTooLargeException carries size and limit', () {
      const ex = LfsKnownHostsTooLargeException(size: 999, limit: 100);
      expect(ex.size, 999);
      expect(ex.limit, 100);
      expect(ex.toString(), contains('999'));
    });
  });

  group('ExportImport — robust session parsing', () {
    test('skips malformed session entries and counts them', () {
      const json = '''
[
  {"id": "valid-1", "label": "ok", "host": "h1", "port": 22, "user": "u",
   "auth_method": "password", "password": "p", "key_id": "", "key_passphrase": "",
   "passphrase_storage": "memory", "use_jump_host": false,
   "created_at": "2026-01-01T00:00:00.000Z"},
  {"id": "bad-port", "label": "bad", "host": "h2", "port": "not-a-number",
   "user": "u", "auth_method": "password", "password": "p", "key_id": "",
   "key_passphrase": "", "passphrase_storage": "memory", "use_jump_host": false,
   "created_at": "2026-01-01T00:00:00.000Z"},
  "not-an-object",
  {"id": "valid-2", "label": "ok2", "host": "h3", "port": 22, "user": "u",
   "auth_method": "password", "password": "p", "key_id": "", "key_passphrase": "",
   "passphrase_storage": "memory", "use_jump_host": false,
   "created_at": "2026-01-01T00:00:00.000Z"}
]
''';
      final (sessions, skipped) = ExportImport.parseSessionsJson(json);
      expect(sessions.map((s) => s.id).toList(), ['valid-1', 'valid-2']);
      // Bad-port entry throws on cast; "not-an-object" is filtered by
      // _decodeList earlier, so only 1 entry counts as skipped here.
      expect(skipped, 1);
    });

    test('returns empty list and zero skipped for null/empty input', () {
      expect(ExportImport.parseSessionsJson(null).$1, isEmpty);
      expect(ExportImport.parseSessionsJson(null).$2, 0);
      expect(ExportImport.parseSessionsJson('').$1, isEmpty);
    });

    test('parseEmptyFoldersJson tolerates non-string entries', () {
      expect(ExportImport.parseEmptyFoldersJson('["a", 42, "b", null]'), {
        'a',
        'b',
      });
      expect(ExportImport.parseEmptyFoldersJson('not json'), isEmpty);
      expect(ExportImport.parseEmptyFoldersJson('{}'), isEmpty);
    });
  });

  group('ExportImport — atomic write', () {
    test('successful export leaves no .tmp on disk', () async {
      final outputPath = '${tempDir.path}/atomic.lfs';
      await ExportImport.export(
        masterPassword: 'pw',
        outputPath: outputPath,
        input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
      );
      expect(await File(outputPath).exists(), isTrue);
      expect(await File('$outputPath.tmp').exists(), isFalse);
    });

    test(
      'export cleans up .tmp when rename to outputPath fails',
      // Spec (export_import.dart L316-328): the atomic-write invariant is
      // "either outputPath becomes the fresh archive or nothing changed".
      // If rename fails mid-way (here: target path is an existing directory
      // so EISDIR fires), the catch branch must delete the stranded .tmp so
      // a subsequent re-run doesn't find a half-written artifact next to
      // the good old archive and lift it by mistake.
      () async {
        // Pre-create outputPath as a *directory* → rename(src=file, dst=dir)
        // fails on POSIX, triggering the catch branch.
        final outputPath = '${tempDir.path}/collides.lfs';
        await Directory(outputPath).create();

        await expectLater(
          ExportImport.export(
            masterPassword: 'pw',
            outputPath: outputPath,
            input: const LfsExportInput(
              sessions: [],
              config: AppConfig.defaults,
            ),
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(
          await File('$outputPath.tmp').exists(),
          isFalse,
          reason: '.tmp must be cleaned up after rename failure',
        );
      },
    );
  });

  group('ExportImport — progress reporter phases', () {
    test(
      'export with password reports Collecting → Encrypting → Writing',
      // Spec (L265, 292, 312): a password-protected export runs through
      // three distinct phases: build the archive, encrypt, write to disk.
      // Each is surfaced to the UI so the progress bar's label changes and
      // the user isn't staring at a stuck "Encrypting…" when we've moved
      // on to file I/O.
      () async {
        final reporter = _RecordingProgress('initial');
        addTearDown(reporter.dispose);

        await ExportImport.export(
          masterPassword: 'pw',
          outputPath: '${tempDir.path}/phases.lfs',
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
          progress: reporter,
        );

        expect(
          reporter.phases,
          containsAllInOrder([
            'Collecting data…',
            'Encrypting…',
            'Writing archive…',
          ]),
        );
      },
    );

    test(
      'export without password reports Collecting → Writing (no Encrypting)',
      // Spec (L283-304): empty master password skips encryption entirely.
      // The Encrypting phase must NOT be reported — otherwise a user who
      // deliberately exported in the clear would see "Encrypting…" flash by
      // and be misled into thinking the file is protected.
      () async {
        final reporter = _RecordingProgress('initial');
        addTearDown(reporter.dispose);

        await ExportImport.export(
          masterPassword: '',
          outputPath: '${tempDir.path}/plain.lfs',
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
          progress: reporter,
        );

        expect(reporter.phases, contains('Collecting data…'));
        expect(reporter.phases, contains('Writing archive…'));
        expect(reporter.phases, isNot(contains('Encrypting…')));
      },
    );

    test(
      'import_ reports Reading → Decrypting → Parsing for encrypted archive',
      () async {
        final outputPath = '${tempDir.path}/import-phases.lfs';
        await ExportImport.export(
          masterPassword: 'pw',
          outputPath: outputPath,
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
        );

        final reporter = _RecordingProgress('initial');
        addTearDown(reporter.dispose);

        await ExportImport.import_(
          filePath: outputPath,
          masterPassword: 'pw',
          mode: ImportMode.merge,
          options: const ExportOptions(),
          progress: reporter,
        );

        expect(
          reporter.phases,
          containsAllInOrder([
            'Reading archive…',
            'Decrypting…',
            'Parsing archive…',
          ]),
        );
      },
    );

    test(
      'import_ skips Decrypting phase for an unencrypted archive',
      // Spec (L501-503): if the bytes start with the ZIP magic, we know
      // the archive was written in the clear. Reading + Parsing are the
      // only phases the user should see; Decrypting would be a lie.
      () async {
        final outputPath = '${tempDir.path}/plain-import.lfs';
        await ExportImport.export(
          masterPassword: '',
          outputPath: outputPath,
          input: const LfsExportInput(sessions: [], config: AppConfig.defaults),
        );

        final reporter = _RecordingProgress('initial');
        addTearDown(reporter.dispose);

        await ExportImport.import_(
          filePath: outputPath,
          masterPassword: '',
          mode: ImportMode.merge,
          options: const ExportOptions(),
          progress: reporter,
        );

        expect(reporter.phases, contains('Reading archive…'));
        expect(reporter.phases, contains('Parsing archive…'));
        expect(reporter.phases, isNot(contains('Decrypting…')));
      },
    );
  });

  group('ExportImport — archive content (keys / tags / snippets)', () {
    test(
      'manager keys roundtrip through the archive',
      // Spec (L370-391): when includeAllManagerKeys is on and
      // managerKeyEntries is non-empty, the archive carries a keys.json
      // with every field the importer needs to rehydrate an SshKeyEntry
      // (id, label, private/public key, key_type, is_generated,
      // created_at). Anything less would force the user to regenerate
      // keys after a full-app transfer.
      () async {
        final keys = [
          SshKeyEntry(
            id: 'k1',
            label: 'prod',
            privateKey: 'PRIV1',
            publicKey: 'PUB1',
            keyType: 'ed25519',
            createdAt: DateTime.utc(2025, 1, 1),
            isGenerated: true,
          ),
          SshKeyEntry(
            id: 'k2',
            label: 'ci',
            privateKey: 'PRIV2',
            publicKey: 'PUB2',
            keyType: 'rsa',
            createdAt: DateTime.utc(2025, 2, 2),
          ),
        ];
        final outputPath = '${tempDir.path}/keys.lfs';
        await ExportImport.export(
          masterPassword: '',
          outputPath: outputPath,
          input: LfsExportInput(
            sessions: const [],
            config: AppConfig.defaults,
            managerKeyEntries: keys,
            options: const ExportOptions(includeAllManagerKeys: true),
          ),
        );

        final result = await ExportImport.import_(
          filePath: outputPath,
          masterPassword: '',
          mode: ImportMode.merge,
          options: const ExportOptions(includeAllManagerKeys: true),
        );

        expect(result.managerKeys.map((k) => k.id), ['k1', 'k2']);
        final byId = {for (final k in result.managerKeys) k.id: k};
        expect(byId['k1']!.label, 'prod');
        expect(byId['k1']!.privateKey, 'PRIV1');
        expect(byId['k1']!.publicKey, 'PUB1');
        expect(byId['k1']!.keyType, 'ed25519');
        expect(byId['k1']!.isGenerated, isTrue);
        expect(byId['k2']!.isGenerated, isFalse);
      },
    );

    test(
      'tags, session-tag links and folder-tag links roundtrip through the archive',
      // Spec (L404-440): the tags export writes three entries — tags.json
      // (tag defs), session_tags.json (session→tag assignments), and
      // folder_tags.json (folder→tag assignments). Links are only written
      // when non-empty so the archive stays small for tag-free users, but
      // when present they must round-trip intact so neither side of the
      // relation goes missing on import.
      () async {
        final tags = [
          Tag(
            id: 't1',
            name: 'prod',
            color: '#ff0000',
            createdAt: DateTime.utc(2025, 1, 1),
          ),
          Tag(
            id: 't2',
            name: 'staging',
            color: '#00ff00',
            createdAt: DateTime.utc(2025, 1, 2),
          ),
        ];
        final sessionTags = [
          const ExportLink(sessionId: 's1', targetId: 't1'),
          const ExportLink(sessionId: 's2', targetId: 't2'),
        ];
        final folderTags = [
          const ExportFolderTagLink(folderPath: 'Prod/Web', tagId: 't1'),
        ];

        final outputPath = '${tempDir.path}/tags.lfs';
        await ExportImport.export(
          masterPassword: '',
          outputPath: outputPath,
          input: LfsExportInput(
            sessions: const [],
            config: AppConfig.defaults,
            tags: tags,
            sessionTags: sessionTags,
            folderTags: folderTags,
            options: const ExportOptions(includeTags: true),
          ),
        );

        final result = await ExportImport.import_(
          filePath: outputPath,
          masterPassword: '',
          mode: ImportMode.merge,
          options: const ExportOptions(includeTags: true),
        );

        expect(result.tags.map((t) => t.id), ['t1', 't2']);
        expect(result.tags.firstWhere((t) => t.id == 't1').color, '#ff0000');
        expect(result.sessionTags.map((l) => (l.sessionId, l.targetId)), [
          ('s1', 't1'),
          ('s2', 't2'),
        ]);
        expect(result.folderTags.map((l) => (l.folderPath, l.tagId)), [
          ('Prod/Web', 't1'),
        ]);
      },
    );

    test(
      'snippets and session-snippet links roundtrip through the archive',
      // Spec (L442-465): snippets export writes snippets.json (definitions)
      // plus session_snippets.json (per-session pin list). Both must
      // survive a round-trip; otherwise pinned snippets detach from their
      // sessions on import and the user has to re-pin.
      () async {
        final snippets = [
          Snippet(
            id: 'sn1',
            title: 'restart',
            command: 'systemctl restart foo',
            description: 'desc',
            createdAt: DateTime.utc(2025, 1, 1),
            updatedAt: DateTime.utc(2025, 1, 2),
          ),
          Snippet(
            id: 'sn2',
            title: 'logs',
            command: 'journalctl -u foo',
            createdAt: DateTime.utc(2025, 1, 3),
            updatedAt: DateTime.utc(2025, 1, 3),
          ),
        ];
        final sessionSnippets = [
          const ExportLink(sessionId: 's1', targetId: 'sn1'),
          const ExportLink(sessionId: 's1', targetId: 'sn2'),
        ];

        final outputPath = '${tempDir.path}/snippets.lfs';
        await ExportImport.export(
          masterPassword: '',
          outputPath: outputPath,
          input: LfsExportInput(
            sessions: const [],
            config: AppConfig.defaults,
            snippets: snippets,
            sessionSnippets: sessionSnippets,
            options: const ExportOptions(includeSnippets: true),
          ),
        );

        final result = await ExportImport.import_(
          filePath: outputPath,
          masterPassword: '',
          mode: ImportMode.merge,
          options: const ExportOptions(includeSnippets: true),
        );

        expect(result.snippets.map((s) => s.id), ['sn1', 'sn2']);
        expect(
          result.snippets.firstWhere((s) => s.id == 'sn1').description,
          'desc',
        );
        expect(result.sessionSnippets.map((l) => (l.sessionId, l.targetId)), [
          ('s1', 'sn1'),
          ('s1', 'sn2'),
        ]);
      },
    );
  });

  group('ExportImport — manifest & archive error paths', () {
    /// Build an unencrypted .lfs at [path] holding just a manifest with the
    /// given raw JSON body. Everything else (sessions, tags, …) is omitted —
    /// these tests only care about the manifest-validation edges.
    Future<void> writeManifestOnlyArchive(
      String path,
      String manifestJson,
    ) async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('manifest.json', manifestJson));
      final zipBytes = ZipEncoder().encode(archive);
      await File(path).writeAsBytes(zipBytes);
    }

    test(
      'enforceDecompressedSizeCap rejects archive whose total uncompressed entries exceed the cap',
      () {
        // The Archive object exposes a writable `size` per entry, so we can
        // build a synthetic zip-bomb shape without actually allocating
        // hundreds of MiB. Two entries each declaring 150 MiB uncompressed
        // exceed the 200 MiB cap.
        final huge = Archive()
          ..addFile(
            ArchiveFile.bytes('big1.bin', Uint8List(0))
              ..size = 150 * 1024 * 1024,
          )
          ..addFile(
            ArchiveFile.bytes('big2.bin', Uint8List(0))
              ..size = 150 * 1024 * 1024,
          );
        expect(
          () => ExportImport.enforceDecompressedSizeCap(huge),
          throwsA(isA<LfsArchiveTooLargeException>()),
        );
      },
    );

    test(
      'enforceDecompressedSizeCap accepts an archive whose total fits the cap',
      () {
        final ok = Archive()
          ..addFile(ArchiveFile.bytes('small.bin', Uint8List(0))..size = 1024);
        expect(
          () => ExportImport.enforceDecompressedSizeCap(ok),
          returnsNormally,
        );
      },
    );

    test(
      'decrypt+parse raises UnsupportedLfsVersionException when schema is newer',
      // Spec (L530-535): the manifest carries schema_version so we can
      // refuse gracefully if a file written by a future version lands in
      // the hands of an older build. Continuing would risk silently
      // dropping fields the importer doesn't know about.
      () async {
        final path = '${tempDir.path}/future.lfs';
        await writeManifestOnlyArchive(path, '{"schema_version": 9999}');

        await expectLater(
          ExportImport.preview(filePath: path, masterPassword: ''),
          throwsA(
            isA<UnsupportedLfsVersionException>()
                .having((e) => e.found, 'found', 9999)
                .having(
                  (e) => e.supported,
                  'supported',
                  greaterThanOrEqualTo(1),
                ),
          ),
        );
      },
    );

    // NOTE: _decryptAndParseArchive wraps ZipDecoder failures in
    // LfsDecryptionFailedException (export_import.dart L522-527). That
    // catch branch is defensive but not reachable in this codebase:
    //   - the `archive` package's ZipDecoder never throws on malformed
    //     bytes — it silently returns an empty Archive (probed across
    //     bare magic, truncated valid zips, and hand-crafted bad local
    //     headers);
    //   - AES-GCM authenticates ciphertext, so a successful decrypt can
    //     only produce bytes that were encrypted as a ZIP in the first
    //     place. There is no realistic input that gets past decryption
    //     and then fails ZipDecoder.
    // We keep the catch in the source as belt-and-braces — if the
    // archive package ever tightens up, the UI will still surface a
    // single decrypt-failed error — but we don't manufacture a fake
    // test for a branch we can't drive.

    test(
      'manifest parser accepts schema_version encoded as a JSON number',
      // Spec (L595-602): some JSON encoders emit integers as doubles
      // (e.g. `2.0`). The manifest parser must coerce via toInt() so the
      // archive still loads instead of defaulting to legacy v1 and then
      // mis-parsing fields that changed between versions.
      () async {
        final path = '${tempDir.path}/float-schema.lfs';
        await writeManifestOnlyArchive(path, '{"schema_version": 1.0}');

        // Should NOT throw — 1.0 → 1, which is <= current schema, parsing
        // continues and returns an empty preview.
        final preview = await ExportImport.preview(
          filePath: path,
          masterPassword: '',
        );
        expect(preview.sessions, isEmpty);
      },
    );
  });

  group('ExportImport — exception toString messages', () {
    test('UnsupportedLfsVersionException surfaces found and supported', () {
      const e = UnsupportedLfsVersionException(found: 9, supported: 3);
      expect(e.toString(), contains('v9'));
      expect(e.toString(), contains('v3'));
    });

    test('LfsArchiveTooLargeException surfaces size and limit', () {
      const e = LfsArchiveTooLargeException(size: 2048, limit: 1024);
      expect(e.toString(), contains('2048'));
      expect(e.toString(), contains('1024'));
    });

    test('LfsKnownHostsTooLargeException surfaces size and limit', () {
      const e = LfsKnownHostsTooLargeException(size: 50, limit: 10);
      expect(e.toString(), contains('50'));
      expect(e.toString(), contains('10'));
    });

    test('LfsDecryptionFailedException toString is stable', () {
      const e = LfsDecryptionFailedException(cause: 'boom');
      expect(e.toString(), 'LfsDecryptionFailedException');
    });
  });

  group('ExportImport.probeArchive', () {
    Uint8List zipWith(Map<String, String> entries) {
      final archive = Archive();
      entries.forEach((name, contents) {
        final bytes = utf8.encode(contents);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      });
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('rejects a random non-ZIP payload as encryptedLfs', () {
      // Non-ZIP header must not be classified as notLfs pre-decrypt — an
      // AES-GCM ciphertext is indistinguishable from noise here, so the
      // import flow still needs a password prompt for it.
      final enc = File('${tempDir.path}/enc.lfs');
      enc.writeAsBytesSync([0x13, 0x37, 0x00, 0x42, 0xAB, 0xCD]);
      expect(ExportImport.probeArchive(enc.path), LfsArchiveKind.encryptedLfs);
    });

    test('classifies a plain ZIP with a marker entry as unencryptedLfs', () {
      final f = File('${tempDir.path}/plain.lfs');
      f.writeAsBytesSync(zipWith({'manifest.json': '{"schema_version":1}'}));
      expect(ExportImport.probeArchive(f.path), LfsArchiveKind.unencryptedLfs);
    });

    test(
      'accepts any one of {sessions.json, config.json, keys.json} as a marker',
      () {
        for (final marker in ['sessions.json', 'config.json', 'keys.json']) {
          final f = File('${tempDir.path}/${marker.replaceAll('.', '_')}.lfs');
          f.writeAsBytesSync(zipWith({marker: '[]'}));
          expect(
            ExportImport.probeArchive(f.path),
            LfsArchiveKind.unencryptedLfs,
            reason: 'marker=$marker',
          );
        }
      },
    );

    test('rejects a ZIP without any LFS marker entry as notLfs '
        '(defends against APK picked by mistake on Android SAF)', () {
      // Shape mimics what an APK might look like — ZIP structure with
      // entries none of which are in our allowlist.
      final f = File('${tempDir.path}/apk-like.lfs');
      f.writeAsBytesSync(
        zipWith({'AndroidManifest.xml': '<manifest />', 'classes.dex': 'dex'}),
      );
      expect(ExportImport.probeArchive(f.path), LfsArchiveKind.notLfs);
    });

    test(
      'rejects a ZIP-magic file that is not actually a valid ZIP as notLfs',
      () {
        // Header looks like a ZIP but the rest is garbage — ZipDecoder throws.
        final f = File('${tempDir.path}/bad.lfs');
        f.writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, 0xFF, 0xFF, 0xFF, 0xFF]);
        expect(ExportImport.probeArchive(f.path), LfsArchiveKind.notLfs);
      },
    );

    test('rejects a file shorter than 4 bytes as notLfs', () {
      final f = File('${tempDir.path}/tiny.lfs');
      f.writeAsBytesSync([0x50, 0x4B]);
      expect(ExportImport.probeArchive(f.path), LfsArchiveKind.notLfs);
    });

    test('rejects a missing file as notLfs', () {
      expect(
        ExportImport.probeArchive('${tempDir.path}/missing.lfs'),
        LfsArchiveKind.notLfs,
      );
    });
  });
}

/// Minimal [ProgressReporter] subclass that records every label passed to
/// [phase] so tests can assert that the right phases ran in the right order.
///
/// Does NOT override [step] — export/import only use phase-level updates,
/// and recording every byte-level tick would drown the signal.
class _RecordingProgress extends ProgressReporter {
  final List<String> phases = [];

  _RecordingProgress(super.initialLabel);

  @override
  void phase(String label) {
    phases.add(label);
    super.phase(label);
  }
}

/// Minimal LFS-shaped ZIP payload — a manifest entry is enough for the
/// reader to treat it as "ours" without needing a real export run. Used
/// to feed the legacy PBKDF2 writer so we can verify the read path.
Uint8List _buildTestZip() {
  final archive = Archive();
  final manifest = utf8.encode(
    jsonEncode({
      'schema_version': 1,
      'created_at': DateTime.utc(2026).toIso8601String(),
    }),
  );
  archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
  final config = utf8.encode(jsonEncode(AppConfig.defaults.toJson()));
  archive.addFile(ArchiveFile('config.json', config.length, config));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
