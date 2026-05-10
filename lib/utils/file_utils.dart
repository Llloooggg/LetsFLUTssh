import 'dart:convert';
import 'dart:io';

import '../src/rust/api/path.dart' as rust_path;
import 'logger.dart';

/// Atomic file write — writes to `<path>.tmp`, hardens to owner-
/// only perms, then renames to the destination. A crash mid-flush
/// leaves either the previous file content or the tmp file behind,
/// never a torn destination.
///
/// Routes through `lfs_core::path::write_bytes_atomic`. The FRB
/// shim returns `Result<(), String>`; failures rethrow as the
/// `AnyhowException` the caller already handles.
Future<void> writeFileAtomic(String path, String content) async {
  await writeBytesAtomic(path, utf8.encode(content));
}

/// Atomic byte write — same flow as [writeFileAtomic] but for raw
/// bytes. Caller is responsible for the parent directory existing
/// (every production caller already runs `dir.create(recursive:
/// true)` ahead of this; the helper surfaces ENOENT loudly when
/// the contract is broken).
Future<void> writeBytesAtomic(String path, List<int> bytes) async {
  await File(path).parent.create(recursive: true);
  rust_path.pathWriteBytesAtomic(path: path, bytes: bytes);
}

/// Single cross-cutting entry point for locking down permissions on a
/// freshly-written secret file.
///
/// Call this after every write that produces a file inside the app
/// support directory that could hold encryption keys, authentication
/// material, rate-limit state, or any other integrity-sensitive blob.
/// The atomic-write helpers above already call it on the `.tmp` file
/// before rename via the Rust core; other paths (rusqlite/SQLCipher
/// `letsflutssh.db-wal` / `.db-shm` sidecars) must call this
/// explicitly.
///
/// Unix: `chmod 600` (owner read/write only) — matches the OpenSSH
/// expectation for every file under `~/.ssh/`.
/// Windows: `icacls` — removes inherited ACLs, grants full control to
/// current user only.
/// Silent no-op on platforms with sandboxed per-app storage (iOS,
/// Android) — the OS already enforces tighter access than `chmod 600`
/// would.
///
/// Routes through `lfs_core::path::harden_file_perms` — the chmod /
/// icacls grammar lives in Rust. Best-effort: a chmod failure must
/// never break a write.
Future<void> hardenFilePerms(String path) async {
  try {
    await rust_path.pathHardenFilePerms(path: path);
  } catch (e) {
    AppLogger.instance.log(
      'Failed to harden permissions: $e',
      name: 'FileUtils',
    );
  }
}
