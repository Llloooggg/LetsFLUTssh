import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../../core/connection/connection.dart';
import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_client.dart';
import 'file_browser_controller.dart';

/// Result of SFTP initialization — controllers + service.
class SFTPInitResult {
  final FilePaneController localCtrl;
  final FilePaneController remoteCtrl;
  final SFTPService sftpService;

  SFTPInitResult({
    required this.localCtrl,
    required this.remoteCtrl,
    required this.sftpService,
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
  /// Throws if SSH connection is not available or SFTP init fails.
  /// Request MANAGE_EXTERNAL_STORAGE on Android for local file browsing.
  /// Falls back to READ/WRITE_EXTERNAL_STORAGE on API < 30.
  static Future<void> _requestStoragePermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return;
    final result = await Permission.manageExternalStorage.request();
    if (!result.isGranted) {
      // Fall back to legacy storage permission (API < 30)
      await Permission.storage.request();
    }
  }

  static Future<SFTPInitResult> init(Connection connection) async {
    final sshClient = connection.sshConnection?.client;
    if (sshClient == null) {
      throw StateError('SSH connection not available');
    }

    // On Android, request storage permission for local file browser
    if (Platform.isAndroid) {
      await _requestStoragePermission();
    }

    final sftpService = await SFTPService.fromSSHClient(sshClient);
    final localCtrl = FilePaneController(fs: LocalFS(), label: 'Local');
    final remoteCtrl = FilePaneController(fs: RemoteFS(sftpService), label: 'Remote');

    await Future.wait([localCtrl.init(), remoteCtrl.init()]);

    return SFTPInitResult(
      localCtrl: localCtrl,
      remoteCtrl: remoteCtrl,
      sftpService: sftpService,
    );
  }
}
