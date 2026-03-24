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
  static Future<SFTPInitResult> init(Connection connection) async {
    final sshClient = connection.sshConnection?.client;
    if (sshClient == null) {
      throw StateError('SSH connection not available');
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
