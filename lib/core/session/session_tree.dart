import 'session.dart';

/// A node in the session tree — either a group folder or a session leaf.
class SessionTreeNode {
  final String name;
  final String fullPath;
  final Session? session; // null for group nodes
  final List<SessionTreeNode> children;
  bool expanded;

  SessionTreeNode({
    required this.name,
    required this.fullPath,
    this.session,
    List<SessionTreeNode>? children,
    this.expanded = true,
  }) : children = children ?? [];

  bool get isGroup => session == null;
  bool get isSession => session != null;
}

/// Builds a tree structure from a flat list of sessions using group paths.
///
/// Example: session with group "Production/Web" and label "nginx1"
/// → Production → Web → nginx1 (leaf)
class SessionTree {
  /// Build tree from flat session list.
  ///
  /// [emptyGroups] — group paths that should appear even without sessions.
  static List<SessionTreeNode> build(
    List<Session> sessions, {
    Set<String> emptyGroups = const {},
  }) {
    final root = <SessionTreeNode>[];

    // Create nodes for empty groups first.
    for (final groupPath in emptyGroups) {
      final parts = groupPath.split('/');
      var currentChildren = root;
      var currentPath = '';
      for (final part in parts) {
        currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
        var groupNode = _findGroup(currentChildren, part);
        if (groupNode == null) {
          groupNode = SessionTreeNode(
            name: part,
            fullPath: currentPath,
          );
          currentChildren.add(groupNode);
        }
        currentChildren = groupNode.children;
      }
    }

    for (final session in sessions) {
      if (session.group.isEmpty) {
        // Top-level session (no group)
        root.add(SessionTreeNode(
          name: session.label.isNotEmpty ? session.label : session.displayName,
          fullPath: session.label,
          session: session,
        ));
      } else {
        // Navigate/create group path
        final parts = session.group.split('/');
        var currentChildren = root;
        var currentPath = '';

        for (final part in parts) {
          currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
          var groupNode = _findGroup(currentChildren, part);
          if (groupNode == null) {
            groupNode = SessionTreeNode(
              name: part,
              fullPath: currentPath,
            );
            currentChildren.add(groupNode);
          }
          currentChildren = groupNode.children;
        }

        // Add session as leaf under the deepest group
        currentChildren.add(SessionTreeNode(
          name: session.label.isNotEmpty ? session.label : session.displayName,
          fullPath: session.fullPath,
          session: session,
        ));
      }
    }

    _sortTree(root);
    return root;
  }

  static SessionTreeNode? _findGroup(List<SessionTreeNode> nodes, String name) {
    for (final node in nodes) {
      if (node.isGroup && node.name == name) return node;
    }
    return null;
  }

  /// Sort: groups first (alphabetical), then sessions (alphabetical).
  static void _sortTree(List<SessionTreeNode> nodes) {
    nodes.sort((a, b) {
      if (a.isGroup && b.isSession) return -1;
      if (a.isSession && b.isGroup) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final node in nodes) {
      if (node.isGroup) _sortTree(node.children);
    }
  }
}
