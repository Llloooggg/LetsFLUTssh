import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await db.sessionDao.insert(
      SessionsCompanion.insert(
        id: 's1',
        host: 'h',
        user: 'u',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SftpBookmarkDao', () {
    test('insert and getForSession', () async {
      await db.sftpBookmarkDao.insert(
        SftpBookmarksCompanion.insert(
          id: 'b1',
          sessionId: 's1',
          remotePath: '/var/log',
          createdAt: DateTime(2024),
        ),
      );
      final bookmarks = await db.sftpBookmarkDao.getForSession('s1');
      expect(bookmarks, hasLength(1));
      expect(bookmarks.first.remotePath, '/var/log');
    });

    test('getForSession returns empty for no bookmarks', () async {
      expect(await db.sftpBookmarkDao.getForSession('s1'), isEmpty);
    });

    test('deleteById removes bookmark', () async {
      await db.sftpBookmarkDao.insert(
        SftpBookmarksCompanion.insert(
          id: 'b1',
          sessionId: 's1',
          remotePath: '/tmp',
          createdAt: DateTime(2024),
        ),
      );
      await db.sftpBookmarkDao.deleteById('b1');
      expect(await db.sftpBookmarkDao.getForSession('s1'), isEmpty);
    });

    test('deleting session cascades to bookmarks', () async {
      await db.sftpBookmarkDao.insert(
        SftpBookmarksCompanion.insert(
          id: 'b1',
          sessionId: 's1',
          remotePath: '/tmp',
          createdAt: DateTime(2024),
        ),
      );
      await db.sessionDao.deleteById('s1');
      // Bookmark gone with session
      expect(await db.sftpBookmarkDao.getForSession('s1'), isEmpty);
    });
  });
}
