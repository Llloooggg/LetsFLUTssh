import 'dart:io';

import '../../core/connection/connection.dart';
import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_fs.dart';
import '../../utils/android_storage_permission.dart';
import '../../utils/logger.dart';
import 'file_browser_controller.dart';

/// Result of SFTP initialization — controllers + filesystem handle.
class SFTPInitResult {
  final FilePaneController localCtrl;
  final FilePaneController remoteCtrl;
  final RemoteSftpFs filesystem;

  /// True if Android storage permission was denied during init.
  final bool storagePermissionDenied;

  SFTPInitResult({
    required this.localCtrl,
    required this.remoteCtrl,
    required this.filesystem,
    this.storagePermissionDenied = false,
  });

  void dispose() {
    localCtrl.dispose();
    remoteCtrl.dispose();
    filesystem.close();
  }
}

/// Shared SFTP initialization logic used by both desktop and mobile file browsers.
class SFTPInitializer {
  SFTPInitializer._();

  /// Initialize SFTP service and file pane controllers from a [Connection].
  ///
  /// [filesystemFactory] can be provided for testing to avoid real SSH.
  /// [localFsFactory] can be provided for testing to avoid real filesystem.
  static Future<SFTPInitResult> init(
    Connection connection, {
    Future<RemoteSftpFs> Function(Connection conn)? filesystemFactory,
    FileSystem Function()? localFsFactory,
  }) async {
    RemoteSftpFs filesystem;
    var permissionDenied = false;

    if (filesystemFactory != null) {
      filesystem = await filesystemFactory(connection);
    } else {
      final transport = connection.transport;
      if (transport == null) {
        throw StateError('SSH transport not available');
      }
      filesystem = await RustSftpFs.create(transport);

      if (Platform.isAndroid) {
        final granted = await requestAndroidStoragePermission();
        permissionDenied = !granted;
        AppLogger.instance.log(
          'Android storage permission: ${granted ? 'granted' : 'denied'}',
          name: 'SFTPInit',
        );
      }
    }

    final localCtrl = FilePaneController(
      fs: localFsFactory?.call() ?? LocalFS(),
      label: 'Local',
    );
    final remoteCtrl = FilePaneController(
      fs: RemoteFS(filesystem),
      label: 'Remote',
    );

    try {
      await Future.wait([localCtrl.init(), remoteCtrl.init()]);
    } catch (e) {
      // Pane init threw after the SFTP handshake already succeeded —
      // usually a permission denial on the remote initial dir, which
      // makes "connection succeeded but file browser blank" a
      // greppable event in support traces.
      AppLogger.instance.log(
        'SFTP pane init failed (disposing controllers + rethrowing): $e',
        name: 'SFTPInit',
        error: e,
      );
      localCtrl.dispose();
      remoteCtrl.dispose();
      rethrow;
    }

    AppLogger.instance.log(
      'SFTP panes initialized (android perm denied=$permissionDenied)',
      name: 'SFTPInit',
    );
    return SFTPInitResult(
      localCtrl: localCtrl,
      remoteCtrl: remoteCtrl,
      filesystem: filesystem,
      storagePermissionDenied: permissionDenied,
    );
  }
}
