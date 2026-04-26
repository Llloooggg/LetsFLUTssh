import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/app.dart' as rust_app;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Path of the Rust-owned sqlite file. Sits alongside drift's
/// `letsflutssh.db` while both engines coexist — names diverge so
/// the two cipher families (drift's MC ChaCha20 vs rusqlite's
/// SQLCipher AES-256-CBC) never share a wire format.
const _rustDbFileName = 'lfs_core.db';

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
/// Whether `lfs_core.db` already exists on disk. Used by the
/// first-launch path to distinguish "fresh install, no data" from
/// "existing install — unlock the previous key".
Future<bool> lfsCoreDbExists() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _rustDbFileName)).exists();
  } catch (e) {
    AppLogger.instance.log(
      'lfs_core.db existence probe failed: $e',
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
      'lfs_core.db readability probe failed: ${e.runtimeType}',
      name: 'RustDbInit',
    );
    return false;
  }
}

Future<void> ensureRustDbOpen({Uint8List? key}) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, _rustDbFileName);
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await hardenFilePerms(path);
    await rust_app.dbInit(
      path: path,
      key: key == null ? const <int>[] : List<int>.from(key),
    );
    AppLogger.instance.log(
      'Rust DB ready (encrypted=${key != null})',
      name: 'RustDbInit',
    );
  } catch (e, st) {
    AppLogger.instance.log(
      'Rust DB init failed: ${e.runtimeType}',
      name: 'RustDbInit',
      level: LogLevel.warn,
      error: e,
      stackTrace: st,
    );
  }
}
