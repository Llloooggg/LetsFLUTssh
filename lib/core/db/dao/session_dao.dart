import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [Sessions] table.
class SessionDao {
  final AppDatabase _db;

  SessionDao(this._db);

  Future<List<DbSession>> getAll() => _db.select(_db.sessions).get();

  Stream<List<DbSession>> watchAll() => _db.select(_db.sessions).watch();

  Future<DbSession?> getById(String id) => (_db.select(
    _db.sessions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<DbSession>> getByFolder(String? folderId) {
    final q = _db.select(_db.sessions);
    if (folderId == null) {
      q.where((t) => t.folderId.isNull());
    } else {
      q.where((t) => t.folderId.equals(folderId));
    }
    return q.get();
  }

  Future<List<DbSession>> search(String query) {
    final pattern = '%$query%';
    return (_db.select(_db.sessions)..where(
          (t) =>
              t.label.like(pattern) |
              t.host.like(pattern) |
              t.user.like(pattern),
        ))
        .get();
  }

  Future<void> insert(SessionsCompanion session) async {
    await _db.into(_db.sessions).insert(session);
    AppLogger.instance.log(
      'Inserted session ${session.id.value}',
      name: 'SessionDao',
    );
  }

  Future<bool> update(SessionsCompanion session) async {
    final count = await (_db.update(
      _db.sessions,
    )..where((t) => t.id.equals(session.id.value))).write(session);
    AppLogger.instance.log(
      'Updated session ${session.id.value} (rows: $count)',
      name: 'SessionDao',
    );
    return count > 0;
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.sessions,
    )..where((t) => t.id.equals(id))).go();
    AppLogger.instance.log(
      'Deleted session $id (rows: $count)',
      name: 'SessionDao',
    );
    return count;
  }

  Future<int> deleteMultiple(Set<String> ids) async {
    final count = await (_db.delete(
      _db.sessions,
    )..where((t) => t.id.isIn(ids))).go();
    AppLogger.instance.log(
      'Deleted ${ids.length} sessions (rows: $count)',
      name: 'SessionDao',
    );
    return count;
  }

  Future<void> deleteAll() async {
    final count = await _db.delete(_db.sessions).go();
    AppLogger.instance.log(
      'Deleted all sessions (rows: $count)',
      name: 'SessionDao',
    );
  }

  Future<bool> moveToFolder(String sessionId, String? folderId) async {
    final count =
        await (_db.update(
          _db.sessions,
        )..where((t) => t.id.equals(sessionId))).write(
          SessionsCompanion(
            folderId: Value(folderId),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return count > 0;
  }

  Future<int> moveMultiple(Set<String> ids, String? folderId) async {
    final count = await (_db.update(_db.sessions)..where((t) => t.id.isIn(ids)))
        .write(
          SessionsCompanion(
            folderId: Value(folderId),
            updatedAt: Value(DateTime.now()),
          ),
        );
    AppLogger.instance.log(
      'Moved ${ids.length} sessions to folder $folderId (rows: $count)',
      name: 'SessionDao',
    );
    return count;
  }

  Future<bool> updateLastConnected(String id) async {
    final count =
        await (_db.update(_db.sessions)..where((t) => t.id.equals(id))).write(
          SessionsCompanion(lastConnectedAt: Value(DateTime.now())),
        );
    return count > 0;
  }
}
