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
  const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'));
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
      // Original tab stays.
      expect(original.tabs.length, 1);
      expect(original.tabs.first.label, 'A');
      // Copy has same label/connection but different id.
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
      // Still a single panel — nothing happened.
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
}
