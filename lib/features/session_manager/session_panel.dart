import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../providers/session_provider.dart';
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
        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, size: 18, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), dense: true, contentPadding: EdgeInsets.zero)),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
