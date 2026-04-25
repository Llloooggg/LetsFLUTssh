import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [PortForwardRules]. Cascade-on-delete from sessions
/// is handled at the schema level — deleting a session drops its
/// rules without a separate query here.
class PortForwardRuleDao {
  final AppDatabase _db;

  PortForwardRuleDao(this._db);

  Future<List<DbPortForwardRule>> getBySession(String sessionId) {
    return (_db.select(_db.portForwardRules)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Stream<List<DbPortForwardRule>> watchBySession(String sessionId) {
    return (_db.select(_db.portForwardRules)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<void> upsert(PortForwardRulesCompanion rule) async {
    await _db.into(_db.portForwardRules).insertOnConflictUpdate(rule);
    AppLogger.instance.log(
      'Upserted port-forward rule ${rule.id.value}',
      name: 'PortForwardDao',
    );
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.portForwardRules,
    )..where((t) => t.id.equals(id))).go();
    AppLogger.instance.log(
      'Deleted port-forward rule $id (rows: $count)',
      name: 'PortForwardDao',
    );
    return count;
  }

  Future<int> deleteBySession(String sessionId) async {
    return (_db.delete(
      _db.portForwardRules,
    )..where((t) => t.sessionId.equals(sessionId))).go();
  }

  Future<bool> setEnabled(String id, bool enabled) async {
    final count =
        await (_db.update(_db.portForwardRules)..where((t) => t.id.equals(id)))
            .write(PortForwardRulesCompanion(enabled: Value(enabled)));
    return count > 0;
  }
}
