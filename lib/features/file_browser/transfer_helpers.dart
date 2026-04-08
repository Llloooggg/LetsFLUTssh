import 'package:path/path.dart' as p;

import '../../core/sftp/sftp_client.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/transfer_manager.dart';
import '../../core/transfer/transfer_task.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/logger.dart';
import 'file_browser_controller.dart';

/// Shared upload/download helpers used by both desktop and mobile file browsers.
class TransferHelpers {
  TransferHelpers._();

  /// Enqueue an upload task for [entry] to the remote [remoteDirPath].
  static void enqueueUpload({
    required TransferManager manager,
    required SFTPService sftp,
    required FileEntry entry,
    required String remoteDirPath,
    required FilePaneController? remoteCtrl,
    required S loc,
  }) {
    final remotePath = p.posix.join(remoteDirPath, entry.name);
    AppLogger.instance.log(
      'Enqueue upload: ${entry.path} → $remotePath',
      name: 'Transfer',
    );

    manager.enqueue(
      TransferTask(
        name: entry.isDir ? '${entry.name}/' : entry.name,
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
  }

  /// Enqueue a download task for [entry] to the local [localDirPath].
  static void enqueueDownload({
    required TransferManager manager,
    required SFTPService sftp,
    required FileEntry entry,
    required String localDirPath,
    required FilePaneController? localCtrl,
    required S loc,
  }) {
    final localPath = p.join(localDirPath, entry.name);
    AppLogger.instance.log(
      'Enqueue download: ${entry.path} → $localPath',
      name: 'Transfer',
    );

    manager.enqueue(
      TransferTask(
        name: entry.isDir ? '${entry.name}/' : entry.name,
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
  }
}
