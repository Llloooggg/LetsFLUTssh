import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/db.dart' as rust_db;
import '../utils/logger.dart';

/// Auto-lock idle timeout in minutes. `0` = disabled.
///
/// The value is stored in the encrypted DB (`lfs_core.db`) so an
/// attacker with plaintext-disk access cannot weaken the security
/// control by editing a config file. Reads return `0` until the DB
/// is unlocked; the notifier reloads itself the first time `load()`
/// is called from `main.dart` after a successful unlock.
///
/// Replaces the prior two-tier `Provider<AutoLockStore>` +
/// `NotifierProvider<AutoLockMinutesNotifier>` split — the Notifier
/// now owns the FRB read/write pipeline directly.
final autoLockMinutesProvider = NotifierProvider<AutoLockMinutesNotifier, int>(
  AutoLockMinutesNotifier.new,
);

class AutoLockMinutesNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Load the current value from the DB. Returns `0` when the DB
  /// isn't available yet (locked) or no value has been written.
  /// Safe to call repeatedly; subsequent invocations re-read.
  Future<void> load() async {
    state = await _readFromDb();
  }

  /// Persist [minutes] (`0` disables auto-lock). Reads the row first
  /// so we never clobber the JSON `data` blob that ConfigStore-style
  /// future writes might park here. Writes are silently dropped if
  /// the DB is locked.
  Future<void> set(int minutes) async {
    try {
      final existing = await rust_db.dbAppConfigsGet();
      await rust_db.dbAppConfigsUpsert(
        row: rust_db.DbAppConfig(
          data: existing?.data ?? '{}',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          autoLockMinutes: minutes,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'autoLockMinutes save failed (DB not unlocked?): $e',
        name: 'AutoLockNotifier',
        level: LogLevel.warn,
      );
    }
    state = minutes;
  }

  Future<int> _readFromDb() async {
    try {
      final row = await rust_db.dbAppConfigsGet();
      return row?.autoLockMinutes ?? 0;
    } catch (e) {
      AppLogger.instance.log(
        'autoLockMinutes load failed (DB not unlocked?): $e',
        name: 'AutoLockNotifier',
        level: LogLevel.warn,
      );
      return 0;
    }
  }
}
