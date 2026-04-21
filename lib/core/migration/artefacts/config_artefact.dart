import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../artefact.dart';
import '../schema_versions.dart';

/// `config.json` payload format.
///
/// The file is plain JSON. The schema version is tracked via a top-level
/// `config_schema_version` field inside the JSON itself — stamped by
/// `ConfigStore.save` on every write. A missing field, non-integer
/// value, or malformed JSON is treated as corrupt (throws); the runner
/// surfaces the fatal error to the caller which routes the user through
/// the reset dialog.
class ConfigArtefact extends Artefact {
  ConfigArtefact({Future<Directory> Function()? supportDir})
    : _supportDir = supportDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDir;

  static const _fileName = 'config.json';
  static const _versionField = 'config_schema_version';

  @override
  String get id => _fileName;

  @override
  int get targetVersion => SchemaVersions.config;

  @override
  Future<int> readVersion() async {
    final dir = await _supportDir();
    final file = File(p.join(dir.path, _fileName));
    if (!await file.exists()) return -1;
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('config.json: not a JSON object');
    }
    final raw = decoded[_versionField];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    throw const FormatException(
      'config.json: missing or non-integer config_schema_version',
    );
  }
}
