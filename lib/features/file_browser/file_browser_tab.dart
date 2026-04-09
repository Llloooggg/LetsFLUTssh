import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

import '../../providers/config_provider.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_progress.dart';
import '../../core/connection/connection.dart';
import '../../core/sftp/sftp_client.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/transfer_task.dart';
import '../../providers/transfer_provider.dart';
import 'file_browser_controller.dart';
import 'file_pane.dart';
import 'sftp_browser_mixin.dart';
import 'sftp_initializer.dart';
import 'transfer_panel.dart';

/// Dual-pane SFTP file browser tab.
/// Factory for SFTP initialization — injectable for testing.
typedef SFTPInitFactory =
    Future<SFTPInitResult> Function(Connection connection);

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

  /// Reverse cross-marquee: file pane → session panel.
  final CrossMarqueeController? reverseCrossMarquee;

  /// Notifier incremented when the sidebar is activated — clear file
  /// selection so only one panel appears selected at a time.
  final ValueNotifier<int>? sidebarActivated;

  const FileBrowserTab({
    super.key,
    required this.connection,
    this.sftpInitFactory,
    this.crossMarquee,
    this.reverseCrossMarquee,
    this.sidebarActivated,
  });

  @override
  ConsumerState<FileBrowserTab> createState() => _FileBrowserTabState();
}

class _FileBrowserTabState extends ConsumerState<FileBrowserTab>
    with SftpBrowserMixin {
  @override
  SFTPInitResult? sftpResult;
  @override
  bool sftpInitializing = true;
  @override
  String? sftpError;
  double _splitRatio = 0.5;
  @override
  final progressKey = GlobalKey<ConnectionProgressState>();

  // SFTP clipboard for Ctrl+C / Ctrl+V across panes.
  List<FileEntry>? _clipboardEntries;
  String? _clipboardSourcePane;

  @override
  Connection get sftpConnection => widget.connection;
  @override
  SFTPInitFactory? get sftpInitFactory => widget.sftpInitFactory;

  FilePaneController? get _localCtrl => sftpResult?.localCtrl;
  FilePaneController? get _remoteCtrl => sftpResult?.remoteCtrl;
  SFTPService? get _sftpService => sftpResult?.sftpService;

  @override
  void initState() {
    super.initState();
    initSftp();
    widget.sidebarActivated?.addListener(_onSidebarActivated);
  }

  @override
  void dispose() {
    widget.sidebarActivated?.removeListener(_onSidebarActivated);
    sftpResult?.dispose();
    super.dispose();
  }

  void _onSidebarActivated() {
    _localCtrl?.clearSelection();
    _remoteCtrl?.clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    if (sftpInitializing || sftpError != null) return _buildLoading();

    final local = _localCtrl;
    final remote = _remoteCtrl;
    if (local == null || remote == null) {
      return Center(child: Text(S.of(context).controllersNotInitialized));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Minimum height for the dual pane area.
        const minDualPaneHeight = 80.0;
        final maxTransferHeight = (constraints.maxHeight - minDualPaneHeight)
            .clamp(0.0, double.infinity);
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
    return ConnectionProgress(
      key: progressKey,
      connection: widget.connection,
      fontSize: ref.read(configProvider).fontSize,
      channelLabel: S.of(context).progressOpeningSftp,
    );
  }

  Widget _buildDualPane(
    BuildContext context,
    FilePaneController local,
    FilePaneController remote,
  ) {
    final showFolderSizes = ref.watch(
      configProvider.select((c) => c.showFolderSizes),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Too narrow for dual pane — show hint instead of empty clipped panes.
        if (maxWidth < 250) {
          return _buildTooNarrowHint(context);
        }

        final leftWidth = (_splitRatio * maxWidth).clamp(100.0, maxWidth - 100);

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
                      reverseCrossMarquee: widget.reverseCrossMarquee,
                      actions: (
                        transfer: upload,
                        drop: download,
                        oppositeSourcePane: 'remote',
                        paste: download,
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
                        transfer: download,
                        drop: upload,
                        oppositeSourcePane: 'local',
                        paste: upload,
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
        S.of(context).resizeWindowToViewFiles,
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
    CrossMarqueeController? reverseCrossMarquee,
  }) {
    return FilePane(
      controller: controller,
      paneId: paneId,
      showFolderSizes: showFolderSizes,
      crossMarquee: crossMarquee,
      reverseCrossMarquee: reverseCrossMarquee,
      onTransfer: actions.transfer,
      onTransferMultiple: (entries) => entries.forEach(actions.transfer),
      onCopy: () => setState(() {
        _clipboardEntries = List.of(controller.selectedEntries);
        _clipboardSourcePane = paneId;
      }),
      onPaste: () =>
          _pasteFromClipboard(actions.oppositeSourcePane, actions.paste),
      onDropReceived: (entries) => entries.forEach(actions.drop),
      onOsDropReceived: actions.onOsDropReceived,
      onPaneActivated: () => otherController.clearSelection(),
    );
  }

  void _pasteFromClipboard(
    String expectedSource,
    void Function(FileEntry) action,
  ) {
    final entries = _clipboardEntries;
    if (entries == null || entries.isEmpty) return;
    if (_clipboardSourcePane != expectedSource) return;
    entries.forEach(action);
  }

  /// OS drop onto local pane — copy files into the current local directory.
  void _osDropToLocal(List<String> paths) {
    final local = _localCtrl;
    if (local == null) return;
    final manager = ref.read(transferManagerProvider);
    final loc = S.of(context);
    for (final srcPath in paths) {
      final name = p.basename(srcPath);
      final targetPath = p.join(local.currentPath, name);
      final isDir = FileSystemEntity.isDirectorySync(srcPath);

      manager.enqueue(
        TransferTask(
          name: isDir ? '$name/' : name,
          direction: TransferDirection.download,
          sourcePath: srcPath,
          targetPath: targetPath,
          run: (update) async {
            update(0, loc.transferCopying);
            if (isDir) {
              await _copyDirLocal(Directory(srcPath), Directory(targetPath));
            } else {
              await File(srcPath).copy(targetPath);
            }
            update(100, loc.transferDone);
            _localCtrl?.refresh();
          },
        ),
      );
    }
  }

  /// OS drop onto remote pane — upload files to the current remote directory.
  void _osDropToRemote(List<String> paths) {
    final sftp = _sftpService;
    final remote = _remoteCtrl;
    if (sftp == null || remote == null) return;
    final manager = ref.read(transferManagerProvider);
    final loc = S.of(context);

    for (final srcPath in paths) {
      final name = p.basename(srcPath);
      final remotePath = p.posix.join(remote.currentPath, name);
      final isDir = FileSystemEntity.isDirectorySync(srcPath);

      manager.enqueue(
        TransferTask(
          name: isDir ? '$name/' : name,
          direction: TransferDirection.upload,
          sourcePath: srcPath,
          targetPath: remotePath,
          run: (update) async {
            update(0, loc.transferStartingUpload);
            if (isDir) {
              await sftp.uploadDir(srcPath, remotePath, (progress) {
                update(
                  progress.percent,
                  loc.transferFilesProgress(
                    progress.doneBytes,
                    progress.totalBytes,
                  ),
                );
              });
            } else {
              await sftp.upload(srcPath, remotePath, (progress) {
                update(
                  progress.percent,
                  '${progress.doneBytes}/${progress.totalBytes}',
                );
              });
            }
            _remoteCtrl?.refresh();
          },
        ),
      );
    }
  }

  static const _maxCopyDepth = 100;

  Future<void> _copyDirLocal(
    Directory src,
    Directory dst, [
    int depth = 0,
  ]) async {
    if (depth >= _maxCopyDepth) {
      throw StateError('Maximum recursion depth ($_maxCopyDepth) exceeded');
    }
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = p.basename(entity.path);
      if (entity is File) {
        await entity.copy(p.join(dst.path, name));
      } else if (entity is Directory) {
        await _copyDirLocal(
          entity,
          Directory(p.join(dst.path, name)),
          depth + 1,
        );
      }
    }
  }
}
