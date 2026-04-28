import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/sftp/sftp_fs.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/conflict_resolver.dart';
import '../../core/transfer/transfer_manager.dart';
import '../../core/transfer/unique_name.dart';
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
    required TransferManager manager,
    required RemoteSftpFs sftp,
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
        sftp: sftp,
        connectionId: connectionId,
        localDir: Directory(entry.path),
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
        sftp: sftp,
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
    required TransferManager manager,
    required RemoteSftpFs sftp,
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
        sftp: sftp,
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
  /// file. Skips symlinks (we don't follow into arbitrary targets) and
  /// conflict-skipped paths. Returns the total enqueue count.
  static Future<int> _enqueueUploadDir({
    required TransferManager manager,
    required RemoteSftpFs sftp,
    required String connectionId,
    required Directory localDir,
    required String remoteDir,
    required BatchConflictResolver? conflictResolver,
  }) async {
    var enqueued = 0;
    try {
      await sftp.mkdir(remoteDir);
    } catch (_) {
      // Already exists or other transient — per-file upserts will fail
      // if the dir is genuinely unwritable; let those surface there.
    }
    final children = localDir.listSync(followLinks: false);
    for (final child in children) {
      final base = p.basename(child.path);
      final remoteChild = p.posix.join(remoteDir, base);
      if (child is Directory) {
        enqueued += await _enqueueUploadDir(
          manager: manager,
          sftp: sftp,
          connectionId: connectionId,
          localDir: child,
          remoteDir: remoteChild,
          conflictResolver: conflictResolver,
        );
      } else if (child is File) {
        String? resolved = remoteChild;
        if (conflictResolver != null) {
          resolved = await _resolveUploadConflict(
            sftp: sftp,
            targetPath: remoteChild,
            resolver: conflictResolver,
          );
          if (resolved == null) continue;
        }
        final stat = child.statSync();
        await manager.enqueueUpload(
          connectionId: connectionId,
          name: p.posix.basename(resolved),
          localPath: child.path,
          remotePath: resolved,
          sizeBytes: stat.size,
        );
        enqueued++;
      }
      // Skip symlinks — we don't follow them into arbitrary targets.
    }
    return enqueued;
  }

  /// Walk [remoteDir] over SFTP and enqueue a download task per leaf
  /// file. Mirrors [_enqueueUploadDir] in shape.
  static Future<int> _enqueueDownloadDir({
    required TransferManager manager,
    required RemoteSftpFs sftp,
    required String connectionId,
    required String remoteDir,
    required String localDir,
    required BatchConflictResolver? conflictResolver,
  }) async {
    var enqueued = 0;
    Directory(localDir).createSync(recursive: true);
    final entries = await sftp.list(remoteDir);
    for (final remoteEntry in entries) {
      final base = remoteEntry.name;
      if (base == '.' || base == '..') continue;
      final remoteChild = p.posix.join(remoteDir, base);
      final localChild = p.join(localDir, base);
      if (remoteEntry.isDir) {
        enqueued += await _enqueueDownloadDir(
          manager: manager,
          sftp: sftp,
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
    required RemoteSftpFs sftp,
    required String targetPath,
    required BatchConflictResolver resolver,
  }) async {
    if (!await sftp.exists(targetPath)) return targetPath;
    final action = await resolver.resolve(targetPath, isRemote: true);
    switch (action) {
      case ConflictAction.skip:
      case ConflictAction.cancel:
        return null;
      case ConflictAction.keepBoth:
        return uniqueSiblingName(targetPath, sftp.exists, isPosix: true);
      case ConflictAction.replace:
        return targetPath;
    }
  }

  static Future<String?> _resolveDownloadConflict({
    required String targetPath,
    required BatchConflictResolver resolver,
  }) async {
    final snapshot = _snapshotLocal(targetPath);
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
        final current = _snapshotLocal(targetPath);
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
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  static _LocalSnapshot? _snapshotLocal(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type == FileSystemEntityType.link) {
      return const _LocalSnapshot.symlink();
    }
    FileStat? stat;
    try {
      stat = FileStat.statSync(path);
    } catch (_) {
      return const _LocalSnapshot.unknown();
    }
    return _LocalSnapshot(type: type, size: stat.size, modified: stat.modified);
  }

  static bool _localSnapshotsMatch(_LocalSnapshot a, _LocalSnapshot? b) {
    if (b == null) return false;
    if (a.isSymlink || b.isSymlink) return false;
    return a.type == b.type &&
        a.size == b.size &&
        a.modified?.millisecondsSinceEpoch ==
            b.modified?.millisecondsSinceEpoch;
  }
}

class _LocalSnapshot {
  final FileSystemEntityType? type;
  final int? size;
  final DateTime? modified;
  final bool isSymlink;

  const _LocalSnapshot({
    required this.type,
    required this.size,
    required this.modified,
  }) : isSymlink = false;

  const _LocalSnapshot.symlink()
    : type = null,
      size = null,
      modified = null,
      isSymlink = true;

  const _LocalSnapshot.unknown()
    : type = null,
      size = null,
      modified = null,
      isSymlink = false;
}
