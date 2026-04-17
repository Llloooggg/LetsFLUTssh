import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/sftp/sftp_client.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/conflict_resolver.dart';
import '../../core/transfer/transfer_manager.dart';
import '../../core/transfer/transfer_task.dart';
import '../../core/transfer/unique_name.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/logger.dart';
import 'file_browser_controller.dart';

/// Shared upload/download helpers used by both desktop and mobile file browsers.
class TransferHelpers {
  TransferHelpers._();

  /// Enqueue an upload task for [entry] to the remote [remoteDirPath].
  ///
  /// Returns `true` if a task was enqueued, `false` if the transfer
  /// was skipped (conflict → skip) or cancelled (conflict → cancel).
  /// Dir entries bypass the conflict check — see class docs.
  static Future<bool> enqueueUpload({
    required TransferManager manager,
    required SFTPService sftp,
    required FileEntry entry,
    required String remoteDirPath,
    required FilePaneController? remoteCtrl,
    required S loc,
    BatchConflictResolver? conflictResolver,
  }) async {
    var remotePath = p.posix.join(remoteDirPath, entry.name);

    if (!entry.isDir && conflictResolver != null) {
      final resolved = await _resolveUploadConflict(
        sftp: sftp,
        targetPath: remotePath,
        resolver: conflictResolver,
      );
      if (resolved == null) return false;
      remotePath = resolved;
    }

    AppLogger.instance.log(
      'Enqueue upload: ${entry.path} → $remotePath',
      name: 'Transfer',
    );

    final displayName = p.posix.basename(remotePath);
    manager.enqueue(
      TransferTask(
        name: entry.isDir ? '${entry.name}/' : displayName,
        direction: TransferDirection.upload,
        sourcePath: entry.path,
        targetPath: remotePath,
        sizeBytes: entry.size,
        run: (update) async {
          update(0, loc.transferStartingUpload);
          if (entry.isDir) {
            await sftp.uploadDir(entry.path, remotePath, (progress) {
              update(
                progress.percent,
                loc.transferFilesProgress(
                  progress.doneBytes,
                  progress.totalBytes,
                ),
              );
            });
          } else {
            await sftp.upload(entry.path, remotePath, (progress) {
              update(
                progress.percent,
                '${progress.doneBytes}/${progress.totalBytes}',
              );
            });
          }
          remoteCtrl?.refresh();
        },
      ),
    );
    return true;
  }

  /// Enqueue a download task for [entry] to the local [localDirPath].
  ///
  /// Returns `true` if a task was enqueued, `false` if skipped/cancelled.
  static Future<bool> enqueueDownload({
    required TransferManager manager,
    required SFTPService sftp,
    required FileEntry entry,
    required String localDirPath,
    required FilePaneController? localCtrl,
    required S loc,
    BatchConflictResolver? conflictResolver,
  }) async {
    var localPath = p.join(localDirPath, entry.name);

    if (!entry.isDir && conflictResolver != null) {
      final resolved = await _resolveDownloadConflict(
        targetPath: localPath,
        resolver: conflictResolver,
      );
      if (resolved == null) return false;
      localPath = resolved;
    }

    AppLogger.instance.log(
      'Enqueue download: ${entry.path} → $localPath',
      name: 'Transfer',
    );

    final displayName = p.basename(localPath);
    manager.enqueue(
      TransferTask(
        name: entry.isDir ? '${entry.name}/' : displayName,
        direction: TransferDirection.download,
        sourcePath: entry.path,
        targetPath: localPath,
        sizeBytes: entry.size,
        run: (update) async {
          update(0, loc.transferStartingDownload);
          if (entry.isDir) {
            await sftp.downloadDir(entry.path, localPath, (progress) {
              update(
                progress.percent,
                loc.transferFilesProgress(
                  progress.doneBytes,
                  progress.totalBytes,
                ),
              );
            });
          } else {
            await sftp.download(entry.path, localPath, (progress) {
              update(
                progress.percent,
                '${progress.doneBytes}/${progress.totalBytes}',
              );
            });
          }
          localCtrl?.refresh();
        },
      ),
    );
    return true;
  }

  /// Returns the effective remote path to upload to, or `null` when
  /// the user chose to skip or cancel. When the user picks "keep
  /// both", the returned path is a renamed sibling.
  static Future<String?> _resolveUploadConflict({
    required SFTPService sftp,
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
    // Symlink-at-probe is already suspicious — a plain overwrite through
    // a symlink would follow it to whatever the link target is, which
    // could be a sensitive file the user never intended to touch (e.g.
    // `~/Downloads/foo.pdf` being a pre-planted symlink to `~/.ssh/id_ed25519`).
    // Refuse up front rather than letting the user "replace" into it.
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
        // TOCTOU re-check: between probe and the user answering the
        // prompt, another process could have swapped the file out for a
        // symlink to a sensitive location or replaced it with a
        // differently-shaped file. If that happened we refuse to
        // overwrite — the user's "replace" was consent for the file
        // they saw, not whatever is there now.
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

  /// Inode-level snapshot of a local path. Returns null when the path
  /// does not exist, so a "no target yet → just write" flow can skip
  /// the TOCTOU check entirely.
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

/// Shape/identity fingerprint for a local path captured just before a
/// destructive operation. `size` + `modified` + `type` is coarse
/// (Dart does not expose the inode number cross-platform) but it
/// catches the common TOCTOU patterns: file swapped for a symlink,
/// file replaced with different contents, or file moved and recreated
/// as a different type.
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
