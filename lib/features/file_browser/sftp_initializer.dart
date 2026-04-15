import 'dart:io';

import '../../core/connection/connection.dart';
import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_client.dart';
import '../../utils/android_storage_permission.dart';
import 'file_browser_controller.dart';

/// Result of SFTP initialization — controllers + service.
class SFTPInitResult {
  final FilePaneController localCtrl;
  final FilePaneController remoteCtrl;
  final SFTPService sftpService;

  /// True if Android storage permission was denied during init.
  final bool storagePermissionDenied;

  SFTPInitResult({
    required this.localCtrl,
    required this.remoteCtrl,
    required this.sftpService,
    this.storagePermissionDenied = false,
  });

  void dispose() {
    localCtrl.dispose();
    remoteCtrl.dispose();
    sftpService.close();
  }
}

/// Shared SFTP initialization logic used by both desktop and mobile file browsers.
class SFTPInitializer {
  SFTPInitializer._();

  /// Initialize SFTP service and file pane controllers from a [Connection].
  ///
  /// [sftpServiceFactory] can be provided for testing to avoid real SSH.
  /// [localFsFactory] can be provided for testing to avoid real filesystem.
  static Future<SFTPInitResult> init(
    Connection connection, {
    Future<SFTPService> Function(Connection conn)? sftpServiceFactory,
    FileSystem Function()? localFsFactory,
  }) async {
    SFTPService sftpService;
    var permissionDenied = false;
    if (sftpServiceFactory != null) {
      sftpService = await sftpServiceFactory(connection);
    } else {
      final sshClient = connection.sshConnection?.client;
      if (sshClient == null) {
        throw StateError('SSH connection not available');
      }

      // On Android, request storage permission for local file browser
      if (Platform.isAndroid) {
        final granted = await requestAndroidStoragePermission();
        permissionDenied = !granted;
      }

      sftpService = await SFTPService.fromSSHClient(sshClient);
    }

    final localCtrl = FilePaneController(
      fs: localFsFactory?.call() ?? LocalFS(),
      label: 'Local',
    );
    final remoteCtrl = FilePaneController(
      fs: RemoteFS(sftpService),
      label: 'Remote',
    );

    try {
      await Future.wait([localCtrl.init(), remoteCtrl.init()]);
    } catch (e) {
      localCtrl.dispose();
      remoteCtrl.dispose();
      rethrow;
    }

    return SFTPInitResult(
      localCtrl: localCtrl,
      remoteCtrl: remoteCtrl,
      sftpService: sftpService,
      storagePermissionDenied: permissionDenied,
    );
  }
}
