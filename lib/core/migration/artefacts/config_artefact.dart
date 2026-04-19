import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../utils/logger.dart';
import '../artefact.dart';
import '../schema_versions.dart';

/// `config.json` payload format.
///
/// The file is plain JSON. The schema version is tracked via a
/// top-level `config_schema_version` field inside the JSON itself —
/// when the field is absent (every config written before the schema
/// was introduced) the reader returns `1` so the migration runner
/// sees it as legacy. New writes in `config_store.save` stamp
/// `config_schema_version` to [SchemaVersions.config].
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
    try {
      final dir = await _supportDir();
      final file = File(p.join(dir.path, _fileName));
      if (!await file.exists()) return -1;
      final content = await file.readAsString();
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          final raw = decoded[_versionField];
          if (raw is int) return raw;
          if (raw is num) return raw.toInt();
        }
      } catch (_) {
        // Corrupt JSON: treat as legacy so the runner routes through
        // the reset path rather than silently mis-reading.
      }
      // No `config_schema_version` field — config was written by a
      // pre-field build. Report as version 1 (the pre-migration-
      // framework baseline).
      return 1;
    } catch (e) {
      AppLogger.instance.log(
        'ConfigArtefact.readVersion failed: $e',
        name: 'ConfigArtefact',
      );
      return -1;
    }
  }
}
