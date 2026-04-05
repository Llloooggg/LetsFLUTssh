import 'session.dart';

/// A node in the session tree — either a folder or a session leaf.
class SessionTreeNode {
  final String name;
  final String fullPath;
  final Session? session; // null for folder nodes
  final List<SessionTreeNode> children;
  bool expanded;

  /// Cached recursive session count (computed during tree build).
  int sessionCount;

  SessionTreeNode({
    required this.name,
    required this.fullPath,
    this.session,
    List<SessionTreeNode>? children,
    this.expanded = true,
    this.sessionCount = 0,
  }) : children = children ?? [];

  bool get isGroup => session == null;
  bool get isSession => session != null;
}

/// Builds a tree structure from a flat list of sessions using folder paths.
///
/// Example: session with folder "Production/Web" and label "nginx1"
/// → Production → Web → nginx1 (leaf)
class SessionTree {
  /// Build tree from flat session list.
  ///
  /// [emptyFolders] — folder paths that should appear even without sessions.
  static List<SessionTreeNode> build(
    List<Session> sessions, {
    Set<String> emptyFolders = const {},
  }) {
    final root = <SessionTreeNode>[];

    // Create nodes for empty folders first.
    for (final folderPath in emptyFolders) {
      _ensureFolderPath(root, folderPath);
    }

    for (final session in sessions) {
      _insertSession(root, session);
    }

    _sortTree(root);
    return root;
  }

  /// Navigate/create all intermediate folder nodes for [folderPath]
  /// and return the children list of the deepest folder.
  static List<SessionTreeNode> _ensureFolderPath(
    List<SessionTreeNode> root,
    String folderPath,
  ) {
    final parts = folderPath.split('/');
    var currentChildren = root;
    var currentPath = '';
    for (final part in parts) {
      currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
      var groupNode = _findGroup(currentChildren, part);
      if (groupNode == null) {
        groupNode = SessionTreeNode(name: part, fullPath: currentPath);
        currentChildren.add(groupNode);
      }
      currentChildren = groupNode.children;
    }
    return currentChildren;
  }

  /// Create a leaf node for [session] and insert it into the tree.
  static void _insertSession(List<SessionTreeNode> root, Session session) {
    final name = session.label.isNotEmpty ? session.label : session.displayName;

    if (session.folder.isEmpty) {
      // Top-level session (no folder)
      root.add(
        SessionTreeNode(name: name, fullPath: session.label, session: session),
      );
    } else {
      // Add session as leaf under the deepest folder
      final parent = _ensureFolderPath(root, session.folder);
      parent.add(
        SessionTreeNode(
          name: name,
          fullPath: session.fullPath,
          session: session,
        ),
      );
    }
  }

  static SessionTreeNode? _findGroup(List<SessionTreeNode> nodes, String name) {
    for (final node in nodes) {
      if (node.isGroup && node.name == name) return node;
    }
    return null;
  }

  /// Sort: folders first (alphabetical), then sessions (alphabetical).
  /// Also computes sessionCount for each folder node.
  static void _sortTree(List<SessionTreeNode> nodes) {
    nodes.sort((a, b) {
      if (a.isGroup && b.isSession) return -1;
      if (a.isSession && b.isGroup) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final node in nodes) {
      if (node.isGroup) {
        _sortTree(node.children);
        node.sessionCount = _countSessions(node);
      }
    }
  }

  static int _countSessions(SessionTreeNode node) {
    if (node.isSession) return 1;
    var count = 0;
    for (final child in node.children) {
      count += _countSessions(child);
    }
    return count;
  }
}
