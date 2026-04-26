import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/migration/registry.dart';
import 'package:letsflutssh/core/migration/schema_versions.dart';

/// Guards the "bump without a migration" class of bugs. Every artefact
/// in [buildAppMigrationRegistry] must have a registered migration for
/// each adjacent `(N-1, N)` pair between v1 and its [SchemaVersions]
/// target. The runner otherwise aborts with a fatal
/// "No migration registered for …" on first post-upgrade boot — this
/// test catches the same gap at PR time.
///
/// One artefact is exempt:
///   - `credentials.kdf` — self-versioned via its `'LFKD'` magic +
///     version byte; a format bump lives inside the KdfParams decoder
///     rather than a `Migration` subclass.
const _exemptArtefacts = <String>{'credentials.kdf'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('registry_completeness_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('every registered artefact has a migration for each (N-1, N) step', () {
    final reg = buildAppMigrationRegistry(supportDir: () async => tempDir);

    for (final artefact in reg.artefacts) {
      if (_exemptArtefacts.contains(artefact.id)) continue;
      final target = artefact.targetVersion;
      // v1 is the permanent floor — no migration to reach v1.
      for (var from = 1; from < target; from++) {
        final hasStep = reg.migrations.any(
          (m) => m.artefactId == artefact.id && m.fromVersion == from,
        );
        expect(
          hasStep,
          isTrue,
          reason:
              'Missing migration for ${artefact.id} from v$from to '
              'v${from + 1} — every SchemaVersions bump must register '
              'the matching Migration in buildAppMigrationRegistry.',
        );
      }
    }
  });

  test('registered artefact ids match SchemaVersions constants', () {
    final reg = buildAppMigrationRegistry(supportDir: () async => tempDir);
    final ids = reg.artefacts.map((a) => a.id).toSet();
    // These two are the artefacts the framework actively parses /
    // tracks today. Bumping any of them without updating this list is a
    // signal the new artefact also needs a companion entry here and in
    // the registry.
    expect(ids, contains('config.json'));
    expect(ids, contains('credentials.kdf'));
  });

  test('no duplicate (artefactId, fromVersion) migrations', () {
    final reg = buildAppMigrationRegistry(supportDir: () async => tempDir);
    final seen = <String>{};
    for (final m in reg.migrations) {
      final key = '${m.artefactId}@${m.fromVersion}';
      expect(
        seen.add(key),
        isTrue,
        reason:
            'Duplicate migration $key — only one path may exist between '
            'adjacent versions of a single artefact.',
      );
    }
  });
}
