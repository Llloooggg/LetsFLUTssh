import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'database.dart';

const _dbFileName = 'letsflutssh.db';

/// SQLite sidecar files that may sit next to the main DB. Created lazily by
/// SQLite during write transactions / WAL mode; we restrict their permissions
/// on every open in case they were left behind by a crash.
const _dbSidecarSuffixes = ['-journal', '-wal', '-shm'];

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

/// Cheap integrity probe. Runs a trivial `SELECT` against the newly
/// opened [db]; returns true when the file is a valid SQLite database
/// under the current cipher key, false when SQLite rejects it as
/// corrupt / wrong-key / "file is not a database".
///
/// The probe is required because a half-migrated install can carry a
/// stale `config.json` tier marker that no longer matches the DB
/// cipher on disk — e.g. `security_tier: plaintext` on a file still
/// encrypted from the pre-tier era. Without this probe the first
/// drift query (usually `PRAGMA user_version` during migration)
/// throws from an async gap and stack-traces into the error boundary.
Future<bool> verifyDatabaseReadable(AppDatabase db) async {
  try {
    await db.customSelect('SELECT 1').get();
    return true;
  } catch (e) {
    AppLogger.instance.log(
      'Database readability probe failed: ${e.runtimeType}',
      name: 'DatabaseOpener',
    );
    return false;
  }
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
/// On any underlying failure we strip the SQL fragment from the rethrown
/// exception so the hex-encoded key cannot leak into log files / crash
/// reporters via `error.toString()`.
///
/// Caller is responsible for updating `securityStateProvider` and moving the
/// key in/out of the relevant storage backend (file / keychain / master
/// password wrapper); this function only touches the DB pages.
Future<void> rekeyDatabase(AppDatabase db, Uint8List? newKey) async {
  final literal = newKey == null
      ? "''"
      : '"${encryptionKeyToSqlLiteral(newKey)}"';
  try {
    await db.customStatement('PRAGMA rekey = $literal');
  } catch (e) {
    // Drift's exception messages embed the failing SQL verbatim, which in
    // this case includes the hex-encoded key. Wrap into a generic error so
    // nothing downstream (logger, crash reporter) ever sees the literal.
    throw RekeyFailedException(
      cipherChange: newKey == null ? 'to-plaintext' : 'to-encrypted',
      causeType: e.runtimeType.toString(),
    );
  }
  AppLogger.instance.log(
    'Database rekeyed (newKey=${newKey == null ? "plaintext" : "encrypted"})',
    name: 'DatabaseOpener',
  );
}

/// Thrown when `PRAGMA rekey` fails. Deliberately carries no SQL or key
/// material — only the high-level cipher transition and the original
/// runtime type so downstream logs can hint at root cause without leaking
/// the secret.
class RekeyFailedException implements Exception {
  final String cipherChange;
  final String causeType;
  const RekeyFailedException({
    required this.cipherChange,
    required this.causeType,
  });

  @override
  String toString() =>
      'RekeyFailedException(cipherChange: $cipherChange, cause: $causeType)';
}

/// Restrict the encrypted DB file (and any SQLite sidecars) to owner-only
/// access. Idempotent: safe to call on every open. Logs and continues on
/// failure — losing the chmod is worse than refusing to start.
Future<void> restrictDatabaseFilePermissions(String dbPath) async {
  await hardenFilePerms(dbPath);
  for (final suffix in _dbSidecarSuffixes) {
    final sidecar = File('$dbPath$suffix');
    if (await sidecar.exists()) {
      await hardenFilePerms(sidecar.path);
    }
  }
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

    // Pre-create the file so we can lock down permissions BEFORE SQLite
    // writes the first encrypted page. SQLite preserves existing mode.
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await restrictDatabaseFilePermissions(file.path);

    return NativeDatabase(
      file,
      setup: (db) {
        if (encryptionKey != null) {
          final hex = encryptionKey
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          db.execute("PRAGMA key = \"x'$hex'\"");

          // Verify encryption is active. If the multi-cipher extension was
          // not statically linked into this build, the PRAGMA returns an
          // empty result and SQLite silently keeps the key-but-no-cipher
          // state — meaning every subsequent write goes to disk in
          // plaintext while the caller still believes it's encrypted.
          // This is exactly the kind of silent downgrade that turns a
          // master-password setup into false advertising. Hard-fail.
          final cipher = db.select('PRAGMA cipher');
          if (cipher.isEmpty) {
            throw const EncryptionUnavailableException();
          }
        }
        db.execute('PRAGMA foreign_keys = ON');
        // Re-harden permissions after SQLite has had a chance to create
        // the WAL / SHM sidecars. The pre-open call above covered the
        // main DB file, but in WAL journal mode SQLite creates
        // `-wal` / `-shm` lazily at first write; if we stop at the
        // pre-open harden those sidecars inherit the default 0644
        // umask and leak the encrypted WAL pages to a same-UID reader.
        // Deliberately fire-and-forget: a failing chmod is logged by
        // the helper and must not block database open.
        unawaited(restrictDatabaseFilePermissions(file.path));
      },
    );
  });
}

/// Thrown when an encryption key was supplied but the underlying SQLite
/// build does not actually support encryption (the SQLite3MultipleCiphers
/// extension is missing). Refusing to open is the only safe outcome —
/// continuing would silently store secrets in plaintext.
class EncryptionUnavailableException implements Exception {
  const EncryptionUnavailableException();

  @override
  String toString() =>
      'EncryptionUnavailableException: SQLite3MultipleCiphers extension '
      'is not linked into this build; refusing to open the database with '
      'a key that would otherwise be silently ignored.';
}
