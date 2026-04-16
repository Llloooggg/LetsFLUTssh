import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [AppConfigs] table (single-row JSON blob).
class ConfigDao {
  final AppDatabase _db;

  ConfigDao(this._db);

  /// Read the config JSON string, or null if not yet saved.
  Future<String?> get() async {
    final row = await (_db.select(
      _db.appConfigs,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    return row?.data;
  }

  /// Insert or replace the config JSON.
  Future<void> save(String jsonData) async {
    await _db
        .into(_db.appConfigs)
        .insertOnConflictUpdate(
          AppConfigsCompanion(
            id: const Value(1),
            data: Value(jsonData),
            updatedAt: Value(DateTime.now()),
          ),
        );
    AppLogger.instance.log('Saved config', name: 'ConfigDao');
  }

  /// Read the auto-lock timeout in minutes (0 = disabled). Returns 0 if the
  /// settings row was never written — same as the column default — so the
  /// caller never needs to handle a null.
  Future<int> getAutoLockMinutes() async {
    final row = await (_db.select(
      _db.appConfigs,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    return row?.autoLockMinutes ?? 0;
  }

  /// Persist the auto-lock timeout in minutes. `0` disables auto-lock. Uses
  /// upsert so we never need to worry about whether the row exists yet —
  /// the `data` column has a NOT NULL constraint, so seed it with `'{}'`
  /// when the row is fresh.
  Future<void> setAutoLockMinutes(int minutes) async {
    final existing = await (_db.select(
      _db.appConfigs,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    await _db
        .into(_db.appConfigs)
        .insertOnConflictUpdate(
          AppConfigsCompanion(
            id: const Value(1),
            data: Value(existing?.data ?? '{}'),
            autoLockMinutes: Value(minutes),
            updatedAt: Value(DateTime.now()),
          ),
        );
    AppLogger.instance.log('Saved autoLockMinutes=$minutes', name: 'ConfigDao');
  }
}
