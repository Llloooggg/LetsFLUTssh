import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/config_provider.dart';
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

typedef _PaneActions = ({
  void Function(FileEntry) transfer,
  void Function(FileEntry) drop,
  String oppositeSourcePane,
  void Function(FileEntry) paste,
  void Function(List<String>) onOsDropReceived,
});

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
  double _splitRatio = 0.5;

  // SFTP clipboard for Ctrl+C / Ctrl+V across panes.
  List<FileEntry>? _clipboardEntries;
  String? _clipboardSourcePane;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Minimum height for the dual pane area.
        const minDualPaneHeight = 80.0;
        final maxTransferHeight = (constraints.maxHeight - minDualPaneHeight).clamp(0.0, double.infinity);
        return Column(
          children: [
            Expanded(child: _buildDualPane(context, local, remote)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxTransferHeight),
              child: const TransferPanel(),
            ),
          ],
        );
      },
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
    final showFolderSizes = ref.watch(configProvider.select((c) => c.showFolderSizes));
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Too narrow for dual pane — show hint instead of empty clipped panes.
        if (maxWidth < 250) {
          return _buildTooNarrowHint(context);
        }

        final leftWidth = (_splitRatio * maxWidth)
            .clamp(100.0, maxWidth - 100);

        return Stack(
          children: [
            Row(
              children: [
                SizedBox(
                  width: leftWidth,
                  child: ClipRect(
                    child: _buildFilePane(
                      controller: local,
                      paneId: 'local',
                      showFolderSizes: showFolderSizes,
                      crossMarquee: widget.crossMarquee,
                      actions: (
                        transfer: _upload,
                        drop: _download,
                        oppositeSourcePane: 'remote',
                        paste: _download,
                        onOsDropReceived: _osDropToLocal,
                      ),
                      otherController: remote,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: _buildFilePane(
                      controller: remote,
                      paneId: 'remote',
                      showFolderSizes: showFolderSizes,
                      actions: (
                        transfer: _download,
                        drop: _upload,
                        oppositeSourcePane: 'local',
                        paste: _upload,
                        onOsDropReceived: _osDropToRemote,
                      ),
                      otherController: local,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: leftWidth - 3,
              top: 0,
              bottom: 0,
              child: _buildDivider(maxWidth),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTooNarrowHint(BuildContext context) {
    return Center(
      child: Text(
        'Resize window to view files',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppFonts.sm,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildDivider(double maxWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          setState(() {
            _splitRatio = ((_splitRatio * maxWidth + d.delta.dx) / maxWidth)
                .clamp(0.2, 0.8);
          });
        },
        child: SizedBox(
          width: 6,
          child: Center(child: Container(width: 1, color: AppTheme.border)),
        ),
      ),
    );
  }

  FilePane _buildFilePane({
    required FilePaneController controller,
    required String paneId,
    required bool showFolderSizes,
    required _PaneActions actions,
    required FilePaneController otherController,
    CrossMarqueeController? crossMarquee,
  }) {
    return FilePane(
      controller: controller,
      paneId: paneId,
      showFolderSizes: showFolderSizes,
      crossMarquee: crossMarquee,
      onTransfer: actions.transfer,
      onTransferMultiple: (entries) => entries.forEach(actions.transfer),
      onCopy: () => setState(() {
        _clipboardEntries = List.of(controller.selectedEntries);
        _clipboardSourcePane = paneId;
      }),
      onPaste: () => _pasteFromClipboard(actions.oppositeSourcePane, actions.paste),
      onDropReceived: (entries) => entries.forEach(actions.drop),
      onOsDropReceived: actions.onOsDropReceived,
      onPaneActivated: () => otherController.clearSelection(),
    );
  }

  void _pasteFromClipboard(String expectedSource, void Function(FileEntry) action) {
    final entries = _clipboardEntries;
    if (entries == null || entries.isEmpty) return;
    if (_clipboardSourcePane != expectedSource) return;
    entries.forEach(action);
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
