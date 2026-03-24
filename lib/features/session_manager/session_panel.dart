import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import 'session_edit_dialog.dart';
import 'session_tree_view.dart';

/// Session sidebar — tree view + search + actions.
class SessionPanel extends ConsumerWidget {
  final void Function(Session session) onConnect;
  final void Function(Session session)? onSftpConnect;

  const SessionPanel({
    super.key,
    required this.onConnect,
    this.onSftpConnect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(filteredSessionTreeProvider);
    final searchQuery = ref.watch(sessionSearchProvider);
    final sessions = ref.watch(sessionProvider);

    return Column(
      children: [
        // Header with title + add button
        _PanelHeader(
          onAdd: () => _addSession(context, ref),
        ),
        // Search bar
        _SearchBar(
          value: searchQuery,
          onChanged: (v) => ref.read(sessionSearchProvider.notifier).state = v,
        ),
        // Tree view
        Expanded(
          child: sessions.isEmpty
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
                ),
        ),
      ],
    );
  }

  Future<void> _addSession(BuildContext context, WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    final session = await SessionEditDialog.show(
      context,
      existingGroups: store.groups(),
    );
    if (session != null) {
      await ref.read(sessionProvider.notifier).add(session);
    }
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Session session,
    Offset position,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'connect', child: ListTile(leading: Icon(Icons.terminal, size: 18), title: Text('SSH Connect'), dense: true, contentPadding: EdgeInsets.zero)),
        if (onSftpConnect != null)
          const PopupMenuItem(value: 'sftp', child: ListTile(leading: Icon(Icons.folder, size: 18), title: Text('SFTP Only'), dense: true, contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, size: 18), title: Text('Edit'), dense: true, contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy, size: 18), title: Text('Duplicate'), dense: true, contentPadding: EdgeInsets.zero)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, size: 18, color: AppTheme.disconnected), title: Text('Delete', style: TextStyle(color: AppTheme.disconnected)), dense: true, contentPadding: EdgeInsets.zero)),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      switch (value) {
        case 'connect':
          onConnect(session);
        case 'sftp':
          onSftpConnect?.call(session);
        case 'edit':
          _editSession(context, ref, session);
        case 'duplicate':
          ref.read(sessionProvider.notifier).duplicate(session.id);
        case 'delete':
          _confirmDelete(context, ref, session);
      }
    });
  }

  Future<void> _editSession(BuildContext context, WidgetRef ref, Session session) async {
    final store = ref.read(sessionStoreProvider);
    final updated = await SessionEditDialog.show(
      context,
      session: session,
      existingGroups: store.groups(),
    );
    if (updated != null) {
      await ref.read(sessionProvider.notifier).update(updated);
    }
  }

  void _showGroupContextMenu(
    BuildContext context,
    WidgetRef ref,
    String groupPath,
    Offset position,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx + 1, position.dy + 1,
      ),
      items: [
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
            title: Text('New Folder'),
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
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      switch (value) {
        case 'new_session':
          _addSessionInGroup(context, ref, groupPath);
        case 'new_folder':
          _createFolder(context, ref, groupPath);
        case 'rename':
          _renameFolder(context, ref, groupPath);
        case 'delete':
          _confirmDeleteFolder(context, ref, groupPath);
      }
    });
  }

  Future<void> _addSessionInGroup(BuildContext context, WidgetRef ref, String groupPath) async {
    final store = ref.read(sessionStoreProvider);
    final session = await SessionEditDialog.show(
      context,
      existingGroups: store.groups(),
      defaultGroup: groupPath,
    );
    if (session != null) {
      await ref.read(sessionProvider.notifier).add(session);
    }
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref, String parentGroup) async {
    final store = ref.read(sessionStoreProvider);
    // Collect all existing group paths including parent segments.
    // E.g. "A/B/C" implies "A" and "A/B" also exist.
    final existingGroups = <String>{};
    for (final g in [...store.groups(), ...store.emptyGroups]) {
      final parts = g.split('/');
      for (var i = 1; i <= parts.length; i++) {
        existingGroups.add(parts.sublist(0, i).join('/'));
      }
    }

    final nameCtrl = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void validate() {
            final name = nameCtrl.text.trim();
            final fullPath = parentGroup.isEmpty ? name : '$parentGroup/$name';
            if (name.isNotEmpty && existingGroups.contains(fullPath)) {
              setDialogState(() => errorText = 'Folder "$name" already exists');
            } else {
              setDialogState(() => errorText = null);
            }
          }

          return AlertDialog(
            title: const Text('New Folder'),
            content: TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Folder name',
                hintText: 'e.g. Production',
                errorText: errorText,
              ),
              onChanged: (_) => validate(),
              onSubmitted: (v) {
                if (errorText == null && v.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(v);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: errorText == null
                    ? () => Navigator.of(ctx).pop(nameCtrl.text)
                    : null,
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
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

    final nameCtrl = TextEditingController(text: currentName);
    String? errorText;

    // Collect existing group paths for validation
    final store = ref.read(sessionStoreProvider);
    final existingGroups = <String>{};
    for (final g in [...store.groups(), ...store.emptyGroups]) {
      final gParts = g.split('/');
      for (var i = 1; i <= gParts.length; i++) {
        existingGroups.add(gParts.sublist(0, i).join('/'));
      }
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void validate() {
            final name = nameCtrl.text.trim();
            final newPath = parentPath.isEmpty ? name : '$parentPath/$name';
            if (name.isEmpty) {
              setDialogState(() => errorText = null);
            } else if (name == currentName) {
              setDialogState(() => errorText = null);
            } else if (existingGroups.contains(newPath)) {
              setDialogState(() => errorText = 'Folder "$name" already exists');
            } else {
              setDialogState(() => errorText = null);
            }
          }

          return AlertDialog(
            title: const Text('Rename Folder'),
            content: TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Folder name',
                errorText: errorText,
              ),
              onChanged: (_) => validate(),
              onSubmitted: (v) {
                if (errorText == null && v.trim().isNotEmpty && v.trim() != currentName) {
                  Navigator.of(ctx).pop(v);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: errorText == null
                    ? () => Navigator.of(ctx).pop(nameCtrl.text)
                    : null,
                child: const Text('Rename'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || result.trim().isEmpty || result.trim() == currentName) return;

    final newPath = parentPath.isEmpty ? result.trim() : '$parentPath/${result.trim()}';
    await ref.read(sessionProvider.notifier).renameGroup(groupPath, newPath);
  }

  Future<void> _confirmDeleteFolder(BuildContext context, WidgetRef ref, String groupPath) async {
    final store = ref.read(sessionStoreProvider);
    final sessionCount = store.countSessionsInGroup(groupPath);
    final folderName = groupPath.split('/').last;

    final confirmed = await showDialog<bool>(
      context: context,
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
}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAdd;

  const _PanelHeader({required this.onAdd});

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
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'New Session',
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
