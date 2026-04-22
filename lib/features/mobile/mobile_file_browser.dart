import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/connection/connection.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/connection_progress.dart';
import '../../core/sftp/sftp_models.dart';
import '../../providers/config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/mobile_selection_bar.dart';
import '../file_browser/breadcrumb_path.dart';
import '../file_browser/file_browser_controller.dart';
import '../file_browser/file_pane_dialogs.dart';
import '../file_browser/sftp_browser_mixin.dart';
import '../file_browser/sftp_initializer.dart';
import '../file_browser/transfer_panel.dart';

/// Factory for SFTP initialization — injectable for testing.
typedef MobileSFTPInitFactory =
    Future<SFTPInitResult> Function(Connection connection);

/// Single-pane mobile SFTP browser with Local/Remote toggle.
class MobileFileBrowser extends ConsumerStatefulWidget {
  final Connection connection;

  /// Optional factory for testing — bypasses real SSH/SFTP.
  final MobileSFTPInitFactory? sftpInitFactory;

  const MobileFileBrowser({
    super.key,
    required this.connection,
    this.sftpInitFactory,
  });

  @override
  ConsumerState<MobileFileBrowser> createState() => _MobileFileBrowserState();
}

class _MobileFileBrowserState extends ConsumerState<MobileFileBrowser>
    with SftpBrowserMixin {
  @override
  SFTPInitResult? sftpResult;
  @override
  bool sftpInitializing = true;
  @override
  String? sftpError;
  bool _showRemote = true; // Start on remote pane
  bool _storagePermissionDenied = false;
  @override
  final progressKey = GlobalKey<ConnectionProgressState>();

  @override
  Connection get sftpConnection => widget.connection;
  @override
  MobileSFTPInitFactory? get sftpInitFactory => widget.sftpInitFactory;

  @override
  void onSftpReady(SFTPInitResult result) {
    _storagePermissionDenied = result.storagePermissionDenied;
  }

  FilePaneController? get _localCtrl => sftpResult?.localCtrl;
  FilePaneController? get _remoteCtrl => sftpResult?.remoteCtrl;

  @override
  void initState() {
    super.initState();
    initSftp();
  }

  FilePaneController get _activeCtrl =>
      _showRemote ? _remoteCtrl! : _localCtrl!;

  @override
  Widget build(BuildContext context) {
    if (sftpInitializing || sftpError != null) {
      return ConnectionProgress(
        key: progressKey,
        connection: widget.connection,
        fontSize: ref.read(configProvider).fontSize,
        channelLabel: S.of(context).progressOpeningSftp,
      );
    }

    return Column(
      children: [
        _buildToolbar(context),
        if (Platform.isAndroid && !_showRemote && _storagePermissionDenied)
          _buildPermissionBanner(context),
        Expanded(
          // Horizontal swipe toggles Local ↔ Remote — mobile users
          // expect the same gesture they get from every tab-style UI
          // (left = go right tab, right = go left tab). Fires on
          // `onHorizontalDragEnd` rather than `Dismissible` so the
          // list still scrolls horizontally inside rows (e.g.
          // filename overflow) without dragging the whole pane. The
          // 500 px/s velocity threshold filters out slow drags that
          // would compete with row-level swipe actions.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() < 500) return;
              // v > 0 → swiped left-to-right → show Local (left tab);
              // v < 0 → swiped right-to-left → show Remote (right tab).
              setState(() => _showRemote = v < 0);
            },
            child: MobileFileList(
              controller: _activeCtrl,
              onTransfer: _showRemote ? download : upload,
              onTransferMultiple: _showRemote ? downloadMany : uploadMany,
            ),
          ),
        ),
        const TransferPanel(),
      ],
    );
  }

  bool _editingPath = false;
  final _pathController = TextEditingController();
  final _pathFocusNode = FocusNode();
  final _breadcrumbScrollController = ScrollController();

  @override
  void dispose() {
    sftpResult?.dispose();
    _pathController.dispose();
    _pathFocusNode.dispose();
    _breadcrumbScrollController.dispose();
    super.dispose();
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
              _buildToggleRow(context),
              const SizedBox(height: 4),
              _buildNavigationRow(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggleRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(S.of(context).local),
                icon: const Icon(Icons.phone_android, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text(S.of(context).remote),
                icon: const Icon(Icons.cloud, size: 16),
              ),
            ],
            selected: {_showRemote},
            onSelectionChanged: (s) => setState(() => _showRemote = s.first),
            style: _segmentedButtonStyle(),
          ),
        ),
        const SizedBox(width: 8),
        ..._platformButtons(context),
        AppIconButton(
          icon: Icons.refresh,
          size: 20,
          boxSize: 36,
          onTap: _activeCtrl.refresh,
          tooltip: S.of(context).refresh,
        ),
      ],
    );
  }

  ButtonStyle _segmentedButtonStyle() {
    final accentColor = _showRemote ? AppTheme.green : AppTheme.blue;
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return null;
        return accentColor.withValues(alpha: 0.15);
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return null;
        return accentColor;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return null;
        return accentColor;
      }),
      side: WidgetStateProperty.all(
        BorderSide(color: accentColor.withValues(alpha: 0.4)),
      ),
    );
  }

  List<Widget> _platformButtons(BuildContext context) {
    return [
      if (Platform.isIOS && !_showRemote)
        AppIconButton(
          icon: Icons.folder_open,
          size: 20,
          boxSize: 36,
          onTap: _pickLocalFolder,
          tooltip: S.of(context).pickFolder,
        ),
      if (Platform.isAndroid && !_showRemote && _storagePermissionDenied)
        AppIconButton(
          icon: Icons.security,
          size: 20,
          boxSize: 36,
          onTap: _requestAndRefreshPermission,
          tooltip: S.of(context).grantPermission,
        ),
    ];
  }

  Widget _buildNavigationRow(BuildContext context) {
    return SizedBox(
      height: AppTheme.barHeightMd,
      child: Row(
        children: [
          Expanded(
            child: _editingPath ? _buildPathEditor() : _buildBreadcrumb(),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.arrow_back,
            size: 22,
            boxSize: 36,
            onTap: _activeCtrl.canGoBack ? _activeCtrl.goBack : null,
            tooltip: S.of(context).back,
          ),
          AppIconButton(
            icon: Icons.arrow_forward,
            size: 22,
            boxSize: 36,
            onTap: _activeCtrl.canGoForward ? _activeCtrl.goForward : null,
            tooltip: S.of(context).forward,
          ),
          AppIconButton(
            icon: Icons.arrow_upward,
            size: 22,
            boxSize: 36,
            onTap: _activeCtrl.navigateUp,
            tooltip: S.of(context).up,
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final bc = parseBreadcrumbPath(_activeCtrl.currentPath);

    // Scroll to end so the deepest (current) folder segment is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbScrollController.hasClients) {
        _breadcrumbScrollController.jumpTo(
          _breadcrumbScrollController.position.maxScrollExtent,
        );
      }
    });

    return GestureDetector(
      onTap: () {
        _pathController.text = _activeCtrl.currentPath;
        setState(() => _editingPath = true);
        // Focus after frame so the TextField is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pathFocusNode.requestFocus();
        });
      },
      child: SingleChildScrollView(
        controller: _breadcrumbScrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Root segment
            _buildBreadcrumbChip(
              label: bc.rootLabel ?? '/',
              icon: bc.rootLabel == null ? Icons.home : null,
              onTap: () => _activeCtrl.navigateTo(bc.rootPath),
            ),
            // Path segments
            for (var i = 0; i < bc.navParts.length; i++) ...[
              Icon(
                Icons.chevron_right,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              _buildBreadcrumbChip(
                label: bc.navParts[i],
                isLast: i == bc.navParts.length - 1,
                onTap: () => _activeCtrl.navigateTo(buildPathForSegment(bc, i)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbChip({
    required String label,
    IconData? icon,
    bool isLast = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final weight = isLast ? FontWeight.w600 : FontWeight.normal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isLast
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: AppTheme.radiusSm,
        ),
        child: icon != null
            ? Icon(icon, size: 16, color: theme.colorScheme.onSurface)
            : Text(
                label,
                style: TextStyle(
                  fontSize: AppFonts.md,
                  fontWeight: weight,
                  color: theme.colorScheme.onSurface,
                ),
              ),
      ),
    );
  }

  Widget _buildPathEditor() {
    return TextField(
      controller: _pathController,
      focusNode: _pathFocusNode,
      style: TextStyle(fontSize: AppFonts.md),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        hintText: _activeCtrl.currentPath,
        border: const OutlineInputBorder(borderRadius: AppTheme.radiusSm),
        suffixIcon: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _editingPath = false),
        ),
      ),
      onSubmitted: (val) {
        setState(() => _editingPath = false);
        if (val.trim().isNotEmpty) {
          _activeCtrl.navigateTo(val.trim());
        }
      },
    );
  }

  Widget _buildPermissionBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.of(context).storagePermissionLimited,
              style: TextStyle(
                fontSize: AppFonts.sm,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AppButton.secondary(
            label: S.of(context).grantPermission,
            dense: true,
            onTap: _requestAndRefreshPermission,
          ),
        ],
      ),
    );
  }

  Future<void> _requestAndRefreshPermission() async {
    const channel = MethodChannel('com.letsflutssh/permissions');
    try {
      final granted = await channel.invokeMethod<bool>(
        'requestStoragePermission',
      );
      if (granted == true && mounted) {
        setState(() => _storagePermissionDenied = false);
        // Re-navigate to shared storage now that we have permission
        await _localCtrl?.navigateTo('/storage/emulated/0');
      }
    } catch (e) {
      AppLogger.instance.log(
        'Permission re-request failed: $e',
        name: 'MobileFileBrowser',
      );
    }
  }

  Future<void> _pickLocalFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null && _localCtrl != null) {
      await _localCtrl!.navigateTo(path);
    }
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
  void didUpdateWidget(MobileFileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _selectionMode = false;
    }
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
    if (ctrl.entries.isEmpty) {
      return AppEmptyState(message: S.of(context).emptyDirectory);
    }

    return Column(
      children: [
        if (_selectionMode)
          MobileSelectionBar(
            selectedCount: ctrl.selected.length,
            totalCount: ctrl.entries.length,
            onCancel: _exitSelectionMode,
            onSelectAll: ctrl.selectAll,
            onDeselectAll: ctrl.clearSelection,
            onDelete: ctrl.selected.isNotEmpty
                ? () => _confirmDelete(context, ctrl.selectedEntries)
                : null,
            actions: [
              AppIconButton(
                icon: Icons.swap_horiz,
                size: 20,
                boxSize: 36,
                onTap: ctrl.selected.isNotEmpty
                    ? () {
                        widget.onTransferMultiple(ctrl.selectedEntries);
                        _exitSelectionMode();
                      }
                    : null,
                tooltip: S.of(context).transfer,
              ),
            ],
          )
        else
          _buildSortBar(context),
        Expanded(
          child: ListView.builder(
            itemCount: ctrl.entries.length,
            itemExtent: 56,
            itemBuilder: (context, index) =>
                _buildFileRow(context, ctrl.entries[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildSortBar(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = S.of(context);
    final column = ctrl.sortColumn;
    final asc = ctrl.sortAscending;

    String columnLabel(SortColumn col) => switch (col) {
      SortColumn.name => l10n.name,
      SortColumn.size => l10n.size,
      SortColumn.modified => l10n.modified,
      SortColumn.mode => l10n.mode,
      SortColumn.owner => l10n.owner,
    };

    final arrow = asc ? ' ↑' : ' ↓';

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.sort, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showSortMenu(context),
            child: Text(
              '${columnLabel(column)}$arrow',
              style: TextStyle(
                fontSize: AppFonts.sm,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${ctrl.entries.length}',
            style: TextStyle(
              fontSize: AppFonts.sm,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    final l10n = S.of(context);
    final columns = [
      (SortColumn.name, l10n.name, Icons.sort_by_alpha),
      (SortColumn.size, l10n.size, Icons.storage),
      (SortColumn.modified, l10n.modified, Icons.schedule),
      (SortColumn.mode, l10n.mode, Icons.lock_outline),
      (SortColumn.owner, l10n.owner, Icons.person_outline),
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.sort,
                style: TextStyle(
                  fontSize: AppFonts.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final (col, label, icon) in columns)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: _sortIndicator(ctrl, col),
                selected: ctrl.sortColumn == col,
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.setSort(col);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget? _sortIndicator(FilePaneController ctrl, SortColumn col) {
    if (ctrl.sortColumn != col) return null;
    final icon = ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward;
    return Icon(icon, size: 18);
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(localizeError(S.of(context), ctrl.error!)),
          const SizedBox(height: 8),
          AppButton.secondary(
            label: S.of(context).retry,
            icon: Icons.refresh,
            onTap: ctrl.refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(BuildContext context, FileEntry entry) {
    final theme = Theme.of(context);
    final isSelected = ctrl.selected.contains(entry.path);
    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final subtitleStyle = TextStyle(
      fontSize: AppFonts.sm,
      color: subtitleColor,
    );

    // Subtitle: "size · date · rwx..." for files, "date · rwx..." for dirs
    final parts = <String>[
      if (!entry.isDir) formatSize(entry.size),
      formatTimestamp(entry.modTime),
      entry.modeString,
    ];

    return InkWell(
      onTap: () => _onEntryTap(entry),
      onLongPress: () => _onEntryLongPress(context, entry),
      child: Container(
        height: AppTheme.itemHeightXl,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
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
              color: entry.isDir
                  ? AppTheme.folderIcon
                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(fontSize: AppFonts.md),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    style: subtitleStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onEntryTap(FileEntry entry) {
    if (_selectionMode) {
      ctrl.toggleSelect(entry.path);
    } else if (entry.isDir) {
      ctrl.navigateTo(entry.path);
    } else {
      widget.onTransfer(entry);
    }
  }

  void _onEntryLongPress(BuildContext context, FileEntry entry) {
    _showEntryActions(context, entry);
  }

  void _showEntryActions(BuildContext context, FileEntry entry) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(S.of(ctx).transfer),
              onTap: () {
                Navigator.pop(ctx);
                widget.onTransfer(entry);
              },
            ),
            if (entry.isDir)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(S.of(ctx).open),
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.navigateTo(entry.path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(S.of(ctx).rename),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, entry);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: AppTheme.disconnected),
              title: Text(
                S.of(ctx).delete,
                style: TextStyle(color: AppTheme.disconnected),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, [entry]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: Text(S.of(ctx).newFolder),
              onTap: () {
                Navigator.pop(ctx);
                _showNewFolderDialog(context);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(S.of(ctx).select),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _selectionMode = true);
                ctrl.selectSingle(entry.path);
              },
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

  Future<void> _confirmDelete(
    BuildContext context,
    List<FileEntry> entries,
  ) async {
    await FilePaneDialogs.confirmDelete(context, ctrl, entries);
    _exitSelectionMode();
  }
}
