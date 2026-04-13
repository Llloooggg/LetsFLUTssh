import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [SftpBookmarks] table.
class SftpBookmarkDao {
  final AppDatabase _db;

  SftpBookmarkDao(this._db);

  Future<List<DbSftpBookmark>> getForSession(String sessionId) => (_db.select(
    _db.sftpBookmarks,
  )..where((t) => t.sessionId.equals(sessionId))).get();

  Future<void> insert(SftpBookmarksCompanion bookmark) async {
    await _db.into(_db.sftpBookmarks).insert(bookmark);
    AppLogger.instance.log(
      'Inserted SFTP bookmark ${bookmark.id.value}',
      name: 'SftpBookmarkDao',
    );
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.sftpBookmarks,
    )..where((t) => t.id.equals(id))).go();
    return count;
  }
}
