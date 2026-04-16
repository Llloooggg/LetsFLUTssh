import 'package:flutter/widgets.dart' show Axis;
import 'package:uuid/uuid.dart';

import '../tabs/tab_model.dart';

const _uuid = Uuid();

/// A node in the workspace split tree.
///
/// Either a [PanelLeaf] (tab stack with its own tab bar) or a
/// [WorkspaceBranch] (two children split in a direction with a ratio).
sealed class WorkspaceNode {
  final String id;
  WorkspaceNode({String? id}) : id = id ?? _uuid.v4();
}

/// A leaf node — holds a stack of tabs with an active index.
class PanelLeaf extends WorkspaceNode {
  final List<TabEntry> tabs;
  final int activeTabIndex;

  PanelLeaf({super.id, this.tabs = const [], this.activeTabIndex = -1});

  /// The currently active tab, or `null` if none.
  TabEntry? get activeTab => activeTabIndex >= 0 && activeTabIndex < tabs.length
      ? tabs[activeTabIndex]
      : null;

  /// Returns a copy with updated fields.
  PanelLeaf copyWith({List<TabEntry>? tabs, int? activeTabIndex}) {
    return PanelLeaf(
      id: id,
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }
}

/// A branch node — two children split in a direction with a ratio.
class WorkspaceBranch extends WorkspaceNode {
  final Axis direction;
  final double ratio;
  final WorkspaceNode first;
  final WorkspaceNode second;

  WorkspaceBranch({
    super.id,
    required this.direction,
    this.ratio = 0.5,
    required this.first,
    required this.second,
  });
}

// ---------------------------------------------------------------------------
// Tree helpers
// ---------------------------------------------------------------------------

/// Finds and replaces a node in the tree by [targetId]. Returns new root.
WorkspaceNode replaceWorkspaceNode(
  WorkspaceNode root,
  String targetId,
  WorkspaceNode replacement,
) {
  if (root.id == targetId) return replacement;
  if (root is WorkspaceBranch) {
    return WorkspaceBranch(
      id: root.id,
      direction: root.direction,
      ratio: root.ratio,
      first: replaceWorkspaceNode(root.first, targetId, replacement),
      second: replaceWorkspaceNode(root.second, targetId, replacement),
    );
  }
  return root;
}

/// Removes a leaf from the tree. Returns the sibling (promoted up).
/// If root is the target, returns `null`.
WorkspaceNode? removeWorkspaceNode(WorkspaceNode root, String targetId) {
  if (root.id == targetId) return null;
  if (root is WorkspaceBranch) {
    if (root.first.id == targetId) return root.second;
    if (root.second.id == targetId) return root.first;
    final newFirst = removeWorkspaceNode(root.first, targetId);
    if (newFirst != null && !identical(newFirst, root.first)) {
      return WorkspaceBranch(
        id: root.id,
        direction: root.direction,
        ratio: root.ratio,
        first: newFirst,
        second: root.second,
      );
    }
    final newSecond = removeWorkspaceNode(root.second, targetId);
    if (newSecond != null && !identical(newSecond, root.second)) {
      return WorkspaceBranch(
        id: root.id,
        direction: root.direction,
        ratio: root.ratio,
        first: root.first,
        second: newSecond,
      );
    }
  }
  return root;
}

/// Collects all [PanelLeaf] IDs in tree order.
List<String> collectPanelIds(WorkspaceNode node) {
  return switch (node) {
    PanelLeaf() => [node.id],
    WorkspaceBranch() => [
      ...collectPanelIds(node.first),
      ...collectPanelIds(node.second),
    ],
  };
}

/// Finds any [WorkspaceNode] by [nodeId], or `null` if not found.
WorkspaceNode? findNode(WorkspaceNode root, String nodeId) {
  if (root.id == nodeId) return root;
  if (root is WorkspaceBranch) {
    return findNode(root.first, nodeId) ?? findNode(root.second, nodeId);
  }
  return null;
}

/// Finds a [PanelLeaf] by [panelId], or `null` if not found.
PanelLeaf? findPanel(WorkspaceNode root, String panelId) {
  return switch (root) {
    PanelLeaf() => root.id == panelId ? root : null,
    WorkspaceBranch() =>
      findPanel(root.first, panelId) ?? findPanel(root.second, panelId),
  };
}

/// Applies [updater] to the [PanelLeaf] with [panelId] and returns a new tree.
/// If the panel is not found the tree is returned unchanged.
WorkspaceNode updatePanel(
  WorkspaceNode root,
  String panelId,
  PanelLeaf Function(PanelLeaf panel) updater,
) {
  return switch (root) {
    PanelLeaf() when root.id == panelId => updater(root),
    PanelLeaf() => root,
    WorkspaceBranch() => WorkspaceBranch(
      id: root.id,
      direction: root.direction,
      ratio: root.ratio,
      first: updatePanel(root.first, panelId, updater),
      second: updatePanel(root.second, panelId, updater),
    ),
  };
}

/// Collects all [TabEntry] objects across every panel in the tree.
List<TabEntry> collectAllTabs(WorkspaceNode root) {
  return switch (root) {
    PanelLeaf() => [...root.tabs],
    WorkspaceBranch() => [
      ...collectAllTabs(root.first),
      ...collectAllTabs(root.second),
    ],
  };
}

/// Returns `true` when the subtree rooted at [node] contains a panel
/// whose id is [panelId]. Used by the workspace view to decide which
/// split branches should give all their space to the maximized panel
/// while still keeping every widget mounted (and every terminal shell
/// alive) via a zero-size sibling.
bool subtreeContainsPanel(WorkspaceNode node, String panelId) {
  return switch (node) {
    PanelLeaf() => node.id == panelId,
    WorkspaceBranch() =>
      subtreeContainsPanel(node.first, panelId) ||
          subtreeContainsPanel(node.second, panelId),
  };
}
