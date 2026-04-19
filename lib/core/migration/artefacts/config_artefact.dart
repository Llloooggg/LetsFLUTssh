import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/logger.dart';
import '../artefact.dart';
import '../schema_versions.dart';

/// `config.json` payload format. Phase A2: presence-only check.
///
/// The file is plain JSON without an envelope. Until Phase G bumps
/// the format (3-tier collapse), the on-disk version is whatever the
/// constant says — we cannot infer it from the bytes themselves.
/// Treating "file present" as "version == [SchemaVersions.config]"
/// is correct because every install that has a `config.json` was
/// written by a build whose current target was that constant.
class ConfigArtefact extends Artefact {
  ConfigArtefact({Future<Directory> Function()? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDir;

  static const _fileName = 'config.json';

  @override
  String get id => _fileName;

  @override
  int get targetVersion => SchemaVersions.config;

  @override
  Future<int> readVersion() async {
    try {
      final dir = await _supportDir();
      final exists = await File(p.join(dir.path, _fileName)).exists();
      return exists ? targetVersion : -1;
    } catch (e) {
      AppLogger.instance.log(
        'ConfigArtefact.readVersion failed: $e',
        name: 'ConfigArtefact',
      );
      return -1;
    }
  }
}
