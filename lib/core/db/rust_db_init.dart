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
