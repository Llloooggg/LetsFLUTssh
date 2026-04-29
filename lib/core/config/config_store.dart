import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/config.dart' as rust_config;
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
    // Bootstrap the Rust `lfs_core::config_store::Store` actor
    // against the same directory so subsequent save() calls land
    // on disk through the Rust atomic-write + bus-event path
    // (Decision 5 / D5 in `docs/RUST_MIGRATION_REMAINING.md`).
    // Best-effort — flutter_test contexts that don't load the
    // FRB native lib continue to use the inline file-write
    // fallback below.
    try {
      rust_config.configStoreInit(supportDir: dir.path);
    } catch (e) {
      AppLogger.instance.log(
        'config_store_init unreachable, falling back to '
        'Dart file writes: $e',
        name: 'ConfigStore',
      );
    }
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
    // Production routes through `lfs_core::config_store::Store`
    // (Decision 5 / D5) — the actor owns the in-memory snapshot,
    // 300 ms debounce, atomic write through `write_bytes_atomic`,
    // and the bus event publication. Fallback to the inline
    // `writeFileAtomic` for flutter_test contexts that don't
    // load the FRB native lib.
    try {
      rust_config.configStoreSetJson(newJson: jsonEncode(payload));
      // Force the pending state to disk — explicit save semantic
      // ("save now"), not a debounced write. The Dart
      // `ConfigNotifier.update` debounce path will land in D6.2
      // when the notifier itself migrates to the actor.
      rust_config.configStoreFlush();
      return;
    } catch (e) {
      AppLogger.instance.log(
        'config_store_set_json unreachable, falling back to '
        'Dart file write: $e',
        name: 'ConfigStore',
      );
    }
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    await writeFileAtomic(_filePath, content);
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    final updated = updater(_config);
    await save(updated);
  }
}
