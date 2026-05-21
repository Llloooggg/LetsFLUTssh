import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/logger.dart';
import 'package:path/path.dart' as p;

import '../../providers/config_provider.dart';
import '../../src/rust/api/file_clipboard.dart' as rust_clip;
import '../../src/rust/api/local_fs.dart' as rust_local_fs;
import '../../theme/app_theme.dart';
import '../../widgets/core/app_empty_state.dart';
import '../../widgets/terminal/connection_progress.dart';
import '../../core/connection/connection.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/conflict_resolver.dart';
import '../../core/transfer/unique_name.dart';
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
  void Function(List<FileEntry>) transfer,
  void Function(List<FileEntry>) drop,
  String oppositeSourcePane,
  void Function(List<FileEntry>) paste,
  void Function(List<String>) onOsDropReceived,
});

class FileBrowserTab extends ConsumerStatefulWidget {
  final Connection connection;

  /// Optional factory for testing — bypasses real SSH/SFTP.
  final SFTPInitFactory? sftpInitFactory;

  /// Notifier incremented when the sidebar is activated — clear file
  /// selection so only one panel appears selected at a time.
  final ValueNotifier<int>? sidebarActivated;

  const FileBrowserTab({
    super.key,
    required this.connection,
    this.sftpInitFactory,
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

  // The file-browser clipboard for Ctrl+C / Ctrl+V across panes
  // lives Rust-side on `lfs_core::clipboard::FileBrowserClipboard`
  // (process-singleton). Routing through FRB lets the slot survive
  // tab swaps + future cross-tab paste, and aligns with the
  // CLAUDE.md "Rust owns data" rule for any user-data the app
  // holds across UI surfaces — paths today, bytes when the
  // file-viewer feature lands. The tab id below scopes paste
  // matching so a cut-then-paste in a sibling tab doesn't drain
  // this tab's clipboard.
  late final String _clipboardTabId;

  @override
  Connection get sftpConnection => widget.connection;
  @override
  SFTPInitFactory? get sftpInitFactory => widget.sftpInitFactory;

  FilePaneController? get _localCtrl => sftpResult?.localCtrl;
  FilePaneController? get _remoteCtrl => sftpResult?.remoteCtrl;

  @override
  void initState() {
    super.initState();
    // The connection id doubles as the per-tab clipboard scope —
    // it's unique per file-browser tab instance (one Connection
    // per tab) and stable for the tab's lifetime.
    _clipboardTabId = widget.connection.id;
    initSftp();
    widget.sidebarActivated?.addListener(_onSidebarActivated);
  }

  @override
  void dispose() {
    widget.sidebarActivated?.removeListener(_onSidebarActivated);
    // Drop the clipboard slot when this tab owns it — without
    // this the next file-browser tab opens to a paste-enabled
    // menu hinting at entries the user can no longer reach.
    // `is_set` + source-tab probe stays sync (no FRB await on
    // dispose).
    if (rust_clip.fileClipboardSourceTabId() == _clipboardTabId) {
      unawaited(rust_clip.fileClipboardClear());
    }
    disposeSftpBrowser();
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
                      actions: (
                        transfer: uploadMany,
                        drop: downloadMany,
                        oppositeSourcePane: 'remote',
                        paste: downloadMany,
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
                        transfer: downloadMany,
                        drop: uploadMany,
                        oppositeSourcePane: 'local',
                        paste: uploadMany,
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
    return AppEmptyState(message: S.of(context).resizeWindowToViewFiles);
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
  }) {
    return FilePane(
      controller: controller,
      paneId: paneId,
      showFolderSizes: showFolderSizes,
      onTransfer: (entry) => actions.transfer([entry]),
      onTransferMultiple: actions.transfer,
      onCopy: () => _copyToClipboard(controller, paneId),
      onPaste: () =>
          _pasteFromClipboard(actions.oppositeSourcePane, actions.paste),
      onDropReceived: actions.drop,
      onOsDropReceived: actions.onOsDropReceived,
      onPaneActivated: () => otherController.clearSelection(),
    );
  }

  /// Push the current pane's selection onto the Rust-side
  /// clipboard slot, tagged with this tab's id + source pane. The
  /// matching paste in the opposite pane consumes it via
  /// [`_pasteFromClipboard`].
  void _copyToClipboard(FilePaneController controller, String sourcePane) {
    final selected = controller.selectedEntries;
    if (selected.isEmpty) return;
    final entries = selected
        .map(
          (e) => rust_clip.DbClipboardEntry(
            name: e.name,
            path: e.path,
            size: BigInt.from(e.size),
            isDir: e.isDir,
          ),
        )
        .toList(growable: false);
    unawaited(
      rust_clip.fileClipboardPut(
        tabId: _clipboardTabId,
        sourcePane: sourcePane,
        entries: entries,
      ),
    );
  }

  /// Take the clipboard slot when this tab owns it and the source
  /// pane matches `expectedSource`. The Rust side drains the slot
  /// on a matching take so the same entries can't paste twice
  /// without a fresh copy.
  Future<void> _pasteFromClipboard(
    String expectedSource,
    void Function(List<FileEntry>) action,
  ) async {
    final taken = await rust_clip.fileClipboardTake(
      expectedTabId: _clipboardTabId,
      expectedSourcePane: expectedSource,
    );
    if (taken == null || taken.isEmpty) return;
    final entries = taken
        .map(
          (e) => FileEntry(
            name: e.name,
            path: e.path,
            size: e.size.toInt(),
            modTime: DateTime.fromMillisecondsSinceEpoch(0),
            isDir: e.isDir,
          ),
        )
        .toList(growable: false);
    action(entries);
  }

  /// OS drop onto local pane — copy files into the current local directory.
  ///
  /// Local-to-local copies do not flow through the transfer queue
  /// (which is owned Rust-side and SFTP-only); the file-system copy
  /// runs inline on the UI isolate. Best-effort: a partial dir copy
  /// surfaces as a logged warning, the user can re-drop to retry.
  ///
  /// Routes every file destination through [buildConflictResolver]
  /// so a drop that overlaps an existing target prompts the same
  /// `FileConflictDialog` the SFTP transfer paths use — without
  /// this the OS drop silently overwrote the target with no UI.
  /// Symlinks in the dropped tree are skipped so a malicious drop
  /// can't follow a link out of the user's chosen destination.
  void _osDropToLocal(List<String> paths) {
    if (_localCtrl == null) return;
    if (paths.isEmpty) return;
    final resolver = buildConflictResolver(showApplyToAll: paths.length > 1);
    unawaited(_runLocalDropBatch(paths: paths, resolver: resolver));
  }

  Future<void> _runLocalDropBatch({
    required List<String> paths,
    required BatchConflictResolver resolver,
  }) async {
    final local = _localCtrl;
    if (local == null) return;
    try {
      for (final srcPath in paths) {
        if (resolver.isCancelled) break;
        if (!mounted) return;
        final name = p.basename(srcPath);
        final srcStat = await rust_local_fs.localFsSymlinkStat(path: srcPath);
        if (srcStat == null) continue;
        if (srcStat.isSymlink) {
          AppLogger.instance.log(
            'Refusing OS drop of symlink source: <path>',
            name: 'FileBrowser',
            level: LogLevel.warn,
          );
          continue;
        }
        final isDir = srcStat.isDir;
        final initialTarget = p.join(local.currentPath, name);
        final resolvedTarget = await _resolveLocalDropConflict(
          targetPath: initialTarget,
          isDir: isDir,
          resolver: resolver,
        );
        if (resolvedTarget == null) continue;
        await _runLocalDrop(
          srcPath: srcPath,
          targetPath: resolvedTarget,
          isDir: isDir,
          name: name,
        );
      }
    } finally {
      resolver.dispose();
    }
  }

  /// Returns the local-FS path to copy into, or `null` when the user
  /// chose to skip / cancel. A pre-existing symlink at the target is
  /// hard-rejected (no overwrite-via-symlink) so the conflict dialog
  /// does not become a vehicle for following an attacker-supplied
  /// link out of the user's chosen directory.
  Future<String?> _resolveLocalDropConflict({
    required String targetPath,
    required bool isDir,
    required BatchConflictResolver resolver,
  }) async {
    final targetStat = await rust_local_fs.localFsSymlinkStat(path: targetPath);
    if (targetStat == null) return targetPath;
    if (targetStat.isSymlink) {
      AppLogger.instance.log(
        'Refusing local drop onto pre-existing symlink: <path>',
        name: 'FileBrowser',
        level: LogLevel.warn,
      );
      return null;
    }
    final action = await resolver.resolve(targetPath, isRemote: false);
    switch (action) {
      case ConflictAction.skip:
      case ConflictAction.cancel:
        return null;
      case ConflictAction.keepBoth:
        return uniqueSiblingName(
          targetPath,
          (path) async =>
              (await rust_local_fs.localFsSymlinkStat(path: path)) != null,
        );
      case ConflictAction.replace:
        return targetPath;
    }
  }

  Future<void> _runLocalDrop({
    required String srcPath,
    required String targetPath,
    required bool isDir,
    required String name,
  }) async {
    try {
      if (isDir) {
        // Recursive copy lives in `lfs_core::fs::local`. A symlink
        // at the root surfaces as `symlink_in_source` (the caller
        // already filtered those above, so this branch is the
        // defensive net); symlinks inside the tree are skipped
        // there, so a hostile link to `/etc` cannot resolve into
        // the recursion. Depth budget matches the SFTP upload
        // walker's cycle defence.
        await rust_local_fs.localFsCopyRecursiveNoSymlinks(
          src: srcPath,
          dst: targetPath,
          maxDepth: 100,
        );
      } else {
        await rust_local_fs.localFsCopyFile(src: srcPath, dst: targetPath);
      }
      _localCtrl?.refresh();
    } catch (e) {
      AppLogger.instance.log(
        'Local drop copy failed for $name: $e',
        name: 'FileBrowser',
      );
    }
  }

  /// OS drop onto remote pane — upload files to the current remote directory.
  Future<void> _osDropToRemote(List<String> paths) async {
    final entries = <FileEntry>[];
    for (final srcPath in paths) {
      final stat = await rust_local_fs.localFsStat(path: srcPath);
      if (stat == null) continue;
      entries.add(
        FileEntry(
          name: p.basename(srcPath),
          path: srcPath,
          size: stat.size.toInt(),
          modTime: DateTime.fromMillisecondsSinceEpoch(
            stat.modTimeUnixMs.toInt(),
          ),
          isDir: stat.isDir,
        ),
      );
    }
    await uploadMany(entries);
  }
}
