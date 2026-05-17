import 'package:flutter/material.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/drop_zone_overlay.dart';
import 'package:letsflutssh/features/workspace/panel_tab_bar.dart';
import 'package:letsflutssh/features/workspace/workspace_drop_logic.dart';

void main() {
  group('dropZoneToSplitParams', () {
    test('center returns null — tab bar handles in-panel reorder', () {
      expect(dropZoneToSplitParams(DropZone.center), isNull);
    });

    test('left zone → horizontal axis, insertBefore=true', () {
      final p = dropZoneToSplitParams(DropZone.left)!;
      expect(p.axis, Axis.horizontal);
      expect(p.insertBefore, isTrue);
    });

    test('right zone → horizontal axis, insertBefore=false', () {
      final p = dropZoneToSplitParams(DropZone.right)!;
      expect(p.axis, Axis.horizontal);
      expect(p.insertBefore, isFalse);
    });

    test('top zone → vertical axis, insertBefore=true', () {
      final p = dropZoneToSplitParams(DropZone.top)!;
      expect(p.axis, Axis.vertical);
      expect(p.insertBefore, isTrue);
    });

    test('bottom zone → vertical axis, insertBefore=false', () {
      final p = dropZoneToSplitParams(DropZone.bottom)!;
      expect(p.axis, Axis.vertical);
      expect(p.insertBefore, isFalse);
    });

    test('every non-center zone returns a non-null params record', () {
      for (final zone in DropZone.values) {
        final result = dropZoneToSplitParams(zone);
        if (zone == DropZone.center) {
          expect(result, isNull);
        } else {
          expect(result, isNotNull, reason: '$zone must yield split params');
        }
      }
    });
  });

  group('applyTabDrop', () {
    final testTab = _makeTab('tab-1', 'demo');

    test('center zone is a no-op — no split, no close', () {
      final calls = _CallLog();
      applyTabDrop(
        splitPanel: calls.recordSplitPanel,
        closeTab: calls.recordCloseTab,
        data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
        targetPanelId: 'p-dst',
        zone: DropZone.center,
      );
      expect(calls.splitPanelCalls, isEmpty);
      expect(calls.closeTabCalls, isEmpty);
    });

    test(
      'cross-panel drop on left zone → splitPanel horizontal+before + close source',
      () {
        final calls = _CallLog();
        applyTabDrop(
          splitPanel: calls.recordSplitPanel,
          closeTab: calls.recordCloseTab,
          data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
          targetPanelId: 'p-dst',
          zone: DropZone.left,
        );
        expect(calls.splitPanelCalls.single.panelId, 'p-dst');
        expect(calls.splitPanelCalls.single.axis, Axis.horizontal);
        expect(calls.splitPanelCalls.single.tab, testTab);
        expect(calls.splitPanelCalls.single.insertBefore, isTrue);
        // Source panel is different → tab cleanup fires.
        expect(calls.closeTabCalls.single, ('p-src', 'tab-1'));
      },
    );

    test('right zone → horizontal+after; bottom → vertical+after', () {
      // Belt-and-braces — the four non-center zones each thread through
      // dropZoneToSplitParams and the helper must forward params verbatim.
      final calls = _CallLog();
      applyTabDrop(
        splitPanel: calls.recordSplitPanel,
        closeTab: calls.recordCloseTab,
        data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
        targetPanelId: 'p-dst',
        zone: DropZone.right,
      );
      expect(calls.splitPanelCalls.single.axis, Axis.horizontal);
      expect(calls.splitPanelCalls.single.insertBefore, isFalse);

      final calls2 = _CallLog();
      applyTabDrop(
        splitPanel: calls2.recordSplitPanel,
        closeTab: calls2.recordCloseTab,
        data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
        targetPanelId: 'p-dst',
        zone: DropZone.bottom,
      );
      expect(calls2.splitPanelCalls.single.axis, Axis.vertical);
      expect(calls2.splitPanelCalls.single.insertBefore, isFalse);
    });

    test(
      'same-panel drop skips closeTab — splitPanel already moves the tab',
      () {
        final calls = _CallLog();
        applyTabDrop(
          splitPanel: calls.recordSplitPanel,
          closeTab: calls.recordCloseTab,
          data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
          targetPanelId: 'p-src', // same!
          zone: DropZone.right,
        );
        expect(calls.splitPanelCalls, hasLength(1));
        expect(
          calls.closeTabCalls,
          isEmpty,
          reason: 'closeTab must NOT fire when source == target',
        );
      },
    );
  });

  group('applyTabRootEdgeDrop', () {
    final testTab = _makeTab('tab-1', 'demo');

    test('center zone is a no-op', () {
      final calls = _CallLog();
      applyTabRootEdgeDrop(
        splitAroundNode: calls.recordSplitAroundNode,
        closeTab: calls.recordCloseTab,
        rootId: 'root',
        sourceStillContainsTab: () =>
            throw StateError('must short-circuit before resolving'),
        data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
        zone: DropZone.center,
      );
      expect(calls.splitAroundNodeCalls, isEmpty);
      expect(calls.closeTabCalls, isEmpty);
    });

    test(
      'top zone → splitAroundNode vertical+before, close source on lookup hit',
      () {
        final calls = _CallLog();
        applyTabRootEdgeDrop(
          splitAroundNode: calls.recordSplitAroundNode,
          closeTab: calls.recordCloseTab,
          rootId: 'root-id',
          sourceStillContainsTab: () => true,
          data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
          zone: DropZone.top,
        );
        expect(calls.splitAroundNodeCalls.single.nodeId, 'root-id');
        expect(calls.splitAroundNodeCalls.single.axis, Axis.vertical);
        expect(calls.splitAroundNodeCalls.single.insertBefore, isTrue);
        expect(calls.closeTabCalls.single, ('p-src', 'tab-1'));
      },
    );

    test('source panel already lost the tab → close skipped', () {
      // splitAroundNode may have already absorbed the tab when the
      // source panel collapsed into the new wrapper; the lookup
      // returns false and the helper must NOT fire a redundant
      // closeTab against a tab id that no longer exists.
      final calls = _CallLog();
      applyTabRootEdgeDrop(
        splitAroundNode: calls.recordSplitAroundNode,
        closeTab: calls.recordCloseTab,
        rootId: 'root',
        sourceStillContainsTab: () => false,
        data: TabDragData(tab: testTab, sourcePanelId: 'p-src'),
        zone: DropZone.left,
      );
      expect(calls.splitAroundNodeCalls, hasLength(1));
      expect(calls.closeTabCalls, isEmpty);
    });
  });
}

/// Recording helpers — each apply* helper reaches the notifier
/// through function pointers, so the tests pass these methods as the
/// seam and assert on what landed in the lists.
class _CallLog {
  final List<({String panelId, Axis axis, TabEntry tab, bool insertBefore})>
  splitPanelCalls = [];
  final List<({String nodeId, Axis axis, TabEntry tab, bool insertBefore})>
  splitAroundNodeCalls = [];
  final List<(String, String)> closeTabCalls = [];

  void recordSplitPanel(
    String panelId,
    Axis axis,
    TabEntry tab, {
    required bool insertBefore,
  }) {
    splitPanelCalls.add((
      panelId: panelId,
      axis: axis,
      tab: tab,
      insertBefore: insertBefore,
    ));
  }

  void recordSplitAroundNode(
    String nodeId,
    Axis axis,
    TabEntry tab, {
    required bool insertBefore,
  }) {
    splitAroundNodeCalls.add((
      nodeId: nodeId,
      axis: axis,
      tab: tab,
      insertBefore: insertBefore,
    ));
  }

  void recordCloseTab(String panelId, String tabId) {
    closeTabCalls.add((panelId, tabId));
  }
}

TabEntry _makeTab(String id, String label) {
  final connection = Connection(
    id: 'conn-$id',
    label: label,
    sshConfig: const SSHConfig(
      server: ServerAddress(host: 'h', user: 'u'),
    ),
  );
  return TabEntry(
    id: id,
    label: label,
    connection: connection,
    kind: TabKind.terminal,
  );
}
