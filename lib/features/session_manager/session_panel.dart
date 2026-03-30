import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
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
  bool _marqueeInProgress = false;

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
  void simulateMarqueeStart() => setState(() => _marqueeInProgress = true);

  @visibleForTesting
  void simulateMarqueeEnd() => setState(() => _marqueeInProgress = false);

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

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(filteredSessionTreeProvider);
    final searchQuery = ref.watch(sessionSearchProvider);
    final isEmpty = ref.watch(sessionProvider.select((s) => s.isEmpty));

    final mobile = isMobilePlatform;

    return Column(
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
          // Desktop: compact action bar when marquee-selected
          // Suppressed during active marquee drag to avoid layout shift.
          if (!mobile && _selectedIds.isNotEmpty && !_marqueeInProgress)
            _SelectActionBar(
              selectedCount: _selectedIds.length,
              onSelectAll: _selectAll,
              onDelete: () => _deleteSelected(context),
              onMove: () => _moveSelected(context),
              onCancel: _clearDesktopSelection,
            ),
        ],
        // Tree view
        Expanded(
          child: isEmpty
              ? _EmptyState(onAdd: () => _addSession(context, ref))
              : SessionTreeView(
                  tree: tree,
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
                  onMarqueeStart: () => setState(() => _marqueeInProgress = true),
                  onMarqueeEnd: () => setState(() => _marqueeInProgress = false),
                  onMarqueeSelect: (ids) {
                    setState(() {
                      _selectedIds
                        ..clear()
                        ..addAll(ids);
                    });
                  },
                ),
        ),
      ],
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
    showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: _sessionMenuItems(),
    ).then((value) {
      if (value == null || !context.mounted) return;
      _handleSessionMenuAction(context, ref, session, value);
    });
  }

  List<PopupMenuEntry<String>> _sessionMenuItems() {
    final h = isMobilePlatform ? 48.0 : 32.0;
    return [
      PopupMenuItem(height: h, value: 'connect', child: const _MenuRow(icon: Icons.terminal, text: 'SSH')),
      if (widget.onSftpConnect != null)
        PopupMenuItem(height: h, value: 'sftp', child: const _MenuRow(icon: Icons.folder, text: 'SFTP')),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(height: h, value: 'edit', child: const _MenuRow(icon: Icons.edit, text: 'Edit')),
      PopupMenuItem(height: h, value: 'duplicate', child: const _MenuRow(icon: Icons.copy, text: 'Duplicate')),
      if (isMobilePlatform)
        PopupMenuItem(height: h, value: 'move', child: const _MenuRow(icon: Icons.drive_file_move, text: 'Move to...')),
      const PopupMenuDivider(height: 1),
      PopupMenuItem(height: h, value: 'delete', child: const _MenuRow(icon: Icons.delete, text: 'Delete', color: AppTheme.disconnected)),
    ];
  }

  void _handleSessionMenuAction(
    BuildContext context,
    WidgetRef ref,
    Session session,
    String value,
  ) {
    switch (value) {
      case 'connect':
        widget.onConnect(session);
      case 'sftp':
        widget.onSftpConnect?.call(session);
      case 'edit':
        _editSession(context, ref, session);
      case 'duplicate':
        ref.read(sessionProvider.notifier).duplicate(session.id);
      case 'move':
        _moveSession(context, ref, session);
      case 'delete':
        _confirmDelete(context, ref, session);
    }
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
    final hasSessions = ref.read(sessionProvider).isNotEmpty;
    showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx + 1, position.dy + 1,
      ),
      items: _groupMenuItems(groupPath, hasSessions),
    ).then((value) {
      if (value == null || !context.mounted) return;
      _handleGroupMenuAction(context, ref, groupPath, value);
    });
  }

  List<PopupMenuEntry<String>> _groupMenuItems(String groupPath, bool hasSessions) {
    final h = isMobilePlatform ? 48.0 : 32.0;
    return [
      PopupMenuItem(height: h, value: 'new_session', child: const _MenuRow(icon: Icons.add, text: 'New Session')),
      PopupMenuItem(height: h, value: 'new_folder', child: const _MenuRow(icon: Icons.create_new_folder, text: _kNewFolder)),
      if (groupPath.isNotEmpty) ...[
        const PopupMenuDivider(height: 1),
        PopupMenuItem(height: h, value: 'rename', child: const _MenuRow(icon: Icons.drive_file_rename_outline, text: 'Rename')),
        PopupMenuItem(height: h, value: 'delete', child: const _MenuRow(icon: Icons.delete, text: 'Delete Folder', color: AppTheme.disconnected)),
      ],
      if (groupPath.isEmpty && hasSessions) ...[
        const PopupMenuDivider(height: 1),
        PopupMenuItem(height: h, value: 'delete_all', child: const _MenuRow(icon: Icons.delete_forever, text: 'Delete All Sessions', color: AppTheme.disconnected)),
      ],
    ];
  }

  void _handleGroupMenuAction(
    BuildContext context,
    WidgetRef ref,
    String groupPath,
    String value,
  ) {
    switch (value) {
      case 'new_session':
        _addSessionInGroup(context, ref, groupPath);
      case 'new_folder':
        _createFolder(context, ref, groupPath);
      case 'rename':
        _renameFolder(context, ref, groupPath);
      case 'delete':
        _confirmDeleteFolder(context, ref, groupPath);
      case 'delete_all':
        _confirmDeleteAll(context, ref);
    }
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

  AlertDialog _buildFolderNameAlert(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required TextEditingController nameCtrl,
    required String? errorText,
    required ValueChanged<String> onChanged,
    String? hintText,
  }) {
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Folder name',
          hintText: hintText,
          errorText: errorText,
        ),
        onChanged: onChanged,
        onSubmitted: (v) {
          if (errorText == null && v.trim().isNotEmpty) {
            Navigator.of(context).pop(v);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: errorText == null
              ? () => Navigator.of(context).pop(nameCtrl.text)
              : null,
          child: Text(confirmLabel),
        ),
      ],
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

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final count = ref.read(sessionProvider).length;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete All Sessions',
      confirmLabel: 'Delete All',
      content: Text('Delete all $count session(s) and all folders?\n\nThis cannot be undone.'),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).deleteAll();
    }
  }
}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAddFolder;
  final VoidCallback? onSelect;

  const _PanelHeader({required this.onAddFolder, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Text(
            'Sessions',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (onSelect != null)
            IconButton(
              onPressed: onSelect,
              icon: const Icon(Icons.checklist, size: 18),
              tooltip: 'Select',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: onAddFolder,
            icon: const Icon(Icons.create_new_folder, size: 18),
            tooltip: _kNewFolder,
            visualDensity: VisualDensity.compact,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SizedBox(
        height: 32,
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Search...',
            prefixIcon: const Icon(Icons.search, size: 16),
            suffixIcon: value.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: () => onChanged(''),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            filled: true,
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: onChanged,
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

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _MenuRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final mobile = isMobilePlatform;
    return Row(
      children: [
        Icon(icon, size: mobile ? 20 : 16, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: mobile ? 15 : 13, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
