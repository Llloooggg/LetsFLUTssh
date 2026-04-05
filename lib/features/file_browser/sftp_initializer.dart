import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/connection/connection.dart';
import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_client.dart';
import '../../utils/logger.dart';
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

  /// Request storage permission on Android via platform channel.
  /// No external plugin needed — avoids GPS/location side-effects from permission_handler.
  ///
  /// Returns `true` if permission was granted, `false` otherwise.
  /// On Android 11+ this opens the "All files access" system settings page.
  /// On older versions it shows the standard runtime permission dialog.
  static Future<bool> _requestStoragePermission() async {
    try {
      // Quick check: if we can already list shared storage, skip the request
      final testDir = Directory('/storage/emulated/0');
      if (await testDir.exists()) {
        try {
          await testDir.list().first;
          return true;
        } catch (_) {
          // Can't list — need permission
        }
      }

      // Request via platform channel — native Android side shows the dialog
      const channel = MethodChannel('com.letsflutssh/permissions');
      final granted = await channel.invokeMethod<bool>(
        'requestStoragePermission',
      );
      if (granted != true) {
        AppLogger.instance.log(
          'Storage permission denied by user',
          name: 'Permission',
        );
        return false;
      }
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Storage permission request failed: $e',
        name: 'Permission',
      );
      return false;
    }
  }

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
    if (sftpServiceFactory != null) {
      sftpService = await sftpServiceFactory(connection);
    } else {
      final sshClient = connection.sshConnection?.client;
      if (sshClient == null) {
        throw StateError('SSH connection not available');
      }

      // On Android, request storage permission for local file browser
      if (Platform.isAndroid) {
        await _requestStoragePermission();
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
    );
  }
}
