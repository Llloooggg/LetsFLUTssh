import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/logger.dart';
import '../artefact.dart';
import '../schema_versions.dart';

/// `letsflutssh.db` — Drift / SQLite encrypted database. Drift owns
/// its own schema migration via `MigrationStrategy.onUpgrade`; this
/// artefact only marks "the DB is here" so the framework's
/// dependency graph can order other artefacts around it.
///
/// `readVersion` returns the canonical [SchemaVersions.db] when the
/// file exists. We intentionally do not try to peek into SQLite
/// before drift opens it — drift's own opener handles that path
/// correctly under the cipher key, and replicating it here would
/// duplicate logic.
class DbArtefact extends Artefact {
  DbArtefact({Future<Directory> Function()? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDir;

  static const _fileName = 'letsflutssh.db';

  @override
  String get id => _fileName;

  @override
  int get targetVersion => SchemaVersions.db;

  @override
  Future<int> readVersion() async {
    try {
      final dir = await _supportDir();
      final exists = await File(p.join(dir.path, _fileName)).exists();
      return exists ? targetVersion : -1;
    } catch (e) {
      AppLogger.instance.log(
        'DbArtefact.readVersion failed: $e',
        name: 'DbArtefact',
      );
      return -1;
    }
  }
}
