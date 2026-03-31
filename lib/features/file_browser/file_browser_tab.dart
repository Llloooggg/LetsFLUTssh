import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../utils/logger.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../../theme/app_theme.dart';
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

  /// Cross-widget marquee controller — forwarded to the local file pane.
  final CrossMarqueeController? crossMarquee;

  const FileBrowserTab({
    super.key,
    required this.connection,
    this.sftpInitFactory,
    this.crossMarquee,
  });

  @override
  ConsumerState<FileBrowserTab> createState() => _FileBrowserTabState();
}

class _FileBrowserTabState extends ConsumerState<FileBrowserTab> {
  SFTPInitResult? _sftp;
  bool _initializing = true;
  String? _error;
  final double _splitRatio = 0.5;

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
    await conn.waitUntilReady();

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
                crossMarquee: widget.crossMarquee,
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
                onPaneActivated: () => remote.clearSelection(),
              ),
            ),
            _TransferArrows(
              onUpload: () {
                final sel = local.selectedEntries;
                for (final e in sel) {
                  _upload(e);
                }
              },
              onDownload: () {
                final sel = remote.selectedEntries;
                for (final e in sel) {
                  _download(e);
                }
              },
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
                onPaneActivated: () => local.clearSelection(),
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

  static const _maxCopyDepth = 100;

  Future<void> _copyDirLocal(Directory src, Directory dst, [int depth = 0]) async {
    if (depth >= _maxCopyDepth) {
      throw StateError('Maximum recursion depth ($_maxCopyDepth) exceeded');
    }
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = p.basename(entity.path);
      if (entity is File) {
        await entity.copy(p.join(dst.path, name));
      } else if (entity is Directory) {
        await _copyDirLocal(entity, Directory(p.join(dst.path, name)), depth + 1);
      }
    }
  }
}

/// Central column with upload/download arrow buttons between local and remote panes.
class _TransferArrows extends StatelessWidget {
  final VoidCallback onUpload;
  final VoidCallback onDownload;

  const _TransferArrows({required this.onUpload, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      color: AppTheme.bg1,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ArrowButton(
            icon: Icons.arrow_forward,
            color: AppTheme.green,
            tooltip: 'Upload selected',
            onTap: onUpload,
          ),
          const SizedBox(height: 6),
          _ArrowButton(
            icon: Icons.arrow_back,
            color: AppTheme.blue,
            tooltip: 'Download selected',
            onTap: onDownload,
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ArrowButton> createState() => _ArrowButtonState();
}

class _ArrowButtonState extends State<_ArrowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered
                  ? widget.color.withValues(alpha: 0.15)
                  : AppTheme.bg3,
              border: Border.all(
                color: _hovered
                    ? widget.color.withValues(alpha: 0.3)
                    : AppTheme.borderLight,
              ),
            ),
            child: Icon(widget.icon, size: 12, color: widget.color),
          ),
        ),
      ),
    );
  }
}
