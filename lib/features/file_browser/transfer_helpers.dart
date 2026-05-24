import 'dart:async';

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

  /// Enqueue an upload task per leaf file under [localDir]. The
  /// recursive walk — symlink-skip + per-segment name validation —
  /// runs in one `lfs_core::fs::local::flat_walk_files` FRB call;
  /// Dart only enqueues from the returned flat list and resolves
  /// per-file conflicts (the conflict UI stays Dart). Returns the
  /// total enqueue count.
  static Future<int> _enqueueUploadDir({
    required TransfersNotifier manager,
    required FileSystem remoteFs,
    required String connectionId,
    required String localDir,
    required String remoteDir,
    required BatchConflictResolver? conflictResolver,
  }) async {
    final leaves = await rust_local_fs.localFsFlatWalkFiles(
      root: localDir,
      maxDepth: _maxWalkDepth,
    );
    var enqueued = 0;
    final createdDirs = <String>{};
    for (final leaf in leaves) {
      final localPath = p.join(localDir, _toNative(leaf.relPath));
      final remoteChild = p.posix.join(remoteDir, leaf.relPath);
      // Recreate the remote parent chain once per distinct directory
      // before its first file lands. A flat walk loses the per-level
      // mkdir the recursion used to do, so derive the parent from the
      // child path and mkdir it idempotently (errors are transient —
      // the upload upsert surfaces a genuinely unwritable dir).
      final remoteParent = p.posix.dirname(remoteChild);
      if (createdDirs.add(remoteParent)) {
        try {
          await remoteFs.mkdir(remoteParent);
        } catch (_) {
          // Already exists or transient — per-file upload surfaces a
          // real failure.
        }
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
        localPath: localPath,
        remotePath: resolved,
        sizeBytes: leaf.size.toInt(),
      );
      enqueued++;
    }
    return enqueued;
  }

  /// Enqueue a download task per leaf file under [remoteDir]. The
  /// recursive SFTP walk — symlink-skip + server-name validation —
  /// runs in one `Sftp::flat_walk_files` FRB call; Dart only enqueues
  /// from the returned flat list and resolves per-file conflicts.
  /// Mirrors [_enqueueUploadDir] in shape.
  static Future<int> _enqueueDownloadDir({
    required TransfersNotifier manager,
    required FileSystem remoteFs,
    required String connectionId,
    required String remoteDir,
    required String localDir,
    required BatchConflictResolver? conflictResolver,
  }) async {
    final leaves = await remoteFs.flatWalkFiles(
      remoteDir,
      maxDepth: _maxWalkDepth,
    );
    var enqueued = 0;
    final createdDirs = <String>{};
    for (final leaf in leaves) {
      final remoteChild = p.posix.join(remoteDir, leaf.relPath);
      final localChild = p.join(localDir, _toNative(leaf.relPath));
      // Recreate the local parent chain once per distinct directory.
      final localParent = p.dirname(localChild);
      if (createdDirs.add(localParent)) {
        await rust_local_fs.localFsMkdir(path: localParent);
      }
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
        sizeBytes: leaf.size,
      );
      enqueued++;
    }
    return enqueued;
  }

  /// Max directory recursion depth for the flat walks — matches the
  /// `dirSize` cap so a cyclic tree (junction loop / symlinked dir
  /// the server presents as a directory) can't drive an unbounded
  /// walk. The Rust walkers stop descending past this rather than
  /// erroring.
  static const _maxWalkDepth = 100;

  /// Convert a `/`-joined relative path (the flat-walk contract) to
  /// the host's native separator so `p.join` lands the local path
  /// correctly on Windows. SFTP / POSIX paths already use `/`.
  static String _toNative(String relPath) => p.joinAll(p.posix.split(relPath));

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
