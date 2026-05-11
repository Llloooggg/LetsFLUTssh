import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/app.dart' as rust_app;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// On-disk filename of the SQLCipher-encrypted sqlite database.
/// **Never bump or rename.** A fresh-install user expects this
/// path, and an existing user upgrading from any other build that
/// also wrote `letsflutssh.db` (under any cipher family) opens it
/// here — a header-decrypt mismatch surfaces through
/// `verifyRustDbReadable` → `DbCorruptDialog` so the user can
/// reset and re-import from `.lfs` rather than silently losing
/// the file. The upgrade path is intentionally the corrupt-DB
/// dialog, not on-the-fly cipher conversion: a fork of cipher
/// translation logic would be a permanent maintenance liability
/// for one-time migration plumbing.
const _rustDbFileName = 'letsflutssh.db';

/// Open the Rust-owned sqlite handle behind the FRB boundary using
/// the master key the unlock orchestrator just produced. Idempotent
/// on the same (path, key) pair — safe to call on every unlock.
///
/// `key` may be null in plaintext mode; the Rust side accepts an
/// empty byte slice and skips the SQLCipher PRAGMA.
///
/// Failures are logged and swallowed: a missing Rust DB only means
/// the FRB-backed DAOs are unusable for this run. Recovery routes
/// through the post-init `verifyRustDbReadable` probe + the
/// DB-corruption dialog rather than throwing here.
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
/// errors out (no native lib in unit tests). Used as the "DB really
/// readable?" gate after every unlock + re-open before sessions /
/// workspace bootstrap.
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
/// * [key] — bytes-on-Dart-heap path. Bytes cross FRB once.
///   Use only on the freshly-typed-secret path (unlock dialog
///   submit) where the bytes are already in Dart memory.
/// * [secretId] — SecretRef path. Pulls bytes from the Rust-side
///   `SecretStore` entry staged by `cryptoAesGcmRandomKeyToSecret`
///   / the master-password derive shim / the keychain read shim;
///   the bytes never touch the Dart heap. Atomic: after this call
///   the SecretStore entry is empty (or, on success, renamed to
///   `kActiveDbKeySecretId` so downstream consumers read from the
///   canonical slot).
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
    // `dbInit` / `dbInitFromSecret` route through
    // `lfs_core::db::Connection::open` which mkdir's the parent
    // directory and lets SQLite create the file itself; the Rust
    // path is the single owner of the on-disk handle.
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
