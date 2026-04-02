import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/connection/connection.dart';
import '../../core/sftp/sftp_client.dart';
import '../../core/sftp/sftp_models.dart';
import '../../providers/transfer_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../widgets/app_icon_button.dart';
import '../file_browser/file_browser_controller.dart';
import '../file_browser/file_pane_dialogs.dart';
import '../file_browser/sftp_initializer.dart';
import '../file_browser/transfer_helpers.dart';
import '../file_browser/transfer_panel.dart';

/// Single-pane mobile SFTP browser with Local/Remote toggle.
class MobileFileBrowser extends ConsumerStatefulWidget {
  final Connection connection;

  const MobileFileBrowser({super.key, required this.connection});

  @override
  ConsumerState<MobileFileBrowser> createState() => _MobileFileBrowserState();
}

class _MobileFileBrowserState extends ConsumerState<MobileFileBrowser> {
  SFTPInitResult? _sftp;
  bool _initializing = true;
  String? _error;
  bool _showRemote = true; // Start on remote pane

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
    final conn = widget.connection;

    // Wait for connection if still connecting (connectAsync returns immediately)
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
      _sftp = await SFTPInitializer.init(conn);
      if (mounted) setState(() => _initializing = false);
    } catch (e) {
      AppLogger.instance.log('SFTP init failed: $e', name: 'MobileFileBrowser', error: e);
      if (mounted) setState(() { _error = 'Failed to init SFTP: $e'; _initializing = false; });
    }
  }

  FilePaneController get _activeCtrl => _showRemote ? _remoteCtrl! : _localCtrl!;

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Initializing SFTP...')],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.disconnected),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () { setState(() { _initializing = true; _error = null; }); _initSftp(); },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildToolbar(context),
        Expanded(child: MobileFileList(
          controller: _activeCtrl,
          onTransfer: _showRemote ? _download : _upload,
          onTransferMultiple: _showRemote
              ? (entries) { for (final e in entries) { _download(e); } }
              : (entries) { for (final e in entries) { _upload(e); } },
        )),
        const TransferPanel(),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _activeCtrl,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Local/Remote toggle
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Local'), icon: Icon(Icons.phone_android, size: 16)),
                        ButtonSegment(value: true, label: Text('Remote'), icon: Icon(Icons.cloud, size: 16)),
                      ],
                      selected: {_showRemote},
                      onSelectionChanged: (s) => setState(() => _showRemote = s.first),
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppIconButton(
                    icon: Icons.refresh,
                    size: 20,
                    boxSize: 36,
                    onTap: _activeCtrl.refresh,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Path breadcrumb
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    AppIconButton(
                      icon: Icons.arrow_back,
                      size: 22,
                      boxSize: 36,
                      onTap: _activeCtrl.canGoBack ? _activeCtrl.goBack : null,
                      tooltip: 'Back',
                    ),
                    AppIconButton(
                      icon: Icons.arrow_upward,
                      size: 22,
                      boxSize: 36,
                      onTap: _activeCtrl.navigateUp,
                      tooltip: 'Up',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _activeCtrl.currentPath,
                        style: TextStyle(fontSize: AppFonts.lg),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
}

/// Mobile file list — tap to navigate dirs, long press for context menu,
/// selection mode with checkboxes.
class MobileFileList extends StatefulWidget {
  final FilePaneController controller;
  final void Function(FileEntry) onTransfer;
  final void Function(List<FileEntry>) onTransferMultiple;

  const MobileFileList({
    super.key,
    required this.controller,
    required this.onTransfer,
    required this.onTransferMultiple,
  });

  @override
  State<MobileFileList> createState() => _MobileFileListState();
}

class _MobileFileListState extends State<MobileFileList> {
  bool _selectionMode = false;

  FilePaneController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _exitSelectionMode() {
    ctrl.clearSelection();
    setState(() => _selectionMode = false);
  }

  @override
  Widget build(BuildContext context) {
    if (ctrl.loading) return const Center(child: CircularProgressIndicator());
    if (ctrl.error != null) return _buildError(context);
    if (ctrl.entries.isEmpty) return const Center(child: Text('Empty directory'));

    return Column(
      children: [
        if (_selectionMode && ctrl.selected.isNotEmpty)
          _buildSelectionBar(context),
        Expanded(
          child: ListView.builder(
            itemCount: ctrl.entries.length,
            itemExtent: 48,
            itemBuilder: (context, index) =>
                _buildFileRow(context, ctrl.entries[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(ctrl.error!),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: ctrl.refresh, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.close,
            size: 20,
            boxSize: 36,
            onTap: _exitSelectionMode,
            tooltip: 'Cancel selection',
          ),
          Text('${ctrl.selected.length} selected', style: TextStyle(fontSize: AppFonts.lg)),
          const Spacer(),
          AppIconButton(
            icon: Icons.swap_horiz,
            size: 20,
            boxSize: 36,
            onTap: () {
              widget.onTransferMultiple(ctrl.selectedEntries);
              _exitSelectionMode();
            },
            tooltip: 'Transfer',
          ),
          AppIconButton(
            icon: Icons.delete,
            size: 20,
            boxSize: 36,
            color: AppTheme.disconnected,
            onTap: () => _confirmDelete(context, ctrl.selectedEntries),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(BuildContext context, FileEntry entry) {
    final theme = Theme.of(context);
    final isSelected = ctrl.selected.contains(entry.path);

    return InkWell(
      onTap: () => _onEntryTap(entry),
      onLongPress: () => _onEntryLongPress(context, entry),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
        child: Row(
          children: [
            if (_selectionMode)
              Checkbox(
                value: isSelected,
                onChanged: (_) => ctrl.toggleSelect(entry.path),
                visualDensity: VisualDensity.compact,
              ),
            Icon(
              entry.isDir ? Icons.folder : Icons.insert_drive_file,
              size: 22,
              color: entry.isDir ? AppTheme.folderIcon : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(entry.name, style: TextStyle(fontSize: AppFonts.md), overflow: TextOverflow.ellipsis),
                  if (!entry.isDir)
                    Text(
                      formatSize(entry.size),
                      style: TextStyle(fontSize: AppFonts.sm, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                ],
              ),
            ),
            if (!_selectionMode)
              Text(
                entry.modeString,
                style: TextStyle(fontSize: AppFonts.sm, fontFamily: 'monospace', color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
          ],
        ),
      ),
    );
  }

  void _onEntryTap(FileEntry entry) {
    if (_selectionMode) {
      ctrl.toggleSelect(entry.path);
      if (ctrl.selected.isEmpty) _exitSelectionMode();
    } else if (entry.isDir) {
      ctrl.navigateTo(entry.path);
    } else {
      widget.onTransfer(entry);
    }
  }

  void _onEntryLongPress(BuildContext context, FileEntry entry) {
    if (!_selectionMode) {
      setState(() => _selectionMode = true);
      ctrl.selectSingle(entry.path);
    } else {
      _showEntryActions(context, entry);
    }
  }

  void _showEntryActions(BuildContext context, FileEntry entry) {
    ctrl.selectSingle(entry.path);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer'),
              onTap: () { Navigator.pop(ctx); widget.onTransfer(entry); },
            ),
            if (entry.isDir)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Open'),
                onTap: () { Navigator.pop(ctx); ctrl.navigateTo(entry.path); },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () { Navigator.pop(ctx); _showRenameDialog(context, entry); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppTheme.disconnected),
              title: const Text('Delete', style: TextStyle(color: AppTheme.disconnected)),
              onTap: () { Navigator.pop(ctx); _confirmDelete(context, [entry]); },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('New Folder'),
              onTap: () { Navigator.pop(ctx); _showNewFolderDialog(context); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNewFolderDialog(BuildContext context) =>
      FilePaneDialogs.showNewFolder(context, ctrl);

  Future<void> _showRenameDialog(BuildContext context, FileEntry entry) =>
      FilePaneDialogs.showRename(context, ctrl, entry);

  Future<void> _confirmDelete(BuildContext context, List<FileEntry> entries) async {
    await FilePaneDialogs.confirmDelete(context, ctrl, entries);
    _exitSelectionMode();
  }
}
