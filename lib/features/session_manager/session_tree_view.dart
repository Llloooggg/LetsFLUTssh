import 'package:flutter/material.dart';

import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../theme/app_theme.dart';

/// Hierarchical tree view of sessions with nested group folders.
class SessionTreeView extends StatefulWidget {
  final List<SessionTreeNode> tree;
  final void Function(Session session)? onSessionTap;
  final void Function(Session session)? onSessionDoubleTap;
  final void Function(Session session, Offset position)? onSessionContextMenu;
  final void Function(String groupPath, Offset position)? onGroupContextMenu;
  /// Context menu on empty space (no group path).
  final void Function(Offset position)? onBackgroundContextMenu;

  const SessionTreeView({
    super.key,
    required this.tree,
    this.onSessionTap,
    this.onSessionDoubleTap,
    this.onSessionContextMenu,
    this.onGroupContextMenu,
    this.onBackgroundContextMenu,
  });

  @override
  State<SessionTreeView> createState() => _SessionTreeViewState();
}

class _SessionTreeViewState extends State<SessionTreeView> {
  final _expandedGroups = <String>{};
  String? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    // Expand all groups by default
    _expandAllGroups(widget.tree);
  }

  void _expandAllGroups(List<SessionTreeNode> nodes) {
    for (final node in nodes) {
      if (node.isGroup) {
        _expandedGroups.add(node.fullPath);
        _expandAllGroups(node.children);
      }
    }
  }

  /// Flattened visible nodes for ListView.builder (avoids recursive widget build).
  List<(SessionTreeNode, int)> _flattenVisible(List<SessionTreeNode> nodes, int depth) {
    final result = <(SessionTreeNode, int)>[];
    for (final node in nodes) {
      result.add((node, depth));
      if (node.isGroup && _expandedGroups.contains(node.fullPath)) {
        result.addAll(_flattenVisible(node.children, depth + 1));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tree.isEmpty) {
      return Center(
        child: Text(
          'No sessions',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    final flatNodes = _flattenVisible(widget.tree, 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onSecondaryTapUp: (d) {
            widget.onBackgroundContextMenu?.call(d.globalPosition);
          },
          behavior: HitTestBehavior.translucent,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: flatNodes.length,
            itemExtent: 30,
            itemBuilder: (context, index) {
              final (node, depth) = flatNodes[index];
              if (node.isGroup) {
                return _buildGroupTile(node, depth);
              } else {
                return _buildSessionTile(node, depth);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildGroupTile(SessionTreeNode node, int depth) {
    final expanded = _expandedGroups.contains(node.fullPath);
    return GestureDetector(
      onSecondaryTapUp: (d) {
        widget.onGroupContextMenu?.call(node.fullPath, d.globalPosition);
      },
      child: InkWell(
        onTap: () {
          setState(() {
            if (expanded) {
              _expandedGroups.remove(node.fullPath);
            } else {
              _expandedGroups.add(node.fullPath);
            }
          });
        },
        child: Padding(
          padding: EdgeInsets.only(left: 8.0 + depth * 16.0),
          child: SizedBox(
            height: 30,
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.folder_open : Icons.folder,
                  size: 16,
                  color: AppTheme.folderColor(Theme.of(context).brightness),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${node.sessionCount}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionTile(SessionTreeNode node, int depth) {
    final session = node.session!;
    final isSelected = session.id == _selectedSessionId;
    final theme = Theme.of(context);

    return GestureDetector(
      onDoubleTap: () => widget.onSessionDoubleTap?.call(session),
      onSecondaryTapUp: (details) {
        widget.onSessionContextMenu?.call(session, details.globalPosition);
      },
      child: InkWell(
        onTap: () {
          setState(() => _selectedSessionId = session.id);
          widget.onSessionTap?.call(session);
        },
        child: Container(
          padding: EdgeInsets.only(left: 12.0 + depth * 16.0, right: 8),
          height: 30,
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : null,
          child: Row(
            children: [
              Icon(
                _authIcon(session.authType),
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${session.host}:${session.port}',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _authIcon(AuthType type) {
    switch (type) {
      case AuthType.password:
        return Icons.lock;
      case AuthType.key:
        return Icons.vpn_key;
      case AuthType.keyWithPassword:
        return Icons.enhanced_encryption;
    }
  }
}
