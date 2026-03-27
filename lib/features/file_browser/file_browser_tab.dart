import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../utils/logger.dart';
import '../../widgets/error_state.dart';

import '../../core/connection/connection.dart';
import '../../core/sftp/sftp_client.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/transfer_task.dart';
import '../../providers/transfer_provider.dart';
import 'file_browser_controller.dart';
import 'file_pane.dart';
import 'sftp_initializer.dart';
import 'transfer_helpers.dart';
import 'transfer_panel.dart';

/// Dual-pane SFTP file browser tab.
/// Factory for SFTP initialization — injectable for testing.
typedef SFTPInitFactory = Future<SFTPInitResult> Function(Connection connection);

class FileBrowserTab extends ConsumerStatefulWidget {
  final Connection connection;

  /// Optional factory for testing — bypasses real SSH/SFTP.
  final SFTPInitFactory? sftpInitFactory;

  const FileBrowserTab({
    super.key,
    required this.connection,
    this.sftpInitFactory,
  });

  @override
  ConsumerState<FileBrowserTab> createState() => _FileBrowserTabState();
}

class _FileBrowserTabState extends ConsumerState<FileBrowserTab> {
  SFTPInitResult? _sftp;
  bool _initializing = true;
  String? _error;
  double _splitRatio = 0.5;

  FilePaneController? get _localCtrl => _sftp?.localCtrl;
  FilePaneController? get _remoteCtrl => _sftp?.remoteCtrl;
  SFTPService? get _sftpService => _sftp?.sftpService;

  @override
  void initState() {
    super.initState();
    _initSftp();
  }

  @override
  void dispose() {
    _sftp?.dispose();
    super.dispose();
  }

  Future<void> _initSftp() async {
    // Wait for connection if still connecting
    final conn = widget.connection;
    if (conn.isConnecting) {
      try {
        await conn.ready.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        if (mounted) {
          setState(() {
            _error = 'Connection timed out';
            _initializing = false;
          });
        }
        return;
      }
    }

    if (!conn.isConnected) {
      if (mounted) {
        setState(() {
          _error = conn.connectionError ?? 'Connection failed';
          _initializing = false;
        });
      }
      return;
    }

    try {
      _sftp = widget.sftpInitFactory != null
          ? await widget.sftpInitFactory!(conn)
          : await SFTPInitializer.init(conn);
      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (e) {
      AppLogger.instance.log('SFTP init failed: $e', name: 'FileBrowser', error: e);
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize SFTP: $e';
          _initializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) return _buildLoading();
    if (_error != null) return _buildError();

    final local = _localCtrl;
    final remote = _remoteCtrl;
    if (local == null || remote == null) {
      return const Center(child: Text('Controllers not initialized'));
    }

    return Column(
      children: [
        Expanded(child: _buildDualPane(context, local, remote)),
        const TransferPanel(),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing SFTP...'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return ErrorState(
      message: _error!,
      onRetry: () {
        setState(() {
          _initializing = true;
          _error = null;
        });
        _initSftp();
      },
    );
  }

  Widget _buildDualPane(BuildContext context, FilePaneController local, FilePaneController remote) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final leftWidth = (_splitRatio * maxWidth)
            .clamp(100.0, maxWidth - 100);

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: FilePane(
                controller: local,
                paneId: 'local',
                onTransfer: (entry) => _upload(entry),
                onTransferMultiple: (entries) {
                  for (final e in entries) {
                    _upload(e);
                  }
                },
                onDropReceived: (entries) {
                  for (final e in entries) {
                    _download(e);
                  }
                },
                onOsDropReceived: (paths) => _osDropToLocal(paths),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _splitRatio = ((_splitRatio * maxWidth + d.delta.dx) / maxWidth)
                        .clamp(0.2, 0.8);
                  });
                },
                child: Container(
                  width: 4,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            Expanded(
              child: FilePane(
                controller: remote,
                paneId: 'remote',
                onTransfer: (entry) => _download(entry),
                onTransferMultiple: (entries) {
                  for (final e in entries) {
                    _download(e);
                  }
                },
                onDropReceived: (entries) {
                  for (final e in entries) {
                    _upload(e);
                  }
                },
                onOsDropReceived: (paths) => _osDropToRemote(paths),
              ),
            ),
          ],
        );
      },
    );
  }

  void _upload(FileEntry entry) {
    final sftp = _sftpService;
    final remote = _remoteCtrl;
    if (sftp == null || remote == null) return;
    TransferHelpers.enqueueUpload(
      manager: ref.read(transferManagerProvider),
      sftp: sftp,
      entry: entry,
      remoteDirPath: remote.currentPath,
      remoteCtrl: _remoteCtrl,
    );
  }

  void _download(FileEntry entry) {
    final sftp = _sftpService;
    final local = _localCtrl;
    if (sftp == null || local == null) return;
    TransferHelpers.enqueueDownload(
      manager: ref.read(transferManagerProvider),
      sftp: sftp,
      entry: entry,
      localDirPath: local.currentPath,
      localCtrl: _localCtrl,
    );
  }

  /// OS drop onto local pane — copy files into the current local directory.
  void _osDropToLocal(List<String> paths) {
    final local = _localCtrl;
    if (local == null) return;
    final manager = ref.read(transferManagerProvider);
    for (final srcPath in paths) {
      final name = p.basename(srcPath);
      final targetPath = p.join(local.currentPath, name);
      final isDir = FileSystemEntity.isDirectorySync(srcPath);

      manager.enqueue(TransferTask(
        name: isDir ? '$name/' : name,
        direction: TransferDirection.download,
        sourcePath: srcPath,
        targetPath: targetPath,
        run: (update) async {
          update(0, 'Copying...');
          if (isDir) {
            await _copyDirLocal(Directory(srcPath), Directory(targetPath));
          } else {
            await File(srcPath).copy(targetPath);
          }
          update(100, 'Done');
          _localCtrl?.refresh();
        },
      ));
    }
  }

  /// OS drop onto remote pane — upload files to the current remote directory.
  void _osDropToRemote(List<String> paths) {
    final sftp = _sftpService;
    final remote = _remoteCtrl;
    if (sftp == null || remote == null) return;
    final manager = ref.read(transferManagerProvider);

    for (final srcPath in paths) {
      final name = p.basename(srcPath);
      final remotePath = p.posix.join(remote.currentPath, name);
      final isDir = FileSystemEntity.isDirectorySync(srcPath);

      manager.enqueue(TransferTask(
        name: isDir ? '$name/' : name,
        direction: TransferDirection.upload,
        sourcePath: srcPath,
        targetPath: remotePath,
        run: (update) async {
          update(0, 'Starting upload...');
          if (isDir) {
            await sftp.uploadDir(srcPath, remotePath, (progress) {
              update(progress.percent, '${progress.doneBytes}/${progress.totalBytes} files');
            });
          } else {
            await sftp.upload(srcPath, remotePath, (progress) {
              update(progress.percent, '${progress.doneBytes}/${progress.totalBytes}');
            });
          }
          _remoteCtrl?.refresh();
        },
      ));
    }
  }

  Future<void> _copyDirLocal(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = p.basename(entity.path);
      if (entity is File) {
        await entity.copy(p.join(dst.path, name));
      } else if (entity is Directory) {
        await _copyDirLocal(entity, Directory(p.join(dst.path, name)));
      }
    }
  }
}
