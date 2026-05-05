import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/app.dart' as rust_app;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Path of the Rust-owned sqlite file. Reuses the same filename
/// drift wrote to before the rusqlite port (`letsflutssh.db`) so
/// a fresh install lands at a familiar path. Upgrades from a
/// pre-rust-port build hit a cipher-family mismatch (drift's MC
/// ChaCha20 vs rusqlite's SQLCipher AES-256-CBC) when SQLCipher
/// tries to open the existing file — "file is not a database"
/// surfaces through `verifyRustDbReadable` → `DbCorruptDialog`,
/// the user picks Reset, the file is wiped, fresh setup proceeds.
/// Conscious tradeoff: no on-the-fly migration code, drift/MC and
/// rusqlite/SQLCipher share the file slot, the corrupt-DB dialog
/// is the upgrade UX. Users who want to preserve pre-port data
/// roll back to v7.3.2, export to `.lfs`, upgrade, import.
const _rustDbFileName = 'letsflutssh.db';

/// Open the Rust-owned sqlite handle behind the FRB boundary using
/// the same master key Dart just unlocked drift with. Idempotent on
/// the same (path, key) pair — safe to call on every unlock.
///
/// `key` may be null in plaintext mode; the Rust side accepts an
/// empty byte slice and skips the SQLCipher PRAGMA.
///
/// Failures are logged and swallowed: a missing Rust DB only means
/// the FRB-backed DAOs are unusable for this run, not that the app
/// can't boot. Drift-backed legacy paths still operate.
/// Whether `letsflutssh.db` already exists on disk. Used by the
/// first-launch path to distinguish "fresh install, no data" from
/// "existing install — unlock the previous key".
Future<bool> lfsCoreDbExists() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _rustDbFileName)).exists();
  } catch (e) {
    AppLogger.instance.log(
      'letsflutssh.db existence probe failed: $e',
      name: 'RustDbInit',
      level: LogLevel.warn,
    );
    return false;
  }
}

/// Cheap integrity probe — runs a `SELECT count(*) FROM sqlite_master`
/// against the running Rust DB. Returns false when SQLCipher rejects
/// the master key (header decrypt fails) or when the FRB call itself
/// errors out (no native lib in unit tests). Mirrors the contract of
/// the legacy `verifyDatabaseReadable`.
Future<bool> verifyRustDbReadable() async {
  try {
    await rust_app.dbSchemaObjectCount();
    return true;
  } catch (e) {
    AppLogger.instance.log(
      'letsflutssh.db readability probe failed: ${e.runtimeType}',
      name: 'RustDbInit',
    );
    return false;
  }
}

/// Open the Rust-owned sqlite handle.
///
/// At most one of [key] or [secretId] may be provided:
/// * [key] — legacy bytes-on-Dart-heap path. Bytes cross FRB once.
/// * [secretId] — SecretRef path. Pulls bytes from the Rust-side
///   `SecretStore` entry that was previously staged via
///   `cryptoAesGcmRandomKeyToSecret`; the bytes never touch the
///   Dart heap. The `secrets_take` is atomic — after this call the
///   SecretStore entry is empty.
///
/// Both null = plaintext (unencrypted) path.
Future<void> ensureRustDbOpen({Uint8List? key, String? secretId}) async {
  assert(
    key == null || secretId == null,
    'pass either key or secretId, not both',
  );
  final sw = Stopwatch()..start();
  void mark(String phase) {
    AppLogger.instance.log(
      'rust db open phase=$phase elapsed=${sw.elapsedMilliseconds}ms',
      name: 'RustDbInit',
    );
  }

  try {
    final dir = await getApplicationSupportDirectory();
    mark('support_dir');
    final path = p.join(dir.path, _rustDbFileName);
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    mark('file_create');
    await hardenFilePerms(path);
    mark('harden_perms');
    if (secretId != null) {
      await rust_app.dbInitFromSecret(path: path, secretId: secretId);
    } else {
      await rust_app.dbInit(
        path: path,
        key: key == null ? const <int>[] : List<int>.from(key),
      );
    }
    mark('db_init');
    AppLogger.instance.log(
      'Rust DB ready (encrypted=${key != null || secretId != null})',
      name: 'RustDbInit',
    );
  } catch (e, st) {
    // Log + swallow on purpose: callers up the chain (`bootstrap`
    // → `handleCorruption` via `verifyRustDbReadable`) probe DB
    // readability AFTER `_injectDatabase` returns and route a
    // failed probe through `DbCorruptDialog`. Rethrowing here
    // would propagate past `_injectDatabase` → `_initSecurity` →
    // `bootstrap` and land as an unhandled future on the widget
    // tree (red-screen / silent crash) because none of those
    // intermediate frames currently catch. The catch + log keeps
    // the failure on the existing recovery rail without bypassing
    // it — and the post-`_initSecurity` `verifyReadable` probe
    // already detects the broken state regardless of whether
    // `dbInit` returned cleanly or not (a half-open state with no
    // SQLCipher attach behind it returns false from the probe
    // just like an attach-failed state).
    AppLogger.instance.log(
      'Rust DB init failed: ${e.runtimeType}',
      name: 'RustDbInit',
      level: LogLevel.warn,
      error: e,
      stackTrace: st,
    );
  }
}
