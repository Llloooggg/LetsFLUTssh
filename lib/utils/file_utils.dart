import 'dart:io';
import 'dart:math';

import 'logger.dart';

final _rng = Random();

/// Atomic file write: writes to a temporary file, restricts permissions,
/// then renames to the target path. Prevents data corruption on crash.
Future<void> writeFileAtomic(String path, String content) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final tmp = File('$path.tmp${_rng.nextInt(1 << 30)}');
  try {
    await tmp.writeAsString(content);
    await hardenFilePerms(tmp.path);
    await tmp.rename(path);
  } catch (e) {
    AppLogger.instance.log(
      'Atomic write failed for $path: $e',
      name: 'FileUtils',
    );
    try {
      await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Atomic byte write: same pattern as [writeFileAtomic] but for raw bytes.
Future<void> writeBytesAtomic(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final tmp = File('$path.tmp${_rng.nextInt(1 << 30)}');
  try {
    await tmp.writeAsBytes(bytes);
    await hardenFilePerms(tmp.path);
    await tmp.rename(path);
  } catch (e) {
    AppLogger.instance.log(
      'Atomic byte write failed for $path: $e',
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
/// before rename; other paths (direct `File.writeAsBytes`, drift's
/// SQLite WAL/SHM sidecars, keychain marker files) must call this
/// explicitly.
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

/// Deprecated alias kept for one release window so existing call
/// sites keep compiling while they are migrated over. Delete after
/// the migration is complete.
@Deprecated('Use hardenFilePerms — single cross-cutting entry point.')
Future<void> restrictFilePermissions(String path) => hardenFilePerms(path);
