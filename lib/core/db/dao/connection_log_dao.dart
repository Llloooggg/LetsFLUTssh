import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [ConnectionLogs] table.
class ConnectionLogDao {
  final AppDatabase _db;

  ConnectionLogDao(this._db);

  Future<List<DbConnectionLog>> getForSession(String sessionId) =>
      (_db.select(_db.connectionLogs)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.desc(t.connectedAt)]))
          .get();

  Future<List<DbConnectionLog>> getRecent({int limit = 50}) =>
      (_db.select(_db.connectionLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.connectedAt)])
            ..limit(limit))
          .get();

  /// Insert a new log entry and return its auto-generated id.
  Future<int> insert(ConnectionLogsCompanion entry) async {
    final id = await _db.into(_db.connectionLogs).insert(entry);
    AppLogger.instance.log(
      'Logged connection for session ${entry.sessionId.value}',
      name: 'ConnectionLogDao',
    );
    return id;
  }

  Future<bool> markDisconnected(int id, {String reason = ''}) async {
    final count =
        await (_db.update(
          _db.connectionLogs,
        )..where((t) => t.id.equals(id))).write(
          ConnectionLogsCompanion(
            disconnectedAt: Value(DateTime.now()),
            disconnectReason: Value(reason),
          ),
        );
    return count > 0;
  }

  Future<int> deleteOlderThan(DateTime cutoff) async {
    final count = await (_db.delete(
      _db.connectionLogs,
    )..where((t) => t.connectedAt.isSmallerThanValue(cutoff))).go();
    AppLogger.instance.log(
      'Pruned connection log before $cutoff (rows: $count)',
      name: 'ConnectionLogDao',
    );
    return count;
  }
}
