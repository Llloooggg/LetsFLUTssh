import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';

TabEntry _tab(String id, {TabKind kind = TabKind.terminal}) {
  const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'));
  final conn = Connection(id: id, sshConfig: config, label: id);
  return TabEntry(id: id, label: id, connection: conn, kind: kind);
}

void main() {
  group('PanelLeaf', () {
    test('activeTab returns correct tab', () {
      final t1 = _tab('t1');
      final t2 = _tab('t2');
      final panel = PanelLeaf(tabs: [t1, t2], activeTabIndex: 1);

      expect(panel.activeTab, t2);
    });

    test('activeTab returns null when index is -1', () {
      final panel = PanelLeaf(tabs: [], activeTabIndex: -1);
      expect(panel.activeTab, isNull);
    });

    test('activeTab returns null when index out of range', () {
      final t1 = _tab('t1');
      final panel = PanelLeaf(tabs: [t1], activeTabIndex: 5);
      expect(panel.activeTab, isNull);
    });

    test('copyWith preserves id', () {
      final panel = PanelLeaf(id: 'p1', tabs: [_tab('t1')], activeTabIndex: 0);
      final copy = panel.copyWith(activeTabIndex: -1);
      expect(copy.id, 'p1');
      expect(copy.activeTabIndex, -1);
      expect(copy.tabs.length, 1);
    });
  });

  group('replaceWorkspaceNode', () {
    test('replaces root when id matches', () {
      final panel = PanelLeaf(id: 'p1');
      final replacement = PanelLeaf(id: 'p2');
      final result = replaceWorkspaceNode(panel, 'p1', replacement);
      expect(result.id, 'p2');
    });

    test('replaces child in branch', () {
      final p1 = PanelLeaf(id: 'p1');
      final p2 = PanelLeaf(id: 'p2');
      final branch = WorkspaceBranch(
        id: 'b1',
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final replacement = PanelLeaf(id: 'p3');
      final result = replaceWorkspaceNode(branch, 'p2', replacement);
      expect(result, isA<WorkspaceBranch>());
      final b = result as WorkspaceBranch;
      expect(b.first.id, 'p1');
      expect(b.second.id, 'p3');
    });

    test('returns unchanged tree when target not found', () {
      final panel = PanelLeaf(id: 'p1');
      final result = replaceWorkspaceNode(panel, 'nonexistent', PanelLeaf());
      expect(result.id, 'p1');
    });
  });

  group('removeWorkspaceNode', () {
    test('returns null when removing root', () {
      final panel = PanelLeaf(id: 'p1');
      final result = removeWorkspaceNode(panel, 'p1');
      expect(result, isNull);
    });

    test('promotes sibling when first child removed', () {
      final p1 = PanelLeaf(id: 'p1');
      final p2 = PanelLeaf(id: 'p2');
      final branch = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final result = removeWorkspaceNode(branch, 'p1');
      expect(result?.id, 'p2');
    });

    test('promotes sibling when second child removed', () {
      final p1 = PanelLeaf(id: 'p1');
      final p2 = PanelLeaf(id: 'p2');
      final branch = WorkspaceBranch(
        direction: Axis.vertical,
        first: p1,
        second: p2,
      );
      final result = removeWorkspaceNode(branch, 'p2');
      expect(result?.id, 'p1');
    });

    test('removes nested leaf and promotes sibling', () {
      final p1 = PanelLeaf(id: 'p1');
      final p2 = PanelLeaf(id: 'p2');
      final p3 = PanelLeaf(id: 'p3');
      final inner = WorkspaceBranch(
        id: 'inner',
        direction: Axis.horizontal,
        first: p2,
        second: p3,
      );
      final root = WorkspaceBranch(
        id: 'root',
        direction: Axis.vertical,
        first: p1,
        second: inner,
      );

      final result = removeWorkspaceNode(root, 'p2');
      expect(result, isA<WorkspaceBranch>());
      final b = result as WorkspaceBranch;
      expect(b.first.id, 'p1');
      expect(b.second.id, 'p3');
    });

    test('returns unchanged tree when target not found', () {
      final p1 = PanelLeaf(id: 'p1');
      final result = removeWorkspaceNode(p1, 'nonexistent');
      expect(result?.id, 'p1');
    });
  });

  group('collectPanelIds', () {
    test('returns single id for leaf', () {
      final panel = PanelLeaf(id: 'p1');
      expect(collectPanelIds(panel), ['p1']);
    });

    test('returns all ids in tree order', () {
      final p1 = PanelLeaf(id: 'p1');
      final p2 = PanelLeaf(id: 'p2');
      final p3 = PanelLeaf(id: 'p3');
      final inner = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p2,
        second: p3,
      );
      final root = WorkspaceBranch(
        direction: Axis.vertical,
        first: p1,
        second: inner,
      );
      expect(collectPanelIds(root), ['p1', 'p2', 'p3']);
    });
  });

  group('findPanel', () {
    test('finds panel by id', () {
      final p1 = PanelLeaf(id: 'p1', tabs: [_tab('t1')]);
      final p2 = PanelLeaf(id: 'p2');
      final root = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final found = findPanel(root, 'p1');
      expect(found, isNotNull);
      expect(found!.tabs.length, 1);
    });

    test('returns null when not found', () {
      final panel = PanelLeaf(id: 'p1');
      expect(findPanel(panel, 'nonexistent'), isNull);
    });
  });

  group('updatePanel', () {
    test('updates matching panel', () {
      final t1 = _tab('t1');
      final t2 = _tab('t2');
      final panel = PanelLeaf(id: 'p1', tabs: [t1], activeTabIndex: 0);

      final updated = updatePanel(panel, 'p1', (p) {
        return p.copyWith(tabs: [...p.tabs, t2], activeTabIndex: 1);
      });

      expect(updated, isA<PanelLeaf>());
      final p = updated as PanelLeaf;
      expect(p.tabs.length, 2);
      expect(p.activeTabIndex, 1);
    });

    test('leaves non-matching panels unchanged', () {
      final p1 = PanelLeaf(id: 'p1', tabs: [_tab('t1')]);
      final p2 = PanelLeaf(id: 'p2');
      final root = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );

      final updated = updatePanel(root, 'p2', (p) {
        return p.copyWith(tabs: [_tab('t2')], activeTabIndex: 0);
      });

      expect(updated, isA<WorkspaceBranch>());
      final b = updated as WorkspaceBranch;
      expect((b.first as PanelLeaf).tabs.length, 1);
      expect((b.second as PanelLeaf).tabs.length, 1);
      expect((b.second as PanelLeaf).tabs.first.id, 't2');
    });
  });

  group('collectAllTabs', () {
    test('collects tabs from single panel', () {
      final panel = PanelLeaf(tabs: [_tab('t1'), _tab('t2')]);
      final tabs = collectAllTabs(panel);
      expect(tabs.length, 2);
    });

    test('collects tabs from multiple panels', () {
      final p1 = PanelLeaf(tabs: [_tab('t1')]);
      final p2 = PanelLeaf(tabs: [_tab('t2'), _tab('t3')]);
      final root = WorkspaceBranch(
        direction: Axis.horizontal,
        first: p1,
        second: p2,
      );
      final tabs = collectAllTabs(root);
      expect(tabs.length, 3);
      expect(tabs.map((t) => t.id), ['t1', 't2', 't3']);
    });

    test('returns empty list for empty panels', () {
      final panel = PanelLeaf();
      expect(collectAllTabs(panel), isEmpty);
    });
  });
}
