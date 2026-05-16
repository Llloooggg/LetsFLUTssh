import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/conflict_resolver.dart';
import '../../core/transfer/unique_name.dart';
import '../../providers/transfer_provider.dart';
import '../../src/rust/api/local_fs.dart' as rust_local_fs;
import '../../utils/logger.dart';
import 'file_browser_controller.dart';

/// Shared upload/download helpers used by both desktop and mobile file
/// browsers. Single-file transfers enqueue one Rust queue task; directory
/// transfers walk locally / over SFTP and enqueue a fresh Rust task per
/// leaf file. The Rust queue owns scheduling, chunked streaming + per-task
/// progress events; the Dart panels render off the same shared snapshot
/// stream regardless of how the task was enqueued.
class TransferHelpers {
  TransferHelpers._();

  /// Enqueue an upload for [entry] to the remote [remoteDirPath].
  ///
  /// Returns `true` if at least one task was enqueued, `false` if the
  /// transfer was skipped (conflict → skip) or cancelled (conflict →
  /// cancel) before any work landed. Dir entries bypass the conflict
  /// check at the top level — per-file conflicts inside the walker
  /// still resolve via [conflictResolver].
  static Future<bool> enqueueUpload({
    required TransfersNotifier manager,
    required FileSystem remoteFs,
    required String connectionId,
    required FileEntry entry,
    required String remoteDirPath,
    required FilePaneController? remoteCtrl,
    BatchConflictResolver? conflictResolver,
  }) async {
    final remotePath = p.posix.join(remoteDirPath, entry.name);

    if (entry.isDir) {
      final enqueued = await _enqueueUploadDir(
        manager: manager,
        remoteFs: remoteFs,
        connectionId: connectionId,
        localDir: entry.path,
        remoteDir: remotePath,
        conflictResolver: conflictResolver,
      );
      if (enqueued > 0) {
        unawaited(_refreshAfterDelay(remoteCtrl));
      }
      return enqueued > 0;
    }

    String? resolvedRemote = remotePath;
    if (conflictResolver != null) {
      resolvedRemote = await _resolveUploadConflict(
        remoteFs: remoteFs,
        targetPath: remotePath,
        resolver: conflictResolver,
      );
      if (resolvedRemote == null) return false;
    }
    await manager.enqueueUpload(
      connectionId: connectionId,
      name: p.posix.basename(resolvedRemote),
      localPath: entry.path,
      remotePath: resolvedRemote,
      sizeBytes: entry.size,
    );
    unawaited(_refreshAfterDelay(remoteCtrl));
    return true;
  }

  /// Enqueue a download for [entry] to the local [localDirPath].
  static Future<bool> enqueueDownload({
    required TransfersNotifier manager,
    required FileSystem remoteFs,
    required String connectionId,
    required FileEntry entry,
    required String localDirPath,
    required FilePaneController? localCtrl,
    BatchConflictResolver? conflictResolver,
  }) async {
    final localPath = p.join(localDirPath, entry.name);

    if (entry.isDir) {
      final enqueued = await _enqueueDownloadDir(
        manager: manager,
        remoteFs: remoteFs,
        connectionId: connectionId,
        remoteDir: entry.path,
        localDir: localPath,
        conflictResolver: conflictResolver,
      );
      if (enqueued > 0) {
        unawaited(_refreshAfterDelay(localCtrl));
      }
      return enqueued > 0;
    }

    String? resolvedLocal = localPath;
    if (conflictResolver != null) {
      resolvedLocal = await _resolveDownloadConflict(
        targetPath: localPath,
        resolver: conflictResolver,
      );
      if (resolvedLocal == null) return false;
    }
    await manager.enqueueDownload(
      connectionId: connectionId,
      name: p.basename(resolvedLocal),
      remotePath: entry.path,
      localPath: resolvedLocal,
      sizeBytes: entry.size,
    );
    unawaited(_refreshAfterDelay(localCtrl));
    return true;
  }

  /// Walk [localDir] recursively and enqueue an upload task per leaf
  /// file. Skips symlinks (we don't follow them into arbitrary targets)
  /// and conflict-skipped paths. Returns the total enqueue count.
  /// Routes the directory listing through `lfs_core::fs::local::list`
  /// so `dart:io` never participates in upload enumeration.
  static Future<int> _enqueueUploadDir({
    required TransfersNotifier manager,
    required FileSystem remoteFs,
    required String connectionId,
    required String localDir,
    required String remoteDir,
    required BatchConflictResolver? conflictResolver,
  }) async {
    var enqueued = 0;
    try {
      await remoteFs.mkdir(remoteDir);
    } catch (_) {
      // Already exists or other transient — per-file upserts will fail
      // if the dir is genuinely unwritable; let those surface there.
    }
    final children = await rust_local_fs.localFsList(path: localDir);
    for (final child in children) {
      // Symlinks are surfaced by Rust's `list` with `isSymlink: true`;
      // skip them so we never follow into arbitrary targets.
      if (child.isSymlink) continue;
      final remoteChild = p.posix.join(remoteDir, child.name);
      if (child.isDir) {
        enqueued += await _enqueueUploadDir(
          manager: manager,
          remoteFs: remoteFs,
          connectionId: connectionId,
          localDir: child.path,
          remoteDir: remoteChild,
          conflictResolver: conflictResolver,
        );
        continue;
      }
      String? resolved = remoteChild;
      if (conflictResolver != null) {
        resolved = await _resolveUploadConflict(
          remoteFs: remoteFs,
          targetPath: remoteChild,
          resolver: conflictResolver,
        );
        if (resolved == null) continue;
      }
      await manager.enqueueUpload(
        connectionId: connectionId,
        name: p.posix.basename(resolved),
        localPath: child.path,
        remotePath: resolved,
        sizeBytes: child.size.toInt(),
      );
      enqueued++;
    }
    return enqueued;
  }

  /// Walk [remoteDir] over SFTP and enqueue a download task per leaf
  /// file. Mirrors [_enqueueUploadDir] in shape.
  static Future<int> _enqueueDownloadDir({
    required TransfersNotifier manager,
    required FileSystem remoteFs,
    required String connectionId,
    required String remoteDir,
    required String localDir,
    required BatchConflictResolver? conflictResolver,
  }) async {
    var enqueued = 0;
    await rust_local_fs.localFsMkdir(path: localDir);
    final entries = await remoteFs.list(remoteDir);
    for (final remoteEntry in entries) {
      final base = remoteEntry.name;
      if (!_isSafeRemoteEntryName(base)) {
        // SFTP server-supplied names are untrusted bytes — a hostile
        // remote returning `name: "../../../etc/cron.d/x"` (or a
        // backslash on Windows, an embedded NUL anywhere, or a leading
        // `.` traversal segment) used to flow straight into `p.join`,
        // which does NOT normalise — the resulting `localPath` could
        // land outside the user-chosen download directory. Reject the
        // entry instead. See P7.2 in `docs/_audit/REPORT.md`.
        AppLogger.instance.log(
          'Skipping remote entry with unsafe name <name> in $remoteDir',
          name: 'Transfer',
          level: LogLevel.warn,
        );
        continue;
      }
      final remoteChild = p.posix.join(remoteDir, base);
      final localChild = p.join(localDir, base);
      if (remoteEntry.isDir) {
        enqueued += await _enqueueDownloadDir(
          manager: manager,
          remoteFs: remoteFs,
          connectionId: connectionId,
          remoteDir: remoteChild,
          localDir: localChild,
          conflictResolver: conflictResolver,
        );
      } else {
        String? resolved = localChild;
        if (conflictResolver != null) {
          resolved = await _resolveDownloadConflict(
            targetPath: localChild,
            resolver: conflictResolver,
          );
          if (resolved == null) continue;
        }
        await manager.enqueueDownload(
          connectionId: connectionId,
          name: p.basename(resolved),
          remotePath: remoteChild,
          localPath: resolved,
          sizeBytes: remoteEntry.size,
        );
        enqueued++;
      }
    }
    return enqueued;
  }

  /// Refresh the file pane a moment after enqueue so the UI catches
  /// up once the Rust queue starts the first task. The Rust executor
  /// re-creates parent dirs / writes the file; the pane needs a
  /// re-list to see them. Best-effort — no-op when the pane is null.
  static Future<void> _refreshAfterDelay(FilePaneController? ctrl) async {
    if (ctrl == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    ctrl.refresh();
  }

  /// Returns the effective remote path to upload to, or `null` when
  /// the user chose to skip or cancel. When the user picks "keep
  /// both", the returned path is a renamed sibling.
  static Future<String?> _resolveUploadConflict({
    required FileSystem remoteFs,
    required String targetPath,
    required BatchConflictResolver resolver,
  }) async {
    if (!await remoteFs.exists(targetPath)) return targetPath;
    final action = await resolver.resolve(targetPath, isRemote: true);
    switch (action) {
      case ConflictAction.skip:
      case ConflictAction.cancel:
        return null;
      case ConflictAction.keepBoth:
        return uniqueSiblingName(targetPath, remoteFs.exists, isPosix: true);
      case ConflictAction.replace:
        return targetPath;
    }
  }

  static Future<String?> _resolveDownloadConflict({
    required String targetPath,
    required BatchConflictResolver resolver,
  }) async {
    final snapshot = await _snapshotLocal(targetPath);
    if (snapshot == null) return targetPath;
    if (snapshot.isSymlink) {
      AppLogger.instance.log(
        'Refusing download to pre-existing symlink: $targetPath',
        name: 'Transfer',
      );
      return null;
    }
    final action = await resolver.resolve(targetPath, isRemote: false);
    switch (action) {
      case ConflictAction.skip:
      case ConflictAction.cancel:
        return null;
      case ConflictAction.keepBoth:
        return uniqueSiblingName(targetPath, _localExists);
      case ConflictAction.replace:
        final current = await _snapshotLocal(targetPath);
        if (!_localSnapshotsMatch(snapshot, current)) {
          AppLogger.instance.log(
            'Local target changed between probe and confirm — aborting: $targetPath',
            name: 'Transfer',
          );
          return null;
        }
        return targetPath;
    }
  }

  static Future<bool> _localExists(String path) async {
    final entry = await rust_local_fs.localFsSymlinkStat(path: path);
    return entry != null;
  }

  /// Reject SFTP-supplied filenames that could escape the user-chosen
  /// download directory after `p.join`. `p.join` concatenates without
  /// normalising — a name carrying path separators, traversal
  /// segments, or NUL bytes lands the file at an attacker-chosen
  /// destination. Single dots are filesystem self-references and
  /// would mostly no-op, but rejecting them keeps the predicate
  /// simple and the file pane's listing intuitive.
  ///
  /// Visible-for-testing so the regression test can pin every
  /// rejection branch (separators, dotdot prefix, embedded NUL,
  /// empty names, surrounding whitespace).
  @visibleForTesting
  static bool isSafeRemoteEntryName(String name) =>
      _isSafeRemoteEntryName(name);

  static bool _isSafeRemoteEntryName(String name) {
    if (name.isEmpty) return false;
    if (name == '.' || name == '..') return false;
    // Reject any path-separator embedded in the name. Both POSIX and
    // Windows separators rejected so a Windows-shaped server name
    // cannot drift through the POSIX-only check.
    if (name.contains('/') || name.contains('\\')) return false;
    // Reject embedded NUL — most filesystems treat these as
    // terminators and would silently truncate the path.
    if (name.contains(' ')) return false;
    // Trim test catches names that round-trip through whitespace
    // canonicalisation differently across platforms.
    if (name.trim().isEmpty) return false;
    return true;
  }

  /// Probe the local path without following symlinks. The probe
  /// is the one feeding the change-detected `replace` path: we
  /// stat the target before the user confirms, stat it again
  /// after, and abort when size / mtime / type drifted in
  /// between. Symlinks are surfaced as a distinct snapshot so
  /// the caller can refuse to overwrite them.
  static Future<_LocalSnapshot?> _snapshotLocal(String path) async {
    rust_local_fs.DbLocalFileEntry? entry;
    try {
      entry = await rust_local_fs.localFsSymlinkStat(path: path);
    } catch (_) {
      return const _LocalSnapshot.unknown();
    }
    if (entry == null) return null;
    if (entry.isSymlink) return const _LocalSnapshot.symlink();
    return _LocalSnapshot(
      isDir: entry.isDir,
      size: entry.size.toInt(),
      modifiedMs: entry.modTimeUnixMs.toInt(),
    );
  }

  static bool _localSnapshotsMatch(_LocalSnapshot a, _LocalSnapshot? b) {
    if (b == null) return false;
    if (a.isSymlink || b.isSymlink) return false;
    return a.isDir == b.isDir &&
        a.size == b.size &&
        a.modifiedMs == b.modifiedMs;
  }
}

class _LocalSnapshot {
  final bool? isDir;
  final int? size;
  final int? modifiedMs;
  final bool isSymlink;

  const _LocalSnapshot({
    required this.isDir,
    required this.size,
    required this.modifiedMs,
  }) : isSymlink = false;

  const _LocalSnapshot.symlink()
    : isDir = null,
      size = null,
      modifiedMs = null,
      isSymlink = true;

  const _LocalSnapshot.unknown()
    : isDir = null,
      size = null,
      modifiedMs = null,
      isSymlink = false;
}
