import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
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
        throwsA(anything),
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
}
