import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '../migration/schema_versions.dart';
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
    // Stamp the current schema version on every write so the
    // migration runner on the next launch can route a legacy config
    // (no field → version 1) through the reset path and a fresh
    // config through untouched.
    final payload = <String, dynamic>{
      'config_schema_version': SchemaVersions.config,
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
