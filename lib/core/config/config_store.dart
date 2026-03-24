import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// Loads/saves AppConfig as JSON in the app support directory.
class ConfigStore {
  static const _fileName = 'config.json';

  AppConfig _config = AppConfig.defaults;
  late final String _filePath;
  bool _initialized = false;

  AppConfig get config => _config;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationSupportDirectory();
    _filePath = p.join(dir.path, _fileName);
    _initialized = true;
  }

  Future<AppConfig> load() async {
    await init();
    final file = File(_filePath);
    if (!await file.exists()) {
      _config = AppConfig.defaults;
      return _config;
    }
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      _config = AppConfig.fromJson(json);
    } catch (e) {
      dev.log('ConfigStore: failed to load config: $e');
      _config = AppConfig.defaults;
    }
    return _config;
  }

  Future<void> save(AppConfig config) async {
    await init();
    _config = config;
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent('  ').convert(config.toJson());
    await file.writeAsString(content);
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    final updated = updater(_config);
    await save(updated);
  }
}
