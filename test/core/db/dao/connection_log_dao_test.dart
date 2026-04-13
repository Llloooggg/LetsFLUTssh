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

  group('ConnectionLogDao', () {
    test('insert returns auto-generated id', () async {
      final id = await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2024, 1, 1),
        ),
      );
      expect(id, greaterThan(0));
    });

    test('getForSession returns entries ordered by time desc', () async {
      await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2024, 1, 1),
        ),
      );
      await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2024, 6, 1),
        ),
      );

      final logs = await db.connectionLogDao.getForSession('s1');
      expect(logs, hasLength(2));
      expect(logs.first.connectedAt.isAfter(logs.last.connectedAt), isTrue);
    });

    test('getRecent respects limit', () async {
      for (var i = 0; i < 5; i++) {
        await db.connectionLogDao.insert(
          ConnectionLogsCompanion.insert(
            sessionId: 's1',
            connectedAt: DateTime(2024, 1, i + 1),
          ),
        );
      }
      expect(await db.connectionLogDao.getRecent(limit: 3), hasLength(3));
    });

    test('markDisconnected sets timestamp and reason', () async {
      final id = await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2024),
        ),
      );
      await db.connectionLogDao.markDisconnected(id, reason: 'timeout');

      final logs = await db.connectionLogDao.getForSession('s1');
      expect(logs.first.disconnectedAt, isNotNull);
      expect(logs.first.disconnectReason, 'timeout');
    });

    test('deleteOlderThan prunes old entries', () async {
      await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2023, 1, 1),
        ),
      );
      await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2024, 6, 1),
        ),
      );

      final removed = await db.connectionLogDao.deleteOlderThan(
        DateTime(2024, 1, 1),
      );
      expect(removed, 1);
      expect(await db.connectionLogDao.getForSession('s1'), hasLength(1));
    });

    test('deleting session cascades to logs', () async {
      await db.connectionLogDao.insert(
        ConnectionLogsCompanion.insert(
          sessionId: 's1',
          connectedAt: DateTime(2024),
        ),
      );
      await db.sessionDao.deleteById('s1');
      expect(await db.connectionLogDao.getForSession('s1'), isEmpty);
    });
  });
}
