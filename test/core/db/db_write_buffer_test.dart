import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/db_write_buffer.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // In-memory drift DB — enough to exercise transaction semantics
    // without touching the real encrypted DB path.
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('DbWriteBuffer', () {
    test('empty buffer drains without error and reports empty', () async {
      final buffer = DbWriteBuffer();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, 0);
      await buffer.drain(db);
      expect(buffer.isEmpty, isTrue);
    });

    test('appended ops run inside a single transaction on drain', () async {
      final buffer = DbWriteBuffer();
      final order = <int>[];
      buffer.append((_) async => order.add(1));
      buffer.append((_) async => order.add(2));
      buffer.append((_) async => order.add(3));
      expect(buffer.length, 3);
      await buffer.drain(db);
      expect(order, [1, 2, 3]);
      expect(buffer.isEmpty, isTrue);
    });

    test('FIFO eviction when the cap is hit', () async {
      final buffer = DbWriteBuffer(maxEntries: 3);
      final order = <int>[];
      buffer.append((_) async => order.add(1));
      buffer.append((_) async => order.add(2));
      buffer.append((_) async => order.add(3));
      // This one pushes out the oldest (1).
      final accepted = buffer.append((_) async => order.add(4));
      expect(accepted, isFalse);
      expect(buffer.length, 3);
      await buffer.drain(db);
      expect(order, [2, 3, 4]);
    });

    test('failing op rolls back the transaction and preserves queue', () async {
      final buffer = DbWriteBuffer();
      buffer.append((_) async {});
      buffer.append((_) async => throw StateError('boom'));
      buffer.append((_) async {});
      expect(buffer.length, 3);
      await expectLater(buffer.drain(db), throwsA(isA<StateError>()));
      // Queue preserved so a retry is possible.
      expect(buffer.length, 3);
    });

    test('clear drops all pending writes unconditionally', () {
      final buffer = DbWriteBuffer();
      buffer.append((_) async {});
      buffer.append((_) async {});
      expect(buffer.length, 2);
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
    });
  });
}
