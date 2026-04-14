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
