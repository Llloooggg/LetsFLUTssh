import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/migration/artefacts/config_artefact.dart';
import 'package:letsflutssh/core/migration/artefacts/kdf_artefact.dart';
import 'package:letsflutssh/core/migration/registry.dart';
import 'package:letsflutssh/core/migration/schema_versions.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('migration_artefact_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<Directory> dirFactory() async => tempDir;

  group('ConfigArtefact', () {
    test('reports -1 when config.json is absent', () async {
      final a = ConfigArtefact(supportDir: dirFactory);
      expect(await a.readVersion(), -1);
    });

    test(
      'throws when config.json is missing the schema_version field',
      () async {
        File(p.join(tempDir.path, 'config.json')).writeAsStringSync('{}');
        final a = ConfigArtefact(supportDir: dirFactory);
        expect(() => a.readVersion(), throwsA(isA<FormatException>()));
      },
    );

    test(
      'reports the stamped schema_version when the field is present',
      () async {
        File(
          p.join(tempDir.path, 'config.json'),
        ).writeAsStringSync('{"config_schema_version": 2}');
        final a = ConfigArtefact(supportDir: dirFactory);
        expect(await a.readVersion(), 2);
      },
    );

    test(
      'throws when the file is corrupt — runner routes through the reset path',
      () async {
        File(
          p.join(tempDir.path, 'config.json'),
        ).writeAsStringSync('{ not json');
        final a = ConfigArtefact(supportDir: dirFactory);
        expect(() => a.readVersion(), throwsA(isA<FormatException>()));
      },
    );

    test('id is the file name', () {
      expect(ConfigArtefact(supportDir: dirFactory).id, 'config.json');
    });
  });

  group('KdfArtefact', () {
    test('reports -1 when credentials.kdf is absent', () async {
      final a = KdfArtefact(supportDir: dirFactory);
      expect(await a.readVersion(), -1);
    });

    test('reports targetVersion when credentials.kdf exists', () async {
      File(p.join(tempDir.path, 'credentials.kdf')).writeAsBytesSync([1, 2, 3]);
      final a = KdfArtefact(supportDir: dirFactory);
      expect(await a.readVersion(), SchemaVersions.kdf);
    });
  });

  group('buildAppMigrationRegistry', () {
    test('registers config + kdf artefacts (no migrations yet)', () {
      final reg = buildAppMigrationRegistry(supportDir: dirFactory);
      final ids = reg.artefacts.map((a) => a.id).toSet();
      expect(ids, containsAll(['config.json', 'credentials.kdf']));
      expect(reg.migrations, isEmpty);
    });

    test('declares hardware-vault deps on config to keep ordering stable', () {
      final reg = buildAppMigrationRegistry(supportDir: dirFactory);
      expect(reg.dependencies['hardware_vault.bin'], contains('config.json'));
      expect(
        reg.dependencies['hardware_vault_salt.bin'],
        contains('config.json'),
      );
      expect(
        reg.dependencies['security_pass_hash.bin'],
        contains('config.json'),
      );
    });
  });
}
