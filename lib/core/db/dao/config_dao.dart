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
}
