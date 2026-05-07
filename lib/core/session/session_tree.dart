import '../../src/rust/api/session_tree.dart' as rust_tree;
import 'session.dart';

/// A node in the session tree — either a folder or a session leaf.
///
/// The tree itself is built by `lfs_core::session_tree`; this class
/// is the Dart wrapper that re-attaches the live [Session] handle
/// to leaf nodes (Rust only knows the session id) and carries the
/// UI-only [expanded] flag the sidebar mutates as the user clicks
/// folder chevrons.
class SessionTreeNode {
  final String name;
  final String fullPath;
  final Session? session; // null for folder nodes
  final List<SessionTreeNode> children;
  bool expanded;

  /// Cached recursive session count (computed Rust-side during
  /// tree build).
  final int sessionCount;

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
///
/// The structural logic (folder collapsing, sort order, recursive
/// session counting) lives in `lfs_core::session_tree`; this Dart
/// surface marshals the input/output and re-binds the live
/// [Session] objects to leaves by id.
class SessionTree {
  /// Build tree from flat session list.
  ///
  /// [emptyFolders] — folder paths that should appear even without sessions.
  ///
  /// Pre-FRB-init callers (Riverpod providers that build during the
  /// first runApp pass — e.g. `filteredSessionTreeProvider` watched
  /// by SessionPanel under the splash) get an empty list back.
  /// `sessions` is empty in that window anyway because the data
  /// providers also gate on FRB, so the empty tree matches the empty
  /// session list. Once `_initRustCoreOrFatal` resolves and
  /// `sessionProvider` reloads, Riverpod re-runs the dependent
  /// providers and the real tree lands.
  static List<SessionTreeNode> build(
    List<Session> sessions, {
    Set<String> emptyFolders = const {},
  }) {
    if (sessions.isEmpty && emptyFolders.isEmpty) return const [];
    final byId = {for (final s in sessions) s.id: s};
    final inputs = sessions
        .map(
          (s) => rust_tree.DbSessionTreeInput(
            id: s.id,
            label: s.label,
            folder: s.folder,
            displayName: s.displayName,
          ),
        )
        .toList();
    try {
      final raw = rust_tree.sessionTreeBuild(
        sessions: inputs,
        emptyFolders: emptyFolders.toList(),
      );
      return raw.map((n) => _wrap(n, byId)).toList();
    } on StateError catch (e) {
      if (e.message.contains('flutter_rust_bridge has not been initialized')) {
        return const [];
      }
      rethrow;
    }
  }

  static SessionTreeNode _wrap(
    rust_tree.DbSessionTreeNode node,
    Map<String, Session> byId,
  ) {
    final id = node.sessionId;
    return SessionTreeNode(
      name: node.name,
      fullPath: node.fullPath,
      session: id == null ? null : byId[id],
      children: node.children.map((c) => _wrap(c, byId)).toList(),
      sessionCount: node.sessionCount,
    );
  }
}
