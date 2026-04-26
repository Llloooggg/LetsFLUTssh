import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'app_config.dart';

/// Loads/saves AppConfig as JSON in the app support directory.
class ConfigStore {
  static const _fileName = 'config.json';

  AppConfig _config = AppConfig.defaults;
  late final String _filePath;
  bool _initialized = false;

  /// True if config was loaded from file; false if defaults were used
  /// (file missing or corrupted).
  bool loadedFromFile = false;

  /// Non-null if config load failed (corrupted JSON, etc.).
  String? loadError;

  AppConfig get config => _config;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationSupportDirectory();
    _filePath = p.join(dir.path, _fileName);
    _initialized = true;
  }

  Future<AppConfig> load() async {
    await init();
    loadError = null;
    loadedFromFile = false;
    final file = File(_filePath);
    if (!await file.exists()) {
      _config = AppConfig.defaults;
      return _config;
    }
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      _config = AppConfig.fromJson(json);
      loadedFromFile = true;
    } catch (e) {
      loadError = 'Failed to load config: $e';
      AppLogger.instance.log(loadError!, name: 'ConfigStore');
      _config = AppConfig.defaults;
    }
    return _config;
  }

  Future<void> save(AppConfig config) async {
    await init();
    _config = config;
    // Stamp the current schema version on every write so the Rust
    // migration runner on the next launch can detect any version
    // other than the current `SchemaVersions::CONFIG` (defined in
    // `lfs_core::migration::SchemaVersions`) and route the user
    // through the reset path. Mirrors the Rust constant by literal —
    // this whole writer moves to `lfs_core::config` in a follow-up
    // arc, at which point the duplication retires.
    final payload = <String, dynamic>{
      'config_schema_version': 1,
      ...config.toJson(),
    };
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    await writeFileAtomic(_filePath, content);
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    final updated = updater(_config);
    await save(updated);
  }
}
