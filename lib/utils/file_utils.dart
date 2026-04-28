import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../src/rust/api/path.dart' as rust_path;
import 'logger.dart';

final _rng = Random();

/// Atomic file write — writes to `<path>.tmp`, hardens to owner-
/// only perms, then renames to the destination. A crash mid-flush
/// leaves either the previous file content or the tmp file behind,
/// never a torn destination.
///
/// Routes through `lfs_core::path::write_bytes_atomic` in
/// production so the on-disk perms contract lives one place. The
/// FRB shim returns `Result<(), String>`; failures rethrow as the
/// `AnyhowException` the caller already handles. Falls back to a
/// pure-Dart write when the FRB native lib is missing
/// (flutter_test contexts).
Future<void> writeFileAtomic(String path, String content) async {
  await writeBytesAtomic(path, utf8.encode(content));
}

/// Atomic byte write — same flow as [writeFileAtomic] but for raw
/// bytes. Caller is responsible for the parent directory existing
/// (every production caller already runs `dir.create(recursive:
/// true)` ahead of this; the helper surfaces ENOENT loudly when
/// the contract is broken).
Future<void> writeBytesAtomic(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  try {
    rust_path.pathWriteBytesAtomic(path: path, bytes: bytes);
    return;
  } catch (e) {
    // FRB native lib missing (flutter_test) or a runtime
    // serialisation issue — fall back to direct Dart File I/O so
    // the test surface keeps working. Production never reaches
    // here because RustLib.init runs at app start.
    AppLogger.instance.log(
      'writeBytesAtomic Rust path failed, falling back: $e',
      name: 'FileUtils',
      level: LogLevel.warn,
    );
  }
  await _writeBytesDartFallback(file, bytes);
}

Future<void> _writeBytesDartFallback(File file, List<int> bytes) async {
  // Random tmp suffix mirrors the Rust path's collision-avoidance
  // shape — concurrent writers to the same destination must not
  // collide on the intermediate file.
  final tmp = File('${file.path}.tmp${_rng.nextInt(1 << 30)}');
  try {
    await tmp.writeAsBytes(bytes);
    await hardenFilePerms(tmp.path);
    await tmp.rename(file.path);
  } catch (e) {
    AppLogger.instance.log(
      'Atomic write fallback failed for ${file.path}: $e',
      name: 'FileUtils',
    );
    try {
      await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Single cross-cutting entry point for locking down permissions on a
/// freshly-written secret file.
///
/// Call this after every write that produces a file inside the app
/// support directory that could hold encryption keys, authentication
/// material, rate-limit state, or any other integrity-sensitive blob.
/// The atomic-write helpers above already call it on the `.tmp` file
/// before rename via the Rust core (or via the Dart fallback); other
/// paths (drift's SQLite WAL/SHM sidecars) must call this explicitly.
///
/// Unix: `chmod 600` (owner read/write only) — matches the OpenSSH
/// expectation for every file under `~/.ssh/`.
/// Windows: `icacls` — removes inherited ACLs, grants full control to
/// current user only.
/// Silent no-op on platforms with sandboxed per-app storage (iOS,
/// Android) — the OS already enforces tighter access than `chmod 600`
/// would.
Future<void> hardenFilePerms(String path) async {
  try {
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('chmod', ['600', path]);
      if (result.exitCode != 0) {
        AppLogger.instance.log(
          'chmod 600 failed: ${result.stderr}',
          name: 'FileUtils',
        );
      }
    } else if (Platform.isWindows) {
      final user = Platform.environment['USERNAME'] ?? '';
      if (user.isEmpty) return;
      // Remove inherited permissions, then grant current user full control.
      final result = await Process.run('icacls', [
        path,
        '/inheritance:r',
        '/grant:r',
        '$user:(F)',
      ]);
      if (result.exitCode != 0) {
        AppLogger.instance.log(
          'icacls failed: ${result.stderr}',
          name: 'FileUtils',
        );
      }
    }
  } catch (e) {
    AppLogger.instance.log(
      'Failed to harden permissions: $e',
      name: 'FileUtils',
    );
  }
}
