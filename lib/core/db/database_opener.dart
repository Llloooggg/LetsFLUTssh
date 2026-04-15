import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';
import 'database.dart';

const _dbFileName = 'letsflutssh.db';

/// Whether the database file already exists on disk.
///
/// Returns false on first launch (before any DB has been created).
Future<bool> databaseFileExists() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, _dbFileName));
  return file.exists();
}

/// Open the app database with optional encryption.
///
/// [encryptionKey] — 32-byte key for SQLite3MultipleCiphers.
/// Pass `null` for plaintext mode.
AppDatabase openDatabase({Uint8List? encryptionKey}) {
  return AppDatabase(_openConnection(encryptionKey: encryptionKey));
}

/// Convert a 32-byte key to the hex-blob literal SQLite3MultipleCiphers
/// expects in `PRAGMA key` / `PRAGMA rekey` statements (`x'...'`).
String encryptionKeyToSqlLiteral(Uint8List key) {
  final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return "x'$hex'";
}

/// Re-encrypt the already-open database [db] with a new [newKey], or convert
/// it to plaintext when [newKey] is null. Uses SQLite3MultipleCiphers
/// `PRAGMA rekey` — rewrites every page under a single transaction at the
/// storage layer, so the only visible failure modes are disk-full or a
/// cipher implementation error (both reported by drift as an execute error).
///
/// Caller is responsible for updating `securityStateProvider` and moving the
/// key in/out of the relevant storage backend (file / keychain / master
/// password wrapper); this function only touches the DB pages.
Future<void> rekeyDatabase(AppDatabase db, Uint8List? newKey) async {
  final literal = newKey == null
      ? "''"
      : '"${encryptionKeyToSqlLiteral(newKey)}"';
  await db.customStatement('PRAGMA rekey = $literal');
  AppLogger.instance.log(
    'Database rekeyed (newKey=${newKey == null ? "plaintext" : "encrypted"})',
    name: 'DatabaseOpener',
  );
}

/// Open an in-memory database for tests (no encryption, no file I/O).
AppDatabase openTestDatabase() {
  return AppDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );
}

LazyDatabase _openConnection({Uint8List? encryptionKey}) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _dbFileName));

    AppLogger.instance.log(
      'Opening database: ${file.path}, '
      'encrypted=${encryptionKey != null}',
      name: 'DatabaseOpener',
    );

    return NativeDatabase(
      file,
      setup: (db) {
        if (encryptionKey != null) {
          final hex = encryptionKey
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          db.execute("PRAGMA key = \"x'$hex'\"");

          // Verify encryption is active
          final cipher = db.select('PRAGMA cipher');
          if (cipher.isEmpty) {
            AppLogger.instance.log(
              'WARNING: SQLite3MultipleCiphers not available',
              name: 'DatabaseOpener',
            );
          }
        }
        db.execute('PRAGMA foreign_keys = ON');
      },
    );
  });
}
