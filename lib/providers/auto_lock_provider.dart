import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/auto_lock_store.dart';
import '../utils/logger.dart';
import 'config_provider.dart';

/// Singleton store. The DB handle is injected from main.dart's
/// `_injectDatabase` helper alongside the other DAO-backed stores.
final autoLockStoreProvider = Provider<AutoLockStore>((_) => AutoLockStore());

/// Auto-lock idle timeout in minutes. `0` = disabled.
///
/// The value is stored in the encrypted DB (see [AutoLockStore]) so an
/// attacker with plaintext-disk access cannot weaken the security control by
/// editing a config file. Reads return `0` until the DB is unlocked; the
/// notifier reloads itself the first time `load()` is called from
/// `main.dart` after a successful unlock.
///
/// One-shot legacy migration: on first load after upgrade, if the DB has
/// the default value (`0`) but the legacy file-based [BehaviorConfig] has
/// a non-zero value, copy the file value into the DB and clear the file
/// field. This way users do not lose their existing setting on upgrade.
class AutoLockMinutesNotifier extends Notifier<int> {
  bool _loaded = false;

  @override
  int build() => 0;

  /// Load the current value from the DB. Safe to call repeatedly; subsequent
  /// invocations simply re-read. Triggers the legacy migration once.
  Future<void> load() async {
    final store = ref.read(autoLockStoreProvider);
    final stored = await store.load();
    if (!_loaded) {
      _loaded = true;
      // Legacy migration — happens once per process lifetime, after first
      // successful unlock. Idempotent because writing 0 back to config.json
      // is itself a no-op for everyone who already migrated.
      final legacy = ref.read(configProvider).behavior.autoLockMinutes;
      if (stored == 0 && legacy > 0) {
        AppLogger.instance.log(
          'Migrating autoLockMinutes=$legacy from config.json to DB',
          name: 'AutoLock',
        );
        await store.save(legacy);
        await ref
            .read(configProvider.notifier)
            .update(
              (c) =>
                  c.copyWith(behavior: c.behavior.copyWith(autoLockMinutes: 0)),
            );
        state = legacy;
        return;
      }
    }
    state = stored;
  }

  /// Persist a new value and update local state.
  Future<void> set(int minutes) async {
    await ref.read(autoLockStoreProvider).save(minutes);
    state = minutes;
  }
}

final autoLockMinutesProvider = NotifierProvider<AutoLockMinutesNotifier, int>(
  AutoLockMinutesNotifier.new,
);
