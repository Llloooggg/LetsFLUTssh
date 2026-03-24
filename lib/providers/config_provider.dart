import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/config_store.dart';

/// Global config store instance.
final configStoreProvider = Provider<ConfigStore>((ref) {
  return ConfigStore();
});

/// App config state — loaded async, then updated in-place.
final configProvider =
    StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  return ConfigNotifier(ref.watch(configStoreProvider));
});

class ConfigNotifier extends StateNotifier<AppConfig> {
  final ConfigStore _store;

  ConfigNotifier(this._store) : super(AppConfig.defaults);

  Future<void> load() async {
    state = await _store.load();
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    final updated = updater(state);
    await _store.save(updated);
    state = updated;
  }
}
