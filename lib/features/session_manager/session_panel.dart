import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/platform.dart';
import 'session_edit_dialog.dart';
import 'session_tree_view.dart';

const _kNewFolder = 'New Folder';

/// Session sidebar — tree view + search + actions.
class SessionPanel extends ConsumerWidget {
  final void Function(Session session) onConnect;
  final void Function(SSHConfig config) onQuickConnect;
  final void Function(Session session)? onSftpConnect;

  const SessionPanel({
    super.key,
    required this.onConnect,
    required this.onQuickConnect,
    this.onSftpConnect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(filteredSessionTreeProvider);
    final searchQuery = ref.watch(sessionSearchProvider);
    final isEmpty = ref.watch(sessionProvider.select((s) => s.isEmpty));

    return Column(
      children: [
        // Header with title + add button
        _PanelHeader(
          onAddFolder: () => _createFolder(context, ref, ''),
        ),
        // Search bar
        _SearchBar(
          value: searchQuery,
          onChanged: (v) => ref.read(sessionSearchProvider.notifier).state = v,
        ),
        // Tree view
        Expanded(
          child: isEmpty
              ? _EmptyState(onAdd: () => _addSession(context, ref))
              : SessionTreeView(
                  tree: tree,
                  onSessionDoubleTap: onConnect,
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
                ),
        ),
      ],
    );
  }

  Future<void> _handleDialogResult(WidgetRef ref, SessionDialogResult result) async {
    switch (result) {
      case ConnectOnlyResult(:final config):
        onQuickConnect(config);
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect) onConnect(session);
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
    return [
      const PopupMenuItem(value: 'connect', child: ListTile(leading: Icon(Icons.terminal, size: 18), title: Text('SSH'), dense: true, contentPadding: EdgeInsets.zero)),
      if (onSftpConnect != null)
        const PopupMenuItem(value: 'sftp', child: ListTile(leading: Icon(Icons.folder, size: 18), title: Text('SFTP'), dense: true, contentPadding: EdgeInsets.zero)),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, size: 18), title: Text('Edit'), dense: true, contentPadding: EdgeInsets.zero)),
      const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy, size: 18), title: Text('Duplicate'), dense: true, contentPadding: EdgeInsets.zero)),
      if (isMobilePlatform)
        const PopupMenuItem(value: 'move', child: ListTile(leading: Icon(Icons.drive_file_move, size: 18), title: Text('Move to...'), dense: true, contentPadding: EdgeInsets.zero)),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, size: 18, color: AppTheme.disconnected), title: Text('Delete', style: TextStyle(color: AppTheme.disconnected)), dense: true, contentPadding: EdgeInsets.zero)),
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
        onConnect(session);
      case 'sftp':
        onSftpConnect?.call(session);
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
    return [
      const PopupMenuItem(
        value: 'new_session',
        child: ListTile(
          leading: Icon(Icons.add, size: 18),
          title: Text('New Session'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'new_folder',
        child: ListTile(
          leading: Icon(Icons.create_new_folder, size: 18),
          title: Text(_kNewFolder),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (groupPath.isNotEmpty) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline, size: 18),
            title: Text('Rename'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete, size: 18, color: AppTheme.disconnected),
            title: Text('Delete Folder', style: TextStyle(color: AppTheme.disconnected)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      if (groupPath.isEmpty && hasSessions) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete_all',
          child: ListTile(
            leading: Icon(Icons.delete_forever, size: 18, color: AppTheme.disconnected),
            title: Text('Delete All Sessions', style: TextStyle(color: AppTheme.disconnected)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
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

    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.disconnected),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionProvider.notifier).deleteGroup(groupPath);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Delete "${session.label.isNotEmpty ? session.label : session.displayName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.disconnected),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionProvider.notifier).delete(session.id);
    }
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final count = ref.read(sessionProvider).length;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Sessions'),
        content: Text('Delete all $count session(s) and all folders?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.disconnected),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionProvider.notifier).deleteAll();
    }
  }
}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAddFolder;

  const _PanelHeader({required this.onAddFolder});

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
