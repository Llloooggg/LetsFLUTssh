import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/connection/connection.dart';
import '../../providers/connection_provider.dart';
import '../tabs/tab_model.dart';
import 'workspace_node.dart';

/// Immutable workspace state.
class WorkspaceState {
  final WorkspaceNode root;
  final String focusedPanelId;

  const WorkspaceState({required this.root, required this.focusedPanelId});

  /// Whether there are any tabs open across all panels.
  bool get hasTabs => collectAllTabs(root).isNotEmpty;

  WorkspaceState copyWith({WorkspaceNode? root, String? focusedPanelId}) {
    return WorkspaceState(
      root: root ?? this.root,
      focusedPanelId: focusedPanelId ?? this.focusedPanelId,
    );
  }
}

/// State notifier for the workspace tiling system.
///
/// Manages a tree of [PanelLeaf] nodes, each holding a stack of tabs.
/// Panels can be split horizontally/vertically and tabs can be moved
/// between panels via drag-and-drop.
class WorkspaceNotifier extends Notifier<WorkspaceState> {
  static const _uuid = Uuid();

  @override
  WorkspaceState build() {
    final initialPanel = PanelLeaf();
    return WorkspaceState(root: initialPanel, focusedPanelId: initialPanel.id);
  }

  // ---------------------------------------------------------------------------
  // Tab operations (scoped to a panel)
  // ---------------------------------------------------------------------------

  /// Add a [TabEntry] to the panel with [panelId].
  /// Returns the tab ID.
  String addTab(String panelId, TabEntry tab) {
    state = state.copyWith(
      root: updatePanel(state.root, panelId, (panel) {
        final newTabs = [...panel.tabs, tab];
        return panel.copyWith(
          tabs: newTabs,
          activeTabIndex: newTabs.length - 1,
        );
      }),
      focusedPanelId: panelId,
    );
    return tab.id;
  }

  /// Close a tab. If the panel becomes empty, collapse it.
  void closeTab(String panelId, String tabId) {
    final panel = findPanel(state.root, panelId);
    if (panel == null) return;

    final idx = panel.tabs.indexWhere((t) => t.id == tabId);
    if (idx < 0) return;

    final closedTab = panel.tabs[idx];
    final newTabs = [...panel.tabs]..removeAt(idx);

    if (newTabs.isEmpty) {
      // Collapse panel — remove from tree and promote sibling.
      final newRoot = removeWorkspaceNode(state.root, panelId);
      if (newRoot == null) {
        // Was the last panel — reset to empty.
        final fresh = PanelLeaf();
        state = WorkspaceState(root: fresh, focusedPanelId: fresh.id);
      } else {
        // Focus moves to the first remaining panel.
        final panels = collectPanelIds(newRoot);
        state = state.copyWith(
          root: newRoot,
          focusedPanelId: panels.contains(state.focusedPanelId)
              ? state.focusedPanelId
              : panels.first,
        );
      }
    } else {
      var newActive = panel.activeTabIndex;
      if (newActive >= newTabs.length) newActive = newTabs.length - 1;
      state = state.copyWith(
        root: updatePanel(state.root, panelId, (_) {
          return panel.copyWith(tabs: newTabs, activeTabIndex: newActive);
        }),
      );
    }

    _disconnectOrphaned([closedTab]);
  }

  /// Select a tab by index within a panel.
  void selectTab(String panelId, int index) {
    state = state.copyWith(
      root: updatePanel(state.root, panelId, (panel) {
        if (index >= 0 && index < panel.tabs.length) {
          return panel.copyWith(activeTabIndex: index);
        }
        return panel;
      }),
      focusedPanelId: panelId,
    );
  }

  /// Reorder tabs within a panel (drag-to-reorder).
  void reorderTabs(String panelId, int oldIndex, int newIndex) {
    state = state.copyWith(
      root: updatePanel(state.root, panelId, (panel) {
        final tabs = [...panel.tabs];
        var adjNew = newIndex;
        if (adjNew > oldIndex) adjNew--;
        final tab = tabs.removeAt(oldIndex);
        tabs.insert(adjNew, tab);

        var activeIdx = panel.activeTabIndex;
        if (activeIdx == oldIndex) {
          activeIdx = adjNew;
        } else if (oldIndex < activeIdx && adjNew >= activeIdx) {
          activeIdx--;
        } else if (oldIndex > activeIdx && adjNew <= activeIdx) {
          activeIdx++;
        }
        return panel.copyWith(tabs: tabs, activeTabIndex: activeIdx);
      }),
    );
  }

  /// Close all tabs except the one with [tabId].
  void closeOthers(String panelId, String tabId) {
    final panel = findPanel(state.root, panelId);
    if (panel == null) return;
    final kept = panel.tabs.firstWhere((t) => t.id == tabId);
    final closed = panel.tabs.where((t) => t.id != tabId).toList();
    state = state.copyWith(
      root: updatePanel(state.root, panelId, (_) {
        return panel.copyWith(tabs: [kept], activeTabIndex: 0);
      }),
    );
    _disconnectOrphaned(closed);
  }

  /// Close all tabs to the right of [index].
  void closeToTheRight(String panelId, int index) {
    final panel = findPanel(state.root, panelId);
    if (panel == null || index >= panel.tabs.length - 1) return;
    final closed = panel.tabs.sublist(index + 1);
    final newTabs = panel.tabs.sublist(0, index + 1);
    var newActive = panel.activeTabIndex;
    if (newActive >= newTabs.length) newActive = newTabs.length - 1;
    state = state.copyWith(
      root: updatePanel(state.root, panelId, (_) {
        return panel.copyWith(tabs: newTabs, activeTabIndex: newActive);
      }),
    );
    _disconnectOrphaned(closed);
  }

  /// Close every tab in [panelId]. The panel collapses afterward.
  void closeAll(String panelId) {
    final panel = findPanel(state.root, panelId);
    if (panel == null || panel.tabs.isEmpty) return;
    final closed = [...panel.tabs];
    // Remove all tabs — panel becomes empty → collapse it.
    final newRoot = removeWorkspaceNode(state.root, panelId);
    if (newRoot == null) {
      final fresh = PanelLeaf();
      state = WorkspaceState(root: fresh, focusedPanelId: fresh.id);
    } else {
      final panels = collectPanelIds(newRoot);
      state = state.copyWith(
        root: newRoot,
        focusedPanelId: panels.contains(state.focusedPanelId)
            ? state.focusedPanelId
            : panels.first,
      );
    }
    _disconnectOrphaned(closed);
  }

  /// Close all tabs to the left of [index].
  void closeToTheLeft(String panelId, int index) {
    final panel = findPanel(state.root, panelId);
    if (panel == null || index <= 0) return;
    final closed = panel.tabs.sublist(0, index);
    final newTabs = panel.tabs.sublist(index);
    var newActive = panel.activeTabIndex - index;
    if (newActive < 0) newActive = 0;
    state = state.copyWith(
      root: updatePanel(state.root, panelId, (_) {
        return panel.copyWith(tabs: newTabs, activeTabIndex: newActive);
      }),
    );
    _disconnectOrphaned(closed);
  }

  // ---------------------------------------------------------------------------
  // Panel operations
  // ---------------------------------------------------------------------------

  /// Set which panel has keyboard focus.
  void setFocusedPanel(String panelId) {
    if (state.focusedPanelId != panelId) {
      state = state.copyWith(focusedPanelId: panelId);
    }
  }

  /// Split [panelId] in [direction], moving [tab] into a new panel.
  ///
  /// If [insertBefore] is true the new panel appears first (left/top),
  /// otherwise second (right/bottom).
  void splitPanel(
    String panelId,
    Axis direction,
    TabEntry tab, {
    bool insertBefore = false,
  }) {
    final sourcePanel = findPanel(state.root, panelId);
    if (sourcePanel == null) return;

    final newPanel = PanelLeaf(tabs: [tab], activeTabIndex: 0);

    // Remove the tab from the source panel if it's there.
    final tabIdx = sourcePanel.tabs.indexWhere((t) => t.id == tab.id);
    PanelLeaf updatedSource = sourcePanel;
    if (tabIdx >= 0) {
      final newTabs = [...sourcePanel.tabs]..removeAt(tabIdx);
      var newActive = sourcePanel.activeTabIndex;
      if (newActive >= newTabs.length) newActive = newTabs.length - 1;
      if (newActive < 0) newActive = -1;
      updatedSource = sourcePanel.copyWith(
        tabs: newTabs,
        activeTabIndex: newActive,
      );
    }

    // If source panel would be empty after removing the tab,
    // just replace it with the new panel (no split needed).
    if (updatedSource.tabs.isEmpty) {
      state = state.copyWith(
        root: replaceWorkspaceNode(state.root, panelId, newPanel),
        focusedPanelId: newPanel.id,
      );
      return;
    }

    final branch = WorkspaceBranch(
      direction: direction,
      first: insertBefore ? newPanel : updatedSource,
      second: insertBefore ? updatedSource : newPanel,
    );

    state = state.copyWith(
      root: replaceWorkspaceNode(state.root, panelId, branch),
      focusedPanelId: newPanel.id,
    );
  }

  /// Split any node (panel or branch) by wrapping it in a new branch.
  ///
  /// Unlike [splitPanel] which replaces a single panel, this wraps the
  /// entire node [nodeId] — useful for splitting an entire branch so the
  /// new panel spans the full height/width of the branch.
  void splitAroundNode(
    String nodeId,
    Axis direction,
    TabEntry tab, {
    bool insertBefore = false,
  }) {
    final target = findNode(state.root, nodeId);
    if (target == null) return;

    // If it's a panel and the tab lives there, use splitPanel instead.
    if (target is PanelLeaf) {
      splitPanel(target.id, direction, tab, insertBefore: insertBefore);
      return;
    }

    final newPanel = PanelLeaf(tabs: [tab], activeTabIndex: 0);

    final branch = WorkspaceBranch(
      direction: direction,
      first: insertBefore ? newPanel : target,
      second: insertBefore ? target : newPanel,
    );

    // If the target IS the root, replace the entire root.
    if (state.root.id == nodeId) {
      state = state.copyWith(root: branch, focusedPanelId: newPanel.id);
    } else {
      state = state.copyWith(
        root: replaceWorkspaceNode(state.root, nodeId, branch),
        focusedPanelId: newPanel.id,
      );
    }
  }

  /// Duplicate the active tab of [panelId] as a new tab next to it.
  ///
  /// The original tab stays in place, and a duplicate (new ID, same
  /// connection) appears immediately after it in the same panel's tab bar.
  void duplicateTab(String panelId) {
    final panel = findPanel(state.root, panelId);
    final tab = panel?.activeTab;
    if (panel == null || tab == null) return;

    final newTab = tab.duplicate();
    final insertIdx = panel.activeTabIndex + 1;
    final newTabs = [...panel.tabs]..insert(insertIdx, newTab);

    state = state.copyWith(
      root: updatePanel(state.root, panelId, (_) {
        return panel.copyWith(tabs: newTabs, activeTabIndex: insertIdx);
      }),
    );
  }

  /// Duplicate the active tab of [panelId] into a new adjacent panel.
  ///
  /// The original tab stays in place, and a duplicate (new ID, same connection)
  /// appears in a new panel split in the given [direction].
  void copyToNewPanel(String panelId, Axis direction) {
    final panel = findPanel(state.root, panelId);
    final tab = panel?.activeTab;
    if (panel == null || tab == null) return;

    final newPanel = PanelLeaf(tabs: [tab.duplicate()], activeTabIndex: 0);

    final branch = WorkspaceBranch(
      direction: direction,
      first: panel,
      second: newPanel,
    );

    state = state.copyWith(
      root: replaceWorkspaceNode(state.root, panelId, branch),
      focusedPanelId: newPanel.id,
    );
  }

  /// Update the divider ratio for a [WorkspaceBranch].
  void updateRatio(String branchId, double ratio) {
    state = state.copyWith(
      root: _updateBranchRatio(state.root, branchId, ratio),
    );
  }

  WorkspaceNode _updateBranchRatio(
    WorkspaceNode node,
    String branchId,
    double ratio,
  ) {
    if (node is WorkspaceBranch) {
      if (node.id == branchId) {
        return WorkspaceBranch(
          id: node.id,
          direction: node.direction,
          ratio: ratio,
          first: node.first,
          second: node.second,
        );
      }
      return WorkspaceBranch(
        id: node.id,
        direction: node.direction,
        ratio: node.ratio,
        first: _updateBranchRatio(node.first, branchId, ratio),
        second: _updateBranchRatio(node.second, branchId, ratio),
      );
    }
    return node;
  }

  /// Move a tab from one panel to another.
  void moveTab(
    String fromPanelId,
    String tabId,
    String toPanelId, {
    int? index,
  }) {
    if (fromPanelId == toPanelId) return;

    final fromPanel = findPanel(state.root, fromPanelId);
    final toPanel = findPanel(state.root, toPanelId);
    if (fromPanel == null || toPanel == null) return;

    final tabIdx = fromPanel.tabs.indexWhere((t) => t.id == tabId);
    if (tabIdx < 0) return;

    final tab = fromPanel.tabs[tabIdx];

    // Remove from source.
    final newFromTabs = [...fromPanel.tabs]..removeAt(tabIdx);
    var newFromActive = fromPanel.activeTabIndex;
    if (newFromActive >= newFromTabs.length) {
      newFromActive = newFromTabs.length - 1;
    }

    // Add to destination.
    final newToTabs = [...toPanel.tabs];
    final insertIdx = index ?? newToTabs.length;
    newToTabs.insert(insertIdx, tab);

    var newRoot = state.root;

    // Update destination panel first.
    newRoot = updatePanel(newRoot, toPanelId, (_) {
      return toPanel.copyWith(tabs: newToTabs, activeTabIndex: insertIdx);
    });

    // If source is now empty, collapse it.
    if (newFromTabs.isEmpty) {
      newRoot = removeWorkspaceNode(newRoot, fromPanelId) ?? newRoot;
    } else {
      newRoot = updatePanel(newRoot, fromPanelId, (_) {
        return fromPanel.copyWith(
          tabs: newFromTabs,
          activeTabIndex: newFromActive,
        );
      });
    }

    final panels = collectPanelIds(newRoot);
    state = state.copyWith(
      root: newRoot,
      focusedPanelId: panels.contains(toPanelId) ? toPanelId : panels.first,
    );
  }

  // ---------------------------------------------------------------------------
  // Convenience methods
  // ---------------------------------------------------------------------------

  /// Add a terminal tab. Defaults to the focused panel.
  String addTerminalTab(
    Connection connection, {
    String? label,
    String? panelId,
  }) {
    final id = _uuid.v4();
    final tab = TabEntry(
      id: id,
      label: label ?? connection.label,
      connection: connection,
      kind: TabKind.terminal,
    );
    return addTab(panelId ?? state.focusedPanelId, tab);
  }

  /// Add an SFTP tab. Defaults to the focused panel.
  String addSftpTab(Connection connection, {String? label, String? panelId}) {
    final id = _uuid.v4();
    final tab = TabEntry(
      id: id,
      label: label ?? connection.label,
      connection: connection,
      kind: TabKind.sftp,
    );
    return addTab(panelId ?? state.focusedPanelId, tab);
  }

  /// The active tab in the focused panel, or `null`.
  TabEntry? get focusedTab {
    final panel = findPanel(state.root, state.focusedPanelId);
    return panel?.activeTab;
  }

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  /// Disconnect connections that are no longer referenced by any open tab
  /// across **all** panels.
  void _disconnectOrphaned(List<TabEntry> closedTabs) {
    final remainingConnIds = collectAllTabs(
      state.root,
    ).map((t) => t.connection.id).toSet();
    final manager = ref.read(connectionManagerProvider);
    for (final tab in closedTabs) {
      if (!remainingConnIds.contains(tab.connection.id)) {
        manager.disconnect(tab.connection.id);
      }
    }
  }
}

/// Riverpod provider for workspace state.
final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(
  WorkspaceNotifier.new,
);
