import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:path/path.dart' as p;

void main() {
  group('restrictDatabaseFilePermissions', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lfsdb_chmod_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('sets owner-only mode on the main DB file', () async {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final dbPath = p.join(tmp.path, 'letsflutssh.db');
      await File(dbPath).writeAsBytes([0]);

      await restrictDatabaseFilePermissions(dbPath);

      final mode = await File(dbPath).stat().then((s) => s.mode & 0x1FF);
      expect(mode, 0x180); // 0600
    });

    test('also restricts existing sidecar files', () async {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final dbPath = p.join(tmp.path, 'letsflutssh.db');
      await File(dbPath).writeAsBytes([0]);
      final wal = File('$dbPath-wal');
      await wal.writeAsBytes([0]);
      final shm = File('$dbPath-shm');
      await shm.writeAsBytes([0]);

      await restrictDatabaseFilePermissions(dbPath);

      expect(await wal.stat().then((s) => s.mode & 0x1FF), 0x180);
      expect(await shm.stat().then((s) => s.mode & 0x1FF), 0x180);
    });

    test('skips missing sidecars without error', () async {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final dbPath = p.join(tmp.path, 'letsflutssh.db');
      await File(dbPath).writeAsBytes([0]);
      await restrictDatabaseFilePermissions(dbPath); // no sidecars present
    });
  });

  group('encryptionKeyToSqlLiteral', () {
    test('formats 32-byte key as lowercase hex blob literal', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final literal = encryptionKeyToSqlLiteral(key);
      expect(literal, startsWith("x'"));
      expect(literal, endsWith("'"));
      expect(literal.length, 2 + 64 + 1);
      expect(
        literal,
        "x'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'",
      );
    });

    test('pads single-digit bytes', () {
      final key = Uint8List.fromList([0x01, 0x0a, 0xff, 0x00]);
      expect(encryptionKeyToSqlLiteral(key), "x'010aff00'");
    });
  });

  group('RekeyFailedException', () {
    test('toString never embeds the SQL or the encryption key', () {
      const ex = RekeyFailedException(
        cipherChange: 'to-encrypted',
        causeType: 'SqliteException',
      );
      final msg = ex.toString();
      expect(msg, contains('to-encrypted'));
      expect(msg, contains('SqliteException'));
      // No `PRAGMA rekey`, no hex-encoded key, no `x'...'` blob literal.
      expect(msg, isNot(contains('rekey')));
      expect(msg, isNot(contains("x'")));
    });
  });

  group('EncryptionUnavailableException', () {
    test('toString explains the refusal without leaking key material', () {
      const ex = EncryptionUnavailableException();
      final msg = ex.toString();
      expect(msg, contains('SQLite3MultipleCiphers'));
      expect(msg, contains('refusing'));
      expect(msg, isNot(contains("x'")));
    });
  });

  group('openTestDatabase', () {
    test('returns a working in-memory AppDatabase with FKs enabled', () async {
      final db = openTestDatabase();
      try {
        // The DB is readable — verifyDatabaseReadable returns true.
        expect(await verifyDatabaseReadable(db), isTrue);

        // PRAGMA foreign_keys = ON was executed in the setup callback.
        final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
        expect(result.data.values.first, 1);
      } finally {
        await db.close();
      }
    });
  });

  group('rekeyDatabase', () {
    test(
      'wraps underlying SQLite errors in RekeyFailedException (no key leak)',
      () async {
        final db = openTestDatabase();
        await db.close(); // Force the rekey to fail on a dead connection.

        try {
          await rekeyDatabase(
            db,
            Uint8List.fromList(List<int>.generate(32, (i) => i)),
          );
          fail('rekeyDatabase must throw when the underlying DB is dead');
        } on RekeyFailedException catch (e) {
          // Sensitive material must not reach the exception surface.
          expect(e.cipherChange, 'to-encrypted');
          final msg = e.toString();
          expect(msg, isNot(contains("x'")));
          expect(msg, isNot(contains('rekey')));
        }
      },
    );

    test('plaintext-target cipherChange also wraps + scrubs the key', () async {
      final db = openTestDatabase();
      await db.close();
      try {
        await rekeyDatabase(db, null);
        fail('closed connection must not accept a rekey');
      } on RekeyFailedException catch (e) {
        expect(e.cipherChange, 'to-plaintext');
        final msg = e.toString();
        expect(msg, isNot(contains("x'")));
        expect(msg, isNot(contains('rekey')));
      }
    });
  });
}
