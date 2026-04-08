import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/config_store.dart';
import '../utils/logger.dart';

/// Global config store instance.
final configStoreProvider = Provider<ConfigStore>((ref) {
  return ConfigStore();
});

/// App config state — loaded async, then updated in-place.
final configProvider = NotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);

class ConfigNotifier extends Notifier<AppConfig> {
  /// Sequential save lock — prevents concurrent file writes.
  Future<void> _pendingSave = Future.value();

  @override
  AppConfig build() => ref.read(configStoreProvider).config;

  ConfigStore get _store => ref.read(configStoreProvider);

  Future<void> load() async {
    try {
      state = await _store.load();
      // Sync logger enabled state with config
      AppLogger.instance.setEnabled(state.enableLogging);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load config, using defaults',
        name: 'ConfigProvider',
        error: e,
      );
    }
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    try {
      final updated = updater(state);
      state = updated;
      // Apply logging toggle immediately
      AppLogger.instance.setEnabled(updated.enableLogging);
      // Chain saves to prevent concurrent file writes
      _pendingSave = _pendingSave.then(
        (_) => _store.save(updated),
        onError: (_) => _store.save(updated),
      );
      await _pendingSave;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to save config',
        name: 'ConfigProvider',
        error: e,
      );
      rethrow;
    }
  }
}
