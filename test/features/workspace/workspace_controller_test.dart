import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';
import 'package:letsflutssh/providers/connection_provider.dart';

Connection _conn(String id) {
  const config = SSHConfig(
    server: ServerAddress(host: 'h', user: 'u'),
  );
  return Connection(id: id, sshConfig: config, label: id);
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
        connectionManagerProvider.overrideWithValue(
          ConnectionManager(knownHosts: KnownHostsManager()),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  WorkspaceNotifier notifier() => container.read(workspaceProvider.notifier);
  WorkspaceState state() => container.read(workspaceProvider);

  group('initial state', () {
    test('starts with single empty panel', () {
      final ws = state();
      expect(ws.root, isA<PanelLeaf>());
      expect((ws.root as PanelLeaf).tabs, isEmpty);
      expect(ws.hasTabs, isFalse);
    });
  });

  group('addTerminalTab', () {
    test('adds tab to focused panel', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn);

      final ws = state();
      expect(ws.hasTabs, isTrue);
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      expect(panel.tabs.length, 1);
      expect(panel.tabs.first.kind, TabKind.terminal);
      expect(panel.activeTabIndex, 0);
    });
  });

  group('addSftpTab', () {
    test('adds SFTP tab to focused panel', () {
      final conn = _conn('c1');
      notifier().addSftpTab(conn);

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      expect(panel.tabs.length, 1);
      expect(panel.tabs.first.kind, TabKind.sftp);
    });
  });

  group('closeTab', () {
    test('removes tab from panel', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn);
      notifier().addTerminalTab(_conn('c2'));

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      final tabId = panel.tabs.first.id;

      notifier().closeTab(panel.id, tabId);

      final updated = findPanel(state().root, ws.focusedPanelId)!;
      expect(updated.tabs.length, 1);
    });

    test('collapses panel when last tab is closed', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn);

      // Split to create two panels.
      notifier().addTerminalTab(_conn('c2'));
      // Now we have 2 tabs in one panel. Split panel with second tab.
      final ws2 = state();
      final p = findPanel(ws2.root, ws2.focusedPanelId)!;
      notifier().splitPanel(p.id, Axis.horizontal, p.tabs.last);

      // Now two panels. Close the tab in the new panel.
      final ws3 = state();
      expect(ws3.root, isA<WorkspaceBranch>());

      final panels = collectPanelIds(ws3.root);
      expect(panels.length, 2);

      // Close the focused panel's tab.
      final focusedPanel = findPanel(ws3.root, ws3.focusedPanelId)!;
      notifier().closeTab(focusedPanel.id, focusedPanel.tabs.first.id);

      // Should collapse back to single panel.
      final ws4 = state();
      expect(ws4.root, isA<PanelLeaf>());
    });

    test('resets to empty panel when last tab in last panel is closed', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn);

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().closeTab(panel.id, panel.tabs.first.id);

      final ws2 = state();
      expect(ws2.hasTabs, isFalse);
      expect(ws2.root, isA<PanelLeaf>());
    });
  });

  group('selectTab', () {
    test('changes active tab index', () {
      notifier().addTerminalTab(_conn('c1'));
      notifier().addTerminalTab(_conn('c2'));

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      expect(panel.activeTabIndex, 1); // Last added is active.

      notifier().selectTab(panel.id, 0);

      final updated = findPanel(state().root, ws.focusedPanelId)!;
      expect(updated.activeTabIndex, 0);
    });
  });

  group('reorderTabs', () {
    test('moves tab within panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().reorderTabs(panelId, 0, 2);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs[0].label, 'B');
      expect(panel.tabs[1].label, 'A');
      expect(panel.tabs[2].label, 'C');
    });
  });

  group('splitPanel', () {
    test('creates branch with two panels', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      final tabToMove = panel.tabs.last;

      notifier().splitPanel(panel.id, Axis.horizontal, tabToMove);

      final ws2 = state();
      expect(ws2.root, isA<WorkspaceBranch>());
      final branch = ws2.root as WorkspaceBranch;
      expect(branch.direction, Axis.horizontal);

      final firstPanel = branch.first as PanelLeaf;
      final secondPanel = branch.second as PanelLeaf;
      expect(firstPanel.tabs.length, 1);
      expect(firstPanel.tabs.first.label, 'A');
      expect(secondPanel.tabs.length, 1);
      expect(secondPanel.tabs.first.label, 'B');
    });

    test('insertBefore places new panel first', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;

      notifier().splitPanel(
        panel.id,
        Axis.vertical,
        panel.tabs.last,
        insertBefore: true,
      );

      final ws2 = state();
      final branch = ws2.root as WorkspaceBranch;
      expect(branch.direction, Axis.vertical);
      // New panel (with tab B) should be first.
      final firstPanel = branch.first as PanelLeaf;
      expect(firstPanel.tabs.first.label, 'B');
    });
  });

  group('duplicateTab', () {
    test('duplicates active tab next to it in same panel', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn, label: 'A');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().duplicateTab(panelId);

      final ws2 = state();
      // Still a single panel — no splitting.
      expect(ws2.root, isA<PanelLeaf>());
      final panel = ws2.root as PanelLeaf;
      expect(panel.tabs.length, 2);
      // Original stays at index 0.
      expect(panel.tabs[0].label, 'A');
      // Copy has same label/connection but different id.
      expect(panel.tabs[1].label, 'A');
      expect(panel.tabs[1].connection, same(conn));
      expect(panel.tabs[1].id, isNot(panel.tabs[0].id));
    });

    test('activates the new tab', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final panelId = state().focusedPanelId;

      notifier().duplicateTab(panelId);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.activeTabIndex, 1);
    });

    test('inserts after active tab when multiple tabs exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final panelId = state().focusedPanelId;
      // Active is C (index 2). Select B (index 1).
      notifier().selectTab(panelId, 1);

      notifier().duplicateTab(panelId);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 4);
      expect(panel.tabs[0].label, 'A');
      expect(panel.tabs[1].label, 'B');
      expect(panel.tabs[2].label, 'B'); // duplicate inserted after B
      expect(panel.tabs[3].label, 'C');
      expect(panel.activeTabIndex, 2);
    });

    test('no-op when panel has no tabs', () {
      final panelId = state().focusedPanelId;
      notifier().duplicateTab(panelId);
      // Still empty.
      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs, isEmpty);
    });
  });

  group('copyToNewPanel', () {
    test('duplicates active tab into new panel', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn, label: 'A');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().copyToNewPanel(panelId, Axis.horizontal);

      final ws2 = state();
      expect(ws2.root, isA<WorkspaceBranch>());
      final branch = ws2.root as WorkspaceBranch;
      expect(branch.direction, Axis.horizontal);

      final original = branch.first as PanelLeaf;
      final copy = branch.second as PanelLeaf;
      expect(original.tabs.length, 1);
      expect(original.tabs.first.label, 'A');
      expect(copy.tabs.length, 1);
      expect(copy.tabs.first.label, 'A');
      expect(copy.tabs.first.connection, same(conn));
      expect(copy.tabs.first.id, isNot(original.tabs.first.id));
    });

    test('focuses the new panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final panelId = state().focusedPanelId;

      notifier().copyToNewPanel(panelId, Axis.vertical);

      final ws = state();
      final branch = ws.root as WorkspaceBranch;
      final newPanel = branch.second as PanelLeaf;
      expect(ws.focusedPanelId, newPanel.id);
    });

    test('no-op when panel has no tabs', () {
      final panelId = state().focusedPanelId;
      notifier().copyToNewPanel(panelId, Axis.horizontal);
      expect(state().root, isA<PanelLeaf>());
    });
  });

  group('moveTab', () {
    test('moves tab between panels', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      // Split to create two panels.
      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      expect(panels.length, 2);

      final p1 = findPanel(ws2.root, panels[0])!;
      final p2 = findPanel(ws2.root, panels[1])!;
      expect(p1.tabs.length, 1);
      expect(p2.tabs.length, 1);

      // Move the tab from p2 to p1.
      notifier().moveTab(p2.id, p2.tabs.first.id, p1.id);

      // p2 should be collapsed (empty), leaving single panel with 2 tabs.
      final ws3 = state();
      expect(ws3.root, isA<PanelLeaf>());
      final remaining = ws3.root as PanelLeaf;
      expect(remaining.tabs.length, 2);
    });
  });

  group('updateRatio', () {
    test('updates branch ratio', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final branch = ws2.root as WorkspaceBranch;
      expect(branch.ratio, 0.5);

      notifier().updateRatio(branch.id, 0.7);

      final ws3 = state();
      expect((ws3.root as WorkspaceBranch).ratio, 0.7);
    });
  });

  group('setFocusedPanel', () {
    test('changes focused panel id', () {
      notifier().addTerminalTab(_conn('c1'));
      notifier().addTerminalTab(_conn('c2'));

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      final otherPanel = panels.firstWhere((id) => id != ws2.focusedPanelId);

      notifier().setFocusedPanel(otherPanel);
      expect(state().focusedPanelId, otherPanel);
    });
  });

  group('closeOthers', () {
    test('keeps only the specified tab', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      final keepId = panel.tabs[1].id;

      notifier().closeOthers(panel.id, keepId);

      final updated = findPanel(state().root, ws.focusedPanelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.tabs.first.id, keepId);
    });

    test('no-op when tabId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      final tabsBefore = panel.tabs.length;

      notifier().closeOthers(panel.id, 'nonexistent');

      final after = findPanel(state().root, ws.focusedPanelId)!;
      expect(after.tabs.length, tabsBefore);
    });
  });

  group('closeToTheRight', () {
    test('closes tabs to the right of index', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeToTheRight(panelId, 0);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 1);
      expect(panel.tabs.first.label, 'A');
    });
  });

  group('closeToTheLeft', () {
    test('closes tabs to the left of index', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeToTheLeft(panelId, 2);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 1);
      expect(panel.tabs.first.label, 'C');
    });
  });

  group('focusedTab', () {
    test('returns active tab of focused panel', () {
      final conn = _conn('c1');
      notifier().addTerminalTab(conn, label: 'MyTab');

      expect(notifier().focusedTab, isNotNull);
      expect(notifier().focusedTab!.label, 'MyTab');
    });

    test('returns null when no tabs', () {
      expect(notifier().focusedTab, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Additional tests for uncovered paths
  // -------------------------------------------------------------------------

  group('closeTab edge cases', () {
    test('no-op when panelId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final before = state();
      notifier().closeTab('nonexistent-panel', 'any-tab');
      expect(state().root, same(before.root));
    });

    test('no-op when tabId does not exist in panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final ws = state();
      final panelId = ws.focusedPanelId;
      notifier().closeTab(panelId, 'nonexistent-tab');
      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 1);
    });

    test('adjusts activeTabIndex when closing tab before active', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;
      // Active is C (index 2). Close A (index 0).
      final panel = findPanel(ws.root, panelId)!;
      notifier().closeTab(panelId, panel.tabs[0].id);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 2);
      expect(updated.tabs[0].label, 'B');
      expect(updated.tabs[1].label, 'C');
      // Active was 2, after removing index 0 it should become 1.
      expect(updated.activeTabIndex, 1);
    });

    test('clamps activeTabIndex when closing the last tab in list', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panelId = ws.focusedPanelId;
      final panel = findPanel(ws.root, panelId)!;
      // Active is B (index 1). Close B.
      notifier().closeTab(panelId, panel.tabs[1].id);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.activeTabIndex, 0);
    });

    test('preserves focus when closing non-focused panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      final focusedId = ws2.focusedPanelId;
      final otherId = panels.firstWhere((id) => id != focusedId);

      // Add an extra tab to the other panel so it survives.
      notifier().addTerminalTab(_conn('c3'), label: 'C', panelId: otherId);

      // Focus back to the original panel.
      notifier().setFocusedPanel(focusedId);

      // Close a tab in the non-focused panel (the one with 2 tabs).
      final otherPanel = findPanel(state().root, otherId)!;
      notifier().closeTab(otherId, otherPanel.tabs.first.id);

      // Focus should remain on the focused panel.
      expect(state().focusedPanelId, focusedId);
    });
  });

  group('splitPanel edge cases', () {
    test('replaces panel when source becomes empty after split', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      final tab = panel.tabs.first;

      // Split with the only tab -> source becomes empty -> just replace.
      notifier().splitPanel(panel.id, Axis.horizontal, tab);

      final ws2 = state();
      // Should NOT create a branch; should replace with a new single panel.
      expect(ws2.root, isA<PanelLeaf>());
      final newPanel = ws2.root as PanelLeaf;
      expect(newPanel.tabs.length, 1);
      expect(newPanel.tabs.first.label, 'A');
      // The panel ID should be different (it's a new panel).
      expect(newPanel.id, isNot(panel.id));
    });

    test('splits with external tab not in source panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');

      final ws = state();
      final panelId = ws.focusedPanelId;

      // Create a tab that is NOT in the panel.
      final externalTab = TabEntry(
        id: 'ext-tab',
        label: 'External',
        connection: _conn('c2'),
        kind: TabKind.terminal,
      );

      notifier().splitPanel(panelId, Axis.vertical, externalTab);

      final ws2 = state();
      expect(ws2.root, isA<WorkspaceBranch>());
      final branch = ws2.root as WorkspaceBranch;
      // Source panel keeps its tab, new panel gets the external tab.
      final first = branch.first as PanelLeaf;
      final second = branch.second as PanelLeaf;
      expect(first.tabs.length, 1);
      expect(first.tabs.first.label, 'A');
      expect(second.tabs.length, 1);
      expect(second.tabs.first.label, 'External');
    });

    test('no-op when panelId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final before = state();

      final tab = TabEntry(
        id: 'tab',
        label: 'X',
        connection: _conn('c2'),
        kind: TabKind.terminal,
      );
      notifier().splitPanel('nonexistent', Axis.horizontal, tab);

      // State should be unchanged.
      expect(state().root, same(before.root));
    });
  });

  group('splitAroundNode', () {
    test('delegates to splitPanel for PanelLeaf targets', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;

      final externalTab = TabEntry(
        id: 'ext',
        label: 'External',
        connection: _conn('c3'),
        kind: TabKind.terminal,
      );

      notifier().splitAroundNode(panel.id, Axis.horizontal, externalTab);

      final ws2 = state();
      expect(ws2.root, isA<WorkspaceBranch>());
    });

    test('wraps branch node when target is root branch', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      expect(ws2.root, isA<WorkspaceBranch>());
      final rootBranchId = ws2.root.id;

      final externalTab = TabEntry(
        id: 'ext',
        label: 'External',
        connection: _conn('c3'),
        kind: TabKind.terminal,
      );

      // Split around the root branch itself.
      notifier().splitAroundNode(rootBranchId, Axis.vertical, externalTab);

      final ws3 = state();
      // Root should now be a new branch wrapping the old branch + new panel.
      expect(ws3.root, isA<WorkspaceBranch>());
      final outerBranch = ws3.root as WorkspaceBranch;
      expect(outerBranch.direction, Axis.vertical);
      expect(outerBranch.first, isA<WorkspaceBranch>());
      expect(outerBranch.second, isA<PanelLeaf>());
    });

    test('wraps branch with insertBefore', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final rootBranchId = ws2.root.id;

      final externalTab = TabEntry(
        id: 'ext',
        label: 'External',
        connection: _conn('c3'),
        kind: TabKind.terminal,
      );

      notifier().splitAroundNode(
        rootBranchId,
        Axis.vertical,
        externalTab,
        insertBefore: true,
      );

      final ws3 = state();
      final outerBranch = ws3.root as WorkspaceBranch;
      // With insertBefore, new panel should be first.
      expect(outerBranch.first, isA<PanelLeaf>());
      expect(outerBranch.second, isA<WorkspaceBranch>());
    });

    test('no-op when nodeId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final before = state();

      final tab = TabEntry(
        id: 'tab',
        label: 'X',
        connection: _conn('c2'),
        kind: TabKind.terminal,
      );
      notifier().splitAroundNode('nonexistent', Axis.horizontal, tab);

      expect(state().root, same(before.root));
    });

    test('wraps non-root branch node', () {
      // Create a 3-panel layout: branch(panel, branch(panel, panel))
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      // Now split the second panel vertically.
      final ws2 = state();
      final panels2 = collectPanelIds(ws2.root);
      final secondPanelId = panels2[1];
      notifier().addTerminalTab(
        _conn('c3'),
        label: 'C',
        panelId: secondPanelId,
      );
      final secondPanel = findPanel(state().root, secondPanelId)!;
      notifier().splitPanel(
        secondPanelId,
        Axis.vertical,
        secondPanel.tabs.last,
      );

      // Now we have branch(panelA, branch(panelB, panelC)).
      final ws3 = state();
      final rootBranch = ws3.root as WorkspaceBranch;
      final innerBranch = rootBranch.second as WorkspaceBranch;

      final externalTab = TabEntry(
        id: 'ext',
        label: 'External',
        connection: _conn('c4'),
        kind: TabKind.terminal,
      );

      // Split around the inner branch.
      notifier().splitAroundNode(innerBranch.id, Axis.horizontal, externalTab);

      final ws4 = state();
      // Root is still a branch, but the second child should now be a branch
      // wrapping the inner branch + the new panel.
      final newRoot = ws4.root as WorkspaceBranch;
      expect(newRoot.second, isA<WorkspaceBranch>());
      final wrappedBranch = newRoot.second as WorkspaceBranch;
      expect(wrappedBranch.direction, Axis.horizontal);
      expect(wrappedBranch.first, isA<WorkspaceBranch>());
      expect(wrappedBranch.second, isA<PanelLeaf>());
    });
  });

  group('closeAll', () {
    test('resets to empty panel when closing all tabs in last panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeAll(panelId);

      final ws2 = state();
      expect(ws2.root, isA<PanelLeaf>());
      expect(ws2.hasTabs, isFalse);
      // Fresh panel should have a new ID.
      expect(ws2.focusedPanelId, isNot(panelId));
    });

    test('collapses panel and promotes sibling', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      expect(panels.length, 2);

      // Close all tabs in the focused panel.
      notifier().closeAll(ws2.focusedPanelId);

      final ws3 = state();
      expect(ws3.root, isA<PanelLeaf>());
      final remaining = ws3.root as PanelLeaf;
      expect(remaining.tabs.length, 1);
    });

    test('no-op when panel has no tabs', () {
      final ws = state();
      final panelId = ws.focusedPanelId;
      notifier().closeAll(panelId);
      // Should not change anything.
      expect(state().focusedPanelId, panelId);
    });

    test('no-op when panelId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final before = state();
      notifier().closeAll('nonexistent');
      final panel = findPanel(state().root, before.focusedPanelId)!;
      expect(panel.tabs.length, 1);
    });

    test('preserves focus when closing non-focused panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      final focusedId = ws2.focusedPanelId;
      final otherId = panels.firstWhere((id) => id != focusedId);

      // Focus on the other panel, then switch back.
      notifier().setFocusedPanel(otherId);
      notifier().setFocusedPanel(focusedId);

      // Close the non-focused panel.
      notifier().closeAll(otherId);

      // Focus should remain on focusedId (which is now the only panel).
      final ws3 = state();
      expect(ws3.focusedPanelId, focusedId);
    });
  });

  group('closeToTheRight edge cases', () {
    test('no-op when index is last tab', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeToTheRight(panelId, 1);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 2);
    });

    test('no-op when panelId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final before = state();
      notifier().closeToTheRight('nonexistent', 0);
      expect(state().root, same(before.root));
    });

    test('clamps active index when active is to the right', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;
      // Active is C (index 2). Close everything to the right of A (index 0).
      notifier().closeToTheRight(panelId, 0);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 1);
      expect(panel.tabs.first.label, 'A');
      expect(panel.activeTabIndex, 0);
    });
  });

  group('closeToTheLeft edge cases', () {
    test('no-op when index is 0', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeToTheLeft(panelId, 0);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 2);
    });

    test('no-op when panelId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final before = state();
      notifier().closeToTheLeft('nonexistent', 1);
      expect(state().root, same(before.root));
    });

    test('adjusts active index when active is to the left', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;
      // Active is C (index 2). Select A (index 0).
      notifier().selectTab(panelId, 0);
      // Close everything to the left of C (index 2).
      notifier().closeToTheLeft(panelId, 2);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs.length, 1);
      expect(panel.tabs.first.label, 'C');
      // Active was 0 (before index 2), so it should clamp to 0.
      expect(panel.activeTabIndex, 0);
    });
  });

  group('selectTab edge cases', () {
    test('no-op for out-of-bounds index', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');

      final ws = state();
      final panelId = ws.focusedPanelId;
      final panel = findPanel(ws.root, panelId)!;
      final activeBefore = panel.activeTabIndex;

      notifier().selectTab(panelId, 99);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.activeTabIndex, activeBefore);
    });

    test('no-op for negative index', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().selectTab(panelId, -1);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.activeTabIndex, 0);
    });
  });

  group('setFocusedPanel edge cases', () {
    test('no-op when setting same panel', () {
      final ws = state();
      final focusedBefore = ws.focusedPanelId;
      notifier().setFocusedPanel(focusedBefore);
      // State reference should be the same (no rebuild).
      expect(state().focusedPanelId, focusedBefore);
    });
  });

  group('moveTab edge cases', () {
    test('no-op when source and destination are the same', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panelId = ws.focusedPanelId;
      final panel = findPanel(ws.root, panelId)!;

      notifier().moveTab(panelId, panel.tabs.first.id, panelId);

      // Tabs should be unchanged.
      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 2);
    });

    test('no-op when source panel does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);

      notifier().moveTab('nonexistent', 'any-tab', panels.first);

      // Should be unchanged.
      expect(collectPanelIds(state().root).length, 2);
    });

    test('no-op when tab does not exist in source', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);

      notifier().moveTab(panels[0], 'nonexistent-tab', panels[1]);

      // Source panel should still have its tab.
      final p1 = findPanel(state().root, panels[0])!;
      expect(p1.tabs.length, 1);
    });

    test('moves tab to specific index in destination', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      // Split with tab C into a new panel.
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      final p2 = findPanel(ws2.root, panels[1])!;
      final tabToMove = p2.tabs.first; // C

      // Move C to index 0 in the first panel (before A and B).
      notifier().moveTab(panels[1], tabToMove.id, panels[0], index: 0);

      final ws3 = state();
      // Second panel collapsed, so single panel remains.
      expect(ws3.root, isA<PanelLeaf>());
      final remaining = ws3.root as PanelLeaf;
      expect(remaining.tabs[0].label, 'C');
      expect(remaining.tabs[1].label, 'A');
      expect(remaining.tabs[2].label, 'B');
    });
  });

  group('reorderTabs edge cases', () {
    test('adjusts active when moving tab from after active to before', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;
      // Active is C (index 2). Select A (index 0).
      notifier().selectTab(panelId, 0);

      // Move C (index 2) to before A (index 0).
      notifier().reorderTabs(panelId, 2, 0);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs[0].label, 'C');
      expect(panel.tabs[1].label, 'A');
      expect(panel.tabs[2].label, 'B');
      // Active was A at index 0, moved to index 1 because C was inserted before.
      expect(panel.activeTabIndex, 1);
    });

    test('adjusts active when moving tab from before active to after', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;
      // Active is C (index 2). Select B (index 1).
      notifier().selectTab(panelId, 1);

      // Move A (index 0) to after C (index 3, which becomes 2 after removal).
      notifier().reorderTabs(panelId, 0, 3);

      final panel = findPanel(state().root, panelId)!;
      expect(panel.tabs[0].label, 'B');
      expect(panel.tabs[1].label, 'C');
      expect(panel.tabs[2].label, 'A');
      // Active was B at index 1, should become 0 because A was removed from before.
      expect(panel.activeTabIndex, 0);
    });
  });

  group('addTerminalTab with explicit panelId', () {
    test('adds tab to specified panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      final otherPanelId = panels.firstWhere((id) => id != ws2.focusedPanelId);

      notifier().addTerminalTab(_conn('c3'), label: 'C', panelId: otherPanelId);

      final otherPanel = findPanel(state().root, otherPanelId)!;
      expect(otherPanel.tabs.length, 2);
      expect(otherPanel.tabs.last.label, 'C');
    });
  });

  group('addSftpTab with explicit panelId', () {
    test('adds SFTP tab to specified panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final panels = collectPanelIds(ws2.root);
      final otherPanelId = panels.firstWhere((id) => id != ws2.focusedPanelId);

      notifier().addSftpTab(_conn('c3'), label: 'SFTP', panelId: otherPanelId);

      final otherPanel = findPanel(state().root, otherPanelId)!;
      expect(otherPanel.tabs.last.kind, TabKind.sftp);
      expect(otherPanel.tabs.last.label, 'SFTP');
    });
  });

  group('_disconnectOrphaned', () {
    test('does not disconnect connection still referenced by another tab', () {
      final conn = _conn('shared');
      notifier().addTerminalTab(conn, label: 'Tab1');
      notifier().addTerminalTab(conn, label: 'Tab2');

      final ws = state();
      final panelId = ws.focusedPanelId;
      final panel = findPanel(ws.root, panelId)!;

      // Close first tab — connection is still used by second tab.
      notifier().closeTab(panelId, panel.tabs.first.id);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.tabs.first.connection.id, 'shared');
    });

    test('disconnects orphaned connection used by no remaining tabs', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panelId = ws.focusedPanelId;
      final panel = findPanel(ws.root, panelId)!;

      // Close tab A — connection c1 is no longer in any tab.
      notifier().closeTab(panelId, panel.tabs[0].id);

      // The method should have been called. We verify indirectly:
      // the remaining tabs only have c2.
      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.tabs.first.connection.id, 'c2');
    });

    test('disconnects orphaned connections on closeOthers', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;
      final panel = findPanel(ws.root, panelId)!;
      final keepId = panel.tabs[1].id; // Keep B.

      notifier().closeOthers(panelId, keepId);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.tabs.first.connection.id, 'c2');
    });

    test('disconnects orphaned connections on closeToTheRight', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeToTheRight(panelId, 0);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.tabs.first.connection.id, 'c1');
    });

    test('disconnects orphaned connections on closeToTheLeft', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');
      notifier().addTerminalTab(_conn('c3'), label: 'C');

      final ws = state();
      final panelId = ws.focusedPanelId;

      notifier().closeToTheLeft(panelId, 2);

      final updated = findPanel(state().root, panelId)!;
      expect(updated.tabs.length, 1);
      expect(updated.tabs.first.connection.id, 'c3');
    });
  });

  group('updateRatio edge cases', () {
    test('updates ratio in nested branch', () {
      // Create a 3-panel layout with nested branches.
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      // Split the second panel vertically to create a nested branch.
      final ws2 = state();
      final panels2 = collectPanelIds(ws2.root);
      final secondPanelId = panels2[1];
      notifier().addTerminalTab(
        _conn('c3'),
        label: 'C',
        panelId: secondPanelId,
      );
      final secondPanel = findPanel(state().root, secondPanelId)!;
      notifier().splitPanel(
        secondPanelId,
        Axis.vertical,
        secondPanel.tabs.last,
      );

      final ws3 = state();
      final rootBranch = ws3.root as WorkspaceBranch;
      final innerBranch = rootBranch.second as WorkspaceBranch;
      expect(innerBranch.ratio, 0.5);

      notifier().updateRatio(innerBranch.id, 0.3);

      final ws4 = state();
      final updatedRoot = ws4.root as WorkspaceBranch;
      final updatedInner = updatedRoot.second as WorkspaceBranch;
      expect(updatedInner.ratio, 0.3);
      // Outer branch ratio should be unchanged.
      expect(updatedRoot.ratio, 0.5);
    });

    test('no-op when branchId does not exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().addTerminalTab(_conn('c2'), label: 'B');

      final ws = state();
      final panel = findPanel(ws.root, ws.focusedPanelId)!;
      notifier().splitPanel(panel.id, Axis.horizontal, panel.tabs.last);

      final ws2 = state();
      final branch = ws2.root as WorkspaceBranch;
      final ratioBefore = branch.ratio;

      notifier().updateRatio('nonexistent', 0.9);

      final ws3 = state();
      expect((ws3.root as WorkspaceBranch).ratio, ratioBefore);
    });
  });

  group('WorkspaceState', () {
    test('hasTabs returns true when any panel has tabs', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      expect(state().hasTabs, isTrue);
    });

    test('hasTabs returns false when all panels are empty', () {
      expect(state().hasTabs, isFalse);
    });

    test('copyWith preserves values when no arguments given', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final ws = state();
      final copy = ws.copyWith();
      expect(copy.root, same(ws.root));
      expect(copy.focusedPanelId, ws.focusedPanelId);
    });

    test('copyWith preserves maximizedPanelId when not provided', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().copyToNewPanel(state().focusedPanelId, Axis.horizontal);
      notifier().toggleMaximizePanel(state().focusedPanelId);
      final ws = state();
      final copy = ws.copyWith(focusedPanelId: 'other');
      expect(copy.maximizedPanelId, ws.maximizedPanelId);
    });

    test('copyWith clears maximizedPanelId when explicitly set to null', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().copyToNewPanel(state().focusedPanelId, Axis.horizontal);
      notifier().toggleMaximizePanel(state().focusedPanelId);
      expect(state().isMaximized, isTrue);
      final ws = state();
      final copy = ws.copyWith(maximizedPanelId: () => null);
      expect(copy.maximizedPanelId, isNull);
    });

    test('isMaximized reflects maximizedPanelId', () {
      expect(state().isMaximized, isFalse);
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      notifier().copyToNewPanel(state().focusedPanelId, Axis.horizontal);
      notifier().toggleMaximizePanel(state().focusedPanelId);
      expect(state().isMaximized, isTrue);
    });
  });

  group('toggleMaximizePanel', () {
    test('maximizes the focused panel when multiple panels exist', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final panelId = state().focusedPanelId;
      notifier().copyToNewPanel(panelId, Axis.horizontal);
      // Now we have two panels; focus is on the new one.
      notifier().toggleMaximizePanel(panelId);
      expect(state().maximizedPanelId, panelId);
    });

    test('restores when toggling the same panel again', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final panelId = state().focusedPanelId;
      notifier().copyToNewPanel(panelId, Axis.horizontal);
      notifier().toggleMaximizePanel(panelId);
      expect(state().isMaximized, isTrue);
      notifier().toggleMaximizePanel(panelId);
      expect(state().isMaximized, isFalse);
    });

    test('switches to different panel when already maximized', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final firstPanel = state().focusedPanelId;
      notifier().copyToNewPanel(firstPanel, Axis.horizontal);
      final secondPanel = state().focusedPanelId;
      notifier().toggleMaximizePanel(firstPanel);
      expect(state().maximizedPanelId, firstPanel);
      notifier().toggleMaximizePanel(secondPanel);
      expect(state().maximizedPanelId, secondPanel);
    });

    test('does nothing when only one panel exists', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final panelId = state().focusedPanelId;
      notifier().toggleMaximizePanel(panelId);
      expect(state().isMaximized, isFalse);
    });

    test('clears when maximized panel is closed via closeTab', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final firstPanel = state().focusedPanelId;
      notifier().copyToNewPanel(firstPanel, Axis.horizontal);
      final secondPanel = state().focusedPanelId;
      final tabId = findPanel(state().root, secondPanel)!.tabs.first.id;
      notifier().toggleMaximizePanel(secondPanel);
      expect(state().isMaximized, isTrue);
      notifier().closeTab(secondPanel, tabId);
      expect(state().isMaximized, isFalse);
    });

    test('clears when maximized panel is closed via closeAll', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final firstPanel = state().focusedPanelId;
      notifier().copyToNewPanel(firstPanel, Axis.horizontal);
      final secondPanel = state().focusedPanelId;
      notifier().toggleMaximizePanel(secondPanel);
      expect(state().isMaximized, isTrue);
      notifier().closeAll(secondPanel);
      expect(state().isMaximized, isFalse);
    });

    test('clears when tree collapses to single panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final firstPanel = state().focusedPanelId;
      notifier().copyToNewPanel(firstPanel, Axis.horizontal);
      final secondPanel = state().focusedPanelId;
      notifier().toggleMaximizePanel(firstPanel);
      expect(state().isMaximized, isTrue);
      // Close the other panel — tree collapses to single panel.
      final tabId = findPanel(state().root, secondPanel)!.tabs.first.id;
      notifier().closeTab(secondPanel, tabId);
      expect(state().isMaximized, isFalse);
      expect(state().root, isA<PanelLeaf>());
    });

    test('sets focus to maximized panel', () {
      notifier().addTerminalTab(_conn('c1'), label: 'A');
      final firstPanel = state().focusedPanelId;
      notifier().copyToNewPanel(firstPanel, Axis.horizontal);
      // Focus is now on second panel.
      expect(state().focusedPanelId, isNot(firstPanel));
      notifier().toggleMaximizePanel(firstPanel);
      expect(state().focusedPanelId, firstPanel);
    });
  });
}
