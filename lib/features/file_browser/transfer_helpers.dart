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
    if (!await _localExists(targetPath)) return targetPath;
    final action = await resolver.resolve(targetPath, isRemote: false);
    switch (action) {
      case ConflictAction.skip:
      case ConflictAction.cancel:
        return null;
      case ConflictAction.keepBoth:
        return uniqueSiblingName(targetPath, _localExists);
      case ConflictAction.replace:
        return targetPath;
    }
  }

  static Future<bool> _localExists(String path) async {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }
}
