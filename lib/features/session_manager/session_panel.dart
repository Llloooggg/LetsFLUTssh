import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/context_menu.dart';
import '../../utils/platform.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/cross_marquee_controller.dart';
import 'session_edit_dialog.dart';
import 'session_tree_view.dart';

const _kNewFolder = 'New Folder';

/// Session sidebar — tree view + search + actions.
class SessionPanel extends ConsumerStatefulWidget {
  final void Function(Session session) onConnect;
  final void Function(SSHConfig config) onQuickConnect;
  final void Function(Session session)? onSftpConnect;
  final CrossMarqueeController? crossMarquee;

  const SessionPanel({
    super.key,
    required this.onConnect,
    required this.onQuickConnect,
    this.onSftpConnect,
    this.crossMarquee,
  });

  @override
  ConsumerState<SessionPanel> createState() => SessionPanelState();
}

class SessionPanelState extends ConsumerState<SessionPanel> {
  bool _selectMode = false;
  final _selectedIds = <String>{};
  // Marquee state tracked for test visibility only.
  @visibleForTesting
  bool marqueeInProgress = false;

  @visibleForTesting
  bool get selectMode => _selectMode;
  @visibleForTesting
  Set<String> get selectedIds => _selectedIds;

  /// Simulate marquee selection in tests.
  @visibleForTesting
  void setMarqueeSelection(Set<String> ids) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
    });
  }

  @visibleForTesting
  void simulateMarqueeStart() => setState(() => marqueeInProgress = true);

  @visibleForTesting
  void simulateMarqueeEnd() => setState(() => marqueeInProgress = false);

  void _enterSelectMode() {
    setState(() {
      _selectMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  void _clearDesktopSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    final sessions = ref.read(filteredSessionsProvider);
    setState(() {
      _selectedIds.addAll(sessions.map((s) => s.id));
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Sessions',
      content: Text('Delete $count selected session(s)?\n\nThis cannot be undone.'),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).deleteMultiple(Set.of(_selectedIds));
      if (_selectMode) {
        _exitSelectMode();
      } else {
        _clearDesktopSelection();
      }
    }
  }

  Future<void> _moveSelected(BuildContext context) async {
    if (_selectedIds.isEmpty) return;
    final store = ref.read(sessionStoreProvider);
    final allGroups = <String>{'', ...store.groups(), ...store.emptyGroups};

    final selected = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allGroups.length,
            itemBuilder: (ctx, index) {
              final group = allGroups.elementAt(index);
              return ListTile(
                leading: Icon(group.isEmpty ? Icons.home : Icons.folder),
                title: Text(group.isEmpty ? '/ (root)' : group),
                onTap: () => Navigator.of(ctx).pop(group),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await ref.read(sessionProvider.notifier).moveMultiple(Set.of(_selectedIds), selected);
      if (_selectMode) {
        _exitSelectMode();
      } else {
        _clearDesktopSelection();
      }
    }
  }

  /// Build set of session IDs that have an active connection.
  Set<String> _connectedSessionIds(WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? [];
    final activeConfigs = connections
        .where((c) => c.isConnected)
        .map((c) => '${c.sshConfig.host}:${c.sshConfig.effectivePort}:${c.sshConfig.user}')
        .toSet();
    final sessions = ref.watch(sessionProvider);
    return {
      for (final s in sessions)
        if (activeConfigs.contains('${s.server.host}:${s.port}:${s.server.user}'))
          s.id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(filteredSessionTreeProvider);
    final searchQuery = ref.watch(sessionSearchProvider);
    final isEmpty = ref.watch(sessionProvider.select((s) => s.isEmpty));

    final mobile = isMobilePlatform;

    return Container(
      color: AppTheme.bg1,
      child: Column(
      children: [
        if (_selectMode && mobile)
          _SelectActionBar(
            selectedCount: _selectedIds.length,
            onSelectAll: _selectAll,
            onDelete: () => _deleteSelected(context),
            onMove: () => _moveSelected(context),
            onCancel: _exitSelectMode,
          )
        else ...[
          // Header with title + add/select buttons
          _PanelHeader(
            onAddFolder: () => _createFolder(context, ref, ''),
            onSelect: mobile && !isEmpty ? _enterSelectMode : null,
          ),
          // Search bar
          _SearchBar(
            value: searchQuery,
            onChanged: (v) => ref.read(sessionSearchProvider.notifier).set(v),
          ),
          // Desktop marquee selection is shown inline via row highlights.
          // Bulk actions available via right-click context menu.
        ],
        // Tree view
        Expanded(
          child: isEmpty
              ? _EmptyState(onAdd: () => _addSession(context, ref))
              : SessionTreeView(
                  tree: tree,
                  connectedSessionIds: _connectedSessionIds(ref),
                  selectMode: mobile && _selectMode,
                  selectedIds: _selectedIds,
                  onToggleSelected: _toggleSelected,
                  crossMarquee: widget.crossMarquee,
                  onSessionDoubleTap: widget.onConnect,
                  onSessionContextMenu: (session, position) {
                    _showContextMenu(context, ref, session, position);
                  },
                  onGroupContextMenu: (groupPath, position) {
                    _showGroupContextMenu(context, ref, groupPath, position);
                  },
                  onBackgroundContextMenu: (position) {
                    _showGroupContextMenu(context, ref, '', position);
                  },
                  onSessionMoved: (sessionId, targetGroup) {
                    ref.read(sessionProvider.notifier).moveSession(sessionId, targetGroup);
                  },
                  onGroupMoved: (groupPath, targetParent) {
                    ref.read(sessionProvider.notifier).moveGroup(groupPath, targetParent);
                  },
                  onMarqueeStart: () => setState(() => marqueeInProgress = true),
                  onMarqueeEnd: () => setState(() => marqueeInProgress = false),
                  onMarqueeSelect: (ids) {
                    setState(() {
                      _selectedIds
                        ..clear()
                        ..addAll(ids);
                    });
                  },
                ),
        ),
        // Footer
        const _SidebarFooter(),
      ],
    ),
    );
  }

  Future<void> _handleDialogResult(WidgetRef ref, SessionDialogResult result) async {
    switch (result) {
      case ConnectOnlyResult(:final config):
        widget.onQuickConnect(config);
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect) widget.onConnect(session);
    }
  }

  Future<void> _addSession(BuildContext context, WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    final result = await SessionEditDialog.show(
      context,
      existingGroups: store.groups(),
    );
    if (result == null) return;
    await _handleDialogResult(ref, result);
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Session session,
    Offset position,
  ) {
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: 'Terminal',
          icon: Icons.terminal,
          color: AppTheme.blue,
          onTap: () => widget.onConnect(session),
        ),
        if (widget.onSftpConnect != null)
          ContextMenuItem(
            label: 'Files',
            icon: Icons.folder,
            color: AppTheme.yellow,
            onTap: () => widget.onSftpConnect?.call(session),
          ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: 'Edit Connection',
          icon: Icons.settings,
          shortcut: 'E',
          onTap: () => _editSession(context, ref, session),
        ),
        ContextMenuItem(
          label: 'Duplicate',
          icon: Icons.copy,
          shortcut: 'Ctrl+D',
          onTap: () => ref.read(sessionProvider.notifier).duplicate(session.id),
        ),
        if (isMobilePlatform)
          ContextMenuItem(
            label: 'Move to...',
            icon: Icons.drive_file_move,
            onTap: () => _moveSession(context, ref, session),
          ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: 'Delete',
          icon: Icons.delete,
          color: AppTheme.red,
          shortcut: 'Del',
          onTap: () => _confirmDelete(context, ref, session),
        ),
      ],
    );
  }

  Future<void> _moveSession(BuildContext context, WidgetRef ref, Session session) async {
    final store = ref.read(sessionStoreProvider);
    final allGroups = <String>{'', ...store.groups(), ...store.emptyGroups};

    final selected = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allGroups.length,
            itemBuilder: (ctx, index) => _buildMoveGroupTile(
              ctx, allGroups.elementAt(index), session.group,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      ref.read(sessionProvider.notifier).moveSession(session.id, selected);
    }
  }

  Widget _buildMoveGroupTile(BuildContext context, String group, String currentGroup) {
    final isCurrent = group == currentGroup;
    return ListTile(
      leading: Icon(
        group.isEmpty ? Icons.home : Icons.folder,
        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        group.isEmpty ? '/ (root)' : group,
        style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : null),
      ),
      trailing: isCurrent ? const Icon(Icons.check, size: 18) : null,
      onTap: isCurrent ? null : () => Navigator.of(context).pop(group),
    );
  }

  Future<void> _editSession(BuildContext context, WidgetRef ref, Session session) async {
    final store = ref.read(sessionStoreProvider);
    final result = await SessionEditDialog.show(
      context,
      session: session,
      existingGroups: store.groups(),
    );
    if (result == null) return;
    if (result is SaveResult) {
      await ref.read(sessionProvider.notifier).update(result.session);
    }
  }

  void _showGroupContextMenu(
    BuildContext context,
    WidgetRef ref,
    String groupPath,
    Offset position,
  ) {
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: 'New Connection',
          icon: Icons.add,
          onTap: () => _addSessionInGroup(context, ref, groupPath),
        ),
        ContextMenuItem(
          label: _kNewFolder,
          icon: Icons.create_new_folder,
          onTap: () => _createFolder(context, ref, groupPath),
        ),
        if (groupPath.isNotEmpty) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: 'Rename Group',
            icon: Icons.drive_file_rename_outline,
            shortcut: 'F2',
            onTap: () => _renameFolder(context, ref, groupPath),
          ),
          ContextMenuItem(
            label: 'Delete Group',
            icon: Icons.delete,
            color: AppTheme.red,
            onTap: () => _confirmDeleteFolder(context, ref, groupPath),
          ),
        ],
      ],
    );
  }

  Future<void> _addSessionInGroup(BuildContext context, WidgetRef ref, String groupPath) async {
    final store = ref.read(sessionStoreProvider);
    final result = await SessionEditDialog.show(
      context,
      existingGroups: store.groups(),
      defaultGroup: groupPath,
    );
    if (result == null) return;
    await _handleDialogResult(ref, result);
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref, String parentGroup) async {
    final existingGroups = _collectAllGroupPaths(ref);

    final result = await _showFolderNameDialog(
      context,
      title: _kNewFolder,
      confirmLabel: 'Create',
      existingGroups: existingGroups,
      parentPath: parentGroup,
    );

    if (result == null || result.trim().isEmpty) return;

    final newGroup = parentGroup.isEmpty ? result.trim() : '$parentGroup/${result.trim()}';
    await ref.read(sessionProvider.notifier).addEmptyGroup(newGroup);
  }

  Future<void> _renameFolder(BuildContext context, WidgetRef ref, String groupPath) async {
    // Extract the folder's own name (last segment)
    final parts = groupPath.split('/');
    final currentName = parts.last;
    final parentPath = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';

    final existingGroups = _collectAllGroupPaths(ref);

    final result = await _showFolderNameDialog(
      context,
      title: 'Rename Folder',
      confirmLabel: 'Rename',
      initialValue: currentName,
      existingGroups: existingGroups,
      parentPath: parentPath,
      currentName: currentName,
    );

    if (result == null || result.trim().isEmpty || result.trim() == currentName) return;

    final newPath = parentPath.isEmpty ? result.trim() : '$parentPath/${result.trim()}';
    await ref.read(sessionProvider.notifier).renameGroup(groupPath, newPath);
  }

  /// Collects all existing group paths including implicit parent segments.
  /// E.g. "A/B/C" implies "A" and "A/B" also exist.
  Set<String> _collectAllGroupPaths(WidgetRef ref) {
    final store = ref.read(sessionStoreProvider);
    final result = <String>{};
    for (final g in [...store.groups(), ...store.emptyGroups]) {
      final parts = g.split('/');
      for (var i = 1; i <= parts.length; i++) {
        result.add(parts.sublist(0, i).join('/'));
      }
    }
    return result;
  }

  /// Shows a folder name input dialog with duplicate validation.
  /// Returns the entered name, or null if cancelled.
  Future<String?> _showFolderNameDialog(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required Set<String> existingGroups,
    required String parentPath,
    String? initialValue,
    String? currentName,
  }) async {
    final nameCtrl = TextEditingController(text: initialValue ?? '');
    String? errorText;

    try {
      return await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return _buildFolderNameAlert(
              ctx,
              title: title,
              confirmLabel: confirmLabel,
              nameCtrl: nameCtrl,
              errorText: errorText,
              onChanged: (_) {
                final name = nameCtrl.text.trim();
                final fullPath = parentPath.isEmpty ? name : '$parentPath/$name';
                final isDuplicate = name.isNotEmpty
                    && name != currentName
                    && existingGroups.contains(fullPath);
                setDialogState(() {
                  errorText = isDuplicate ? 'Folder "$name" already exists' : null;
                });
              },
              hintText: 'e.g. Production',
            );
          },
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  Widget _buildFolderNameAlert(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required TextEditingController nameCtrl,
    required String? errorText,
    required ValueChanged<String> onChanged,
    String? hintText,
  }) {
    return Dialog(
      backgroundColor: AppTheme.bg1,
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.fg,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, size: 13, color: AppTheme.fgDim),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FOLDER NAME',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppTheme.fgFaint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      color: AppTheme.fg,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        color: AppTheme.fgFaint,
                      ),
                      filled: true,
                      fillColor: AppTheme.bg3,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppTheme.borderLight),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppTheme.borderLight),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppTheme.accent),
                      ),
                      errorBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppTheme.red),
                      ),
                      errorText: errorText,
                      errorStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        color: AppTheme.red,
                      ),
                    ),
                    onChanged: onChanged,
                    onFieldSubmitted: (v) {
                      if (errorText == null && v.trim().isNotEmpty) {
                        Navigator.of(context).pop(v);
                      }
                    },
                  ),
                ],
              ),
            ),
            // Footer
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.fgDim,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: errorText == null
                        ? () => Navigator.of(context).pop(nameCtrl.text)
                        : null,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: errorText == null ? AppTheme.accent : AppTheme.bg4,
                      ),
                      child: Text(
                        confirmLabel,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: errorText == null ? Colors.white : AppTheme.fgFaint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteFolder(BuildContext context, WidgetRef ref, String groupPath) async {
    final store = ref.read(sessionStoreProvider);
    final sessionCount = store.countSessionsInGroup(groupPath);
    final folderName = groupPath.split('/').last;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Folder',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delete folder "$folderName"?'),
          if (sessionCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'This will also delete $sessionCount session(s) inside.',
              style: const TextStyle(color: AppTheme.disconnected, fontSize: 13),
            ),
          ],
        ],
      ),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).deleteGroup(groupPath);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Session session) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Session',
      content: Text('Delete "${session.label.isNotEmpty ? session.label : session.displayName}"?'),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).delete(session.id);
    }
  }

}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAddFolder;
  final VoidCallback? onSelect;

  const _PanelHeader({required this.onAddFolder, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Text(
            'SESSIONS',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppTheme.fgFaint,
            ),
          ),
          const Spacer(),
          if (onSelect != null)
            IconButton(
              onPressed: onSelect,
              icon: const Icon(Icons.checklist, size: 18),
              tooltip: 'Select',
              visualDensity: VisualDensity.compact,
            ),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              onPressed: onAddFolder,
              icon: const Icon(Icons.create_new_folder, size: 14),
              tooltip: _kNewFolder,
              padding: EdgeInsets.zero,
              color: AppTheme.fgDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onCancel;

  const _SelectActionBar({
    required this.selectedCount,
    required this.onSelectAll,
    required this.onDelete,
    required this.onMove,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            '$selectedCount selected',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSelectAll,
            icon: const Icon(Icons.select_all, size: 18),
            tooltip: 'Select All',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: selectedCount > 0 ? onMove : null,
            icon: const Icon(Icons.drive_file_move, size: 18),
            tooltip: 'Move to...',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: selectedCount > 0 ? onDelete : null,
            icon: Icon(Icons.delete, size: 18, color: selectedCount > 0 ? AppTheme.disconnected : null),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 12, color: AppTheme.fgFaint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Filter...',
                  hintStyle: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    color: AppTheme.fgFaint,
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: AppTheme.fg,
                ),
                onChanged: onChanged,
              ),
            ),
            if (value.isNotEmpty)
              GestureDetector(
                onTap: () => onChanged(''),
                child: const Icon(Icons.close, size: 12, color: AppTheme.fgFaint),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            'No saved sessions',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Session', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? [];
    final activeCount = connections.where((c) => c.isConnected).length;
    final savedCount = ref.watch(sessionProvider).length;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi, size: 10,
              color: activeCount > 0 ? AppTheme.green : AppTheme.fgFaint),
          const SizedBox(width: 6),
          Text(
            '$activeCount active',
            style: AppFonts.inter(fontSize: 10, color: AppTheme.fgFaint),
          ),
          const Spacer(),
          Text(
            '$savedCount saved',
            style: AppFonts.inter(fontSize: 10, color: AppTheme.fgFaint),
          ),
        ],
      ),
    );
  }
}

