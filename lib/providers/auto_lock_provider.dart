import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/auto_lock_store.dart';

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
class AutoLockMinutesNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Load the current value from the DB. Safe to call repeatedly; subsequent
  /// invocations simply re-read.
  Future<void> load() async {
    state = await ref.read(autoLockStoreProvider).load();
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
