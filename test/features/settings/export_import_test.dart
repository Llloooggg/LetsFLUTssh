import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/features/settings/export_import.dart';

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
      host: host,
      user: user,
      password: password,
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
        sessions: sessions,
        config: config,
        outputPath: outputPath,
      );

      expect(await File(outputPath).exists(), isTrue);

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'test-password',
        mode: ImportMode.merge,
        importConfig: true,
        importKnownHosts: false,
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
        terminal: AppConfig.defaults.terminal.copyWith(fontSize: 18, scrollback: 10000),
      );
      final outputPath = '${tempDir.path}/config.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        sessions: [],
        config: config,
        outputPath: outputPath,
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.replace,
        importConfig: true,
        importKnownHosts: false,
      );

      expect(result.config, isNotNull);
      expect(result.config!.fontSize, 18);
      expect(result.config!.scrollback, 10000);
      expect(result.mode, ImportMode.replace);
    });

    test('import with importConfig=false skips config', () async {
      final outputPath = '${tempDir.path}/noconfig.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        sessions: [],
        config: AppConfig.defaults,
        outputPath: outputPath,
      );

      final result = await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        importConfig: false,
        importKnownHosts: false,
      );

      expect(result.config, isNull);
    });

    test('export includes known_hosts when present', () async {
      // Write a known_hosts file
      final khFile = File('${tempDir.path}/known_hosts');
      await khFile.writeAsString('example.com ssh-rsa AAAAB3...');

      final outputPath = '${tempDir.path}/withkh.lfs';
      await ExportImport.export(
        masterPassword: 'pw',
        sessions: [],
        config: AppConfig.defaults,
        outputPath: outputPath,
      );

      await ExportImport.import_(
        filePath: outputPath,
        masterPassword: 'pw',
        mode: ImportMode.merge,
        importConfig: false,
        importKnownHosts: true,
      );

      // known_hosts should have been restored
      final restoredKh = File('${tempDir.path}/known_hosts');
      expect(await restoredKh.exists(), isTrue);
      expect(await restoredKh.readAsString(), 'example.com ssh-rsa AAAAB3...');
    });
  });

  group('ExportImport — preview', () {
    test('preview shows sessions and flags', () async {
      final sessions = [
        makeSession(id: 'prev-1', label: 'preview-server'),
      ];
      final outputPath = '${tempDir.path}/preview.lfs';

      await ExportImport.export(
        masterPassword: 'pw',
        sessions: sessions,
        config: AppConfig.defaults,
        outputPath: outputPath,
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
        sessions: [],
        config: AppConfig.defaults,
        outputPath: outputPath,
      );

      expect(
        () => ExportImport.import_(
          filePath: outputPath,
          masterPassword: 'wrong',
          mode: ImportMode.merge,
          importConfig: true,
          importKnownHosts: false,
        ),
        throwsA(anything),
      );
    });
  });

  group('ImportMode and ImportResult', () {
    test('ImportMode values', () {
      expect(ImportMode.values, hasLength(2));
      expect(ImportMode.values, contains(ImportMode.merge));
      expect(ImportMode.values, contains(ImportMode.replace));
    });

    test('ImportResult holds data', () {
      const result = ImportResult(
        sessions: [],
        mode: ImportMode.merge,
      );
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
      expect(preview.hasConfig, isTrue);
      expect(preview.hasKnownHosts, isFalse);
    });
  });
}
