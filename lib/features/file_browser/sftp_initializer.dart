import 'dart:io' show Platform;

import '../../core/connection/connection.dart';
import '../../core/s3/s3_fs.dart';
import '../../core/session/session.dart';
import '../../core/sftp/file_system.dart';
import '../../platform/android_storage_permission.dart';
import '../../platform/local_fs.dart';
import '../../core/sftp/sftp_fs.dart';
import '../../core/webdav/webdav_fs.dart';
import '../../utils/logger.dart';
import 'file_browser_controller.dart';

/// Result of SFTP / WebDAV initialization — controllers + remote
/// [`FileSystem`] handle. `filesystem` is the [`RemoteSftpFs`]
/// when the connection is SSH-kind; null when the connection is
/// WebDAV (the file browser routes through the pane controller's
/// [`FileSystem`] surface, so the legacy SFTP handle has no
/// matching slot to plug into).
class SFTPInitResult {
  final FilePaneController localCtrl;
  final FilePaneController remoteCtrl;
  final RemoteSftpFs? filesystem;

  /// True on Android when broad storage access (`MANAGE_EXTERNAL_STORAGE`)
  /// is not currently held, so the local pane is confined to the app
  /// sandbox / scoped-storage dirs. The mobile browser surfaces a
  /// "grant access" banner off this flag; non-Android is always `false`.
  /// Probed (not requested) at init so opening SFTP never prompts — the
  /// banner button does the actual request.
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
    filesystem?.close();
  }
}

/// Shared file-browser initialization used by both desktop and
/// mobile shells. Dispatches by [`Connection.kind`]: SSH/SFTP
/// sessions wrap a live [`RustSftpFs`], WebDAV sessions wrap a
/// live [`WebDavFileSystem`] off the [`Connection.webdavConnection`]
/// handle. The pane controller talks only to the high-level
/// [`FileSystem`] interface so callers stay transport-agnostic.
class SFTPInitializer {
  SFTPInitializer._();

  /// Initialize the remote-pane file system and file-pane
  /// controllers from a [Connection].
  ///
  /// [filesystemFactory] can be provided for testing to avoid real SSH.
  /// [localFsFactory] can be provided for testing to avoid real filesystem.
  static Future<SFTPInitResult> init(
    Connection connection, {
    Future<RemoteSftpFs> Function(Connection conn)? filesystemFactory,
    FileSystem Function()? localFsFactory,
  }) async {
    final localCtrl = FilePaneController(
      fs: localFsFactory?.call() ?? LocalFS(),
      label: 'Local',
    );

    // Probe (don't request) broad storage access so opening SFTP never
    // throws a permission prompt — the mobile browser's banner button
    // does the actual request when the user wants the full filesystem.
    final permissionDenied = Platform.isAndroid
        ? !(await hasAndroidStoragePermission())
        : false;

    final FileSystem remoteFs;
    RemoteSftpFs? sftp;

    if (connection.kind == SessionKind.webdav) {
      final webdav = connection.webdavConnection;
      if (webdav == null) {
        localCtrl.dispose();
        throw StateError('WebDAV connection not available');
      }
      remoteFs = WebDavFileSystem(webdav, connection.webdavBaseUrl);
    } else if (connection.kind == SessionKind.s3) {
      final s3 = connection.s3Connection;
      if (s3 == null) {
        localCtrl.dispose();
        throw StateError('S3 connection not available');
      }
      remoteFs = S3FileSystem(s3, connection.s3InitialDir);
    } else if (filesystemFactory != null) {
      sftp = await filesystemFactory(connection);
      remoteFs = RemoteFS(sftp);
    } else {
      final transport = connection.transport;
      if (transport == null) {
        localCtrl.dispose();
        throw StateError('SSH transport not available');
      }
      sftp = await RustSftpFs.create(transport);
      remoteFs = RemoteFS(sftp);
    }

    final remoteCtrl = FilePaneController(fs: remoteFs, label: 'Remote');

    try {
      await Future.wait([localCtrl.init(), remoteCtrl.init()]);
    } catch (e) {
      // Pane init threw after the remote handshake already
      // succeeded — usually a permission denial on the remote
      // initial dir, which makes "connection succeeded but file
      // browser blank" a greppable event in support traces.
      AppLogger.instance.log(
        'Remote pane init failed (disposing controllers + rethrowing): $e',
        name: 'SFTPInit',
        error: e,
      );
      localCtrl.dispose();
      remoteCtrl.dispose();
      sftp?.close();
      rethrow;
    }

    return SFTPInitResult(
      localCtrl: localCtrl,
      remoteCtrl: remoteCtrl,
      filesystem: sftp,
      storagePermissionDenied: permissionDenied,
    );
  }
}
