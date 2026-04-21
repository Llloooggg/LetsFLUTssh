import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../artefact.dart';
import '../schema_versions.dart';

/// `credentials.kdf` — Argon2id parameter blob written by `KdfParams`.
/// Self-versioned inside the file via `'LFKD'` magic + version byte;
/// the framework just registers the file's presence so the migration
/// runner has a complete world view. A future format bump registers a
/// proper [Migration] that reads the inner version byte.
class KdfArtefact extends Artefact {
  KdfArtefact({Future<Directory> Function()? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDir;

  static const _fileName = 'credentials.kdf';

  @override
  String get id => _fileName;

  @override
  int get targetVersion => SchemaVersions.kdf;

  @override
  Future<int> readVersion() async {
    final dir = await _supportDir();
    final exists = await File(p.join(dir.path, _fileName)).exists();
    return exists ? targetVersion : -1;
  }
}
