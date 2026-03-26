import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/config_store.dart';
import '../utils/logger.dart';

/// Global config store instance.
final configStoreProvider = Provider<ConfigStore>((ref) {
  return ConfigStore();
});

/// App config state — loaded async, then updated in-place.
final configProvider =
    NotifierProvider<ConfigNotifier, AppConfig>(ConfigNotifier.new);

class ConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() => AppConfig.defaults;

  ConfigStore get _store => ref.read(configStoreProvider);

  Future<void> load() async {
    state = await _store.load();
    // Sync logger enabled state with config
    AppLogger.instance.setEnabled(state.enableLogging);
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    final updated = updater(state);
    await _store.save(updated);
    state = updated;
    // Apply logging toggle immediately
    AppLogger.instance.setEnabled(updated.enableLogging);
  }
}
