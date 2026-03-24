import 'package:flutter/material.dart';

import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../theme/app_theme.dart';

/// Drag data: either a session or a group path.
sealed class SessionDragData {}

class SessionDrag extends SessionDragData {
  final Session session;
  SessionDrag(this.session);
}

class GroupDrag extends SessionDragData {
  final String groupPath;
  GroupDrag(this.groupPath);
}

/// Hierarchical tree view of sessions with nested group folders.
/// Supports drag&drop: sessions into folders, folders into folders.
class SessionTreeView extends StatefulWidget {
  final List<SessionTreeNode> tree;
  final void Function(Session session)? onSessionTap;
  final void Function(Session session)? onSessionDoubleTap;
  final void Function(Session session, Offset position)? onSessionContextMenu;
  final void Function(String groupPath, Offset position)? onGroupContextMenu;
  /// Context menu on empty space (no group path).
  final void Function(Offset position)? onBackgroundContextMenu;
  /// Called when a session is dropped onto a group (or root).
  final void Function(String sessionId, String targetGroup)? onSessionMoved;
  /// Called when a group is dropped onto another group (or root).
  final void Function(String groupPath, String targetParent)? onGroupMoved;

  const SessionTreeView({
    super.key,
    required this.tree,
    this.onSessionTap,
    this.onSessionDoubleTap,
    this.onSessionContextMenu,
    this.onGroupContextMenu,
    this.onBackgroundContextMenu,
    this.onSessionMoved,
    this.onGroupMoved,
  });

  @override
  State<SessionTreeView> createState() => _SessionTreeViewState();
}

class _SessionTreeViewState extends State<SessionTreeView> {
  final _expandedGroups = <String>{};
  String? _selectedSessionId;
  String? _dropTargetGroup; // highlight on drag hover

  @override
  void initState() {
    super.initState();
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

  /// Flattened visible nodes for ListView.builder.
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

  bool _canAcceptDrop(SessionDragData data, String targetGroup) {
    if (data is SessionDrag) {
      // Don't drop on own group
      return data.session.group != targetGroup;
    } else if (data is GroupDrag) {
      // Can't drop on self or into own subtree
      if (data.groupPath == targetGroup) return false;
      if (targetGroup.startsWith('${data.groupPath}/')) return false;
      // Can't drop on own current parent
      final parts = data.groupPath.split('/');
      final currentParent = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('/')
          : '';
      return currentParent != targetGroup;
    }
    return false;
  }

  void _handleDrop(SessionDragData data, String targetGroup) {
    if (data is SessionDrag) {
      widget.onSessionMoved?.call(data.session.id, targetGroup);
    } else if (data is GroupDrag) {
      widget.onGroupMoved?.call(data.groupPath, targetGroup);
    }
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
          child: DragTarget<SessionDragData>(
            onWillAcceptWithDetails: (details) => _canAcceptDrop(details.data, ''),
            onAcceptWithDetails: (details) {
              setState(() => _dropTargetGroup = null);
              _handleDrop(details.data, '');
            },
            onMove: (_) {
              if (_dropTargetGroup != '') {
                setState(() => _dropTargetGroup = '');
              }
            },
            onLeave: (_) {
              if (_dropTargetGroup == '') {
                setState(() => _dropTargetGroup = null);
              }
            },
            builder: (context, candidateData, rejectedData) {
              return ListView.builder(
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
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildIndentGuides(int depth, ThemeData theme) {
    if (depth == 0) return const SizedBox(width: 8);
    final guideColor = theme.colorScheme.onSurface.withValues(alpha: 0.12);
    return SizedBox(
      width: 8.0 + depth * 16.0,
      child: Row(
        children: [
          const SizedBox(width: 8),
          for (var i = 0; i < depth; i++)
            SizedBox(
              width: 16,
              child: Center(
                child: Container(width: 1, color: guideColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupContent(SessionTreeNode node, int depth, bool isDropTarget) {
    final expanded = _expandedGroups.contains(node.fullPath);
    final theme = Theme.of(context);

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
        child: Container(
          height: 30,
          decoration: isDropTarget
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  border: Border.all(color: theme.colorScheme.primary, width: 1),
                )
              : null,
          child: Row(
            children: [
              _buildIndentGuides(depth, theme),
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.folder_open : Icons.folder,
                size: 16,
                color: AppTheme.folderColor(theme.brightness),
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupTile(SessionTreeNode node, int depth) {
    final theme = Theme.of(context);

    // Wrap as Draggable + DragTarget
    return LongPressDraggable<SessionDragData>(
      data: GroupDrag(node.fullPath),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder, size: 14,
                  color: AppTheme.folderColor(theme.brightness)),
              const SizedBox(width: 4),
              Text(node.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildGroupContent(node, depth, false),
      ),
      child: DragTarget<SessionDragData>(
        onWillAcceptWithDetails: (details) => _canAcceptDrop(details.data, node.fullPath),
        onAcceptWithDetails: (details) {
          setState(() => _dropTargetGroup = null);
          _handleDrop(details.data, node.fullPath);
        },
        onMove: (_) {
          if (_dropTargetGroup != node.fullPath) {
            setState(() => _dropTargetGroup = node.fullPath);
          }
        },
        onLeave: (_) {
          if (_dropTargetGroup == node.fullPath) {
            setState(() => _dropTargetGroup = null);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return _buildGroupContent(node, depth, _dropTargetGroup == node.fullPath);
        },
      ),
    );
  }

  Widget _buildSessionTile(SessionTreeNode node, int depth) {
    final session = node.session!;
    final isSelected = session.id == _selectedSessionId;
    final theme = Theme.of(context);

    final Widget content = GestureDetector(
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
          height: 30,
          padding: const EdgeInsets.only(right: 8),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : null,
          child: Row(
            children: [
              _buildIndentGuides(depth, theme),
              const SizedBox(width: 4),
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

    return LongPressDraggable<SessionDragData>(
      data: SessionDrag(session),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_authIcon(session.authType), size: 14),
              const SizedBox(width: 4),
              Text(node.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: content,
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
