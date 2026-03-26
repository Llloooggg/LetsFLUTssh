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
    restrictFilePermissions(tmp.path);
    await tmp.rename(path);
  } catch (_) {
    try { await tmp.delete(); } catch (_) {}
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
    restrictFilePermissions(tmp.path);
    await tmp.rename(path);
  } catch (_) {
    try { await tmp.delete(); } catch (_) {}
    rethrow;
  }
}

/// Set file permissions to owner-only (0600) on Unix systems.
/// No-op on Windows.
void restrictFilePermissions(String path) {
  if (Platform.isLinux || Platform.isMacOS) {
    try {
      final result = Process.runSync('chmod', ['600', path]);
      if (result.exitCode != 0) {
        AppLogger.instance
            .log('chmod 600 failed: ${result.stderr}', name: 'FileUtils');
      }
    } catch (e) {
      AppLogger.instance
          .log('Failed to restrict permissions: $e', name: 'FileUtils');
    }
  }
}
