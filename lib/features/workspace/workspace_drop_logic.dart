/// Pure helpers for the workspace's tab-drop handlers. Splitting a
/// panel from a drop zone walks two independent decisions —
/// horizontal vs vertical axis, and "before" vs "after" — which
/// were inlined inside both `_handleDrop` and `_handleRootEdgeDrop`
/// in `WorkspaceViewState`. Extracting the mapping here keeps the
/// two call sites in lockstep and gives one test target for the
/// "center is inert" / four-zone-axis-pair contract.
library;

import 'package:flutter/material.dart' show Axis;

import '../tabs/tab_model.dart';
import 'drop_zone_overlay.dart';
import 'panel_tab_bar.dart';

/// Map a drop [zone] onto the split parameters for
/// `WorkspaceNotifier.splitPanel` / `splitAroundNode`. The center
/// zone is inert (the tab bar handles in-panel reordering), so it
/// returns `null`. Otherwise:
/// * left / right  → horizontal axis
/// * top / bottom  → vertical axis
/// * left / top    → insertBefore = true (the new tab lands first)
/// * right / bottom → insertBefore = false (the new tab lands last)
({Axis axis, bool insertBefore})? dropZoneToSplitParams(DropZone zone) {
  if (zone == DropZone.center) return null;
  final axis = zone == DropZone.left || zone == DropZone.right
      ? Axis.horizontal
      : Axis.vertical;
  final insertBefore = zone == DropZone.left || zone == DropZone.top;
  return (axis: axis, insertBefore: insertBefore);
}

/// Function-pointer signatures matching the relevant
/// `WorkspaceNotifier` methods. Defining them here keeps the apply
/// helpers below independent of the riverpod runtime — tests pass
/// recording lambdas, production passes the notifier method handles.
typedef SplitPanelFn =
    void Function(
      String panelId,
      Axis axis,
      TabEntry tab, {
      required bool insertBefore,
    });

typedef SplitAroundNodeFn =
    void Function(
      String nodeId,
      Axis axis,
      TabEntry tab, {
      required bool insertBefore,
    });

typedef CloseTabFn = void Function(String panelId, String tabId);

/// Apply a tab drop onto a panel. Mirrors
/// `_WorkspaceViewState._handleDrop` body, peeled out so the branch
/// (split vs no-op on center, source-panel cleanup) can be unit-tested
/// without booting the widget tree or simulating real drag gestures.
///
/// Center drops are inert: the tab bar owns in-panel reordering, so
/// the `dropZoneToSplitParams` short-circuit collapses to "do
/// nothing" rather than emitting a degenerate split call. Same-panel
/// drops (the user re-organising their own tab grid) skip the
/// `closeTab` step — `splitPanel` already moves the tab into the new
/// pane, and a redundant close would race against the post-split
/// activeTabIndex resolution.
void applyTabDrop({
  required SplitPanelFn splitPanel,
  required CloseTabFn closeTab,
  required TabDragData data,
  required String targetPanelId,
  required DropZone zone,
}) {
  final params = dropZoneToSplitParams(zone);
  if (params == null) return;
  splitPanel(
    targetPanelId,
    params.axis,
    data.tab,
    insertBefore: params.insertBefore,
  );
  if (data.sourcePanelId != targetPanelId) {
    closeTab(data.sourcePanelId, data.tab.id);
  }
}

/// Apply a tab drop on the workspace's outermost edge — splits
/// around the entire root node rather than a panel. Mirrors
/// `_WorkspaceViewState._handleRootEdgeDrop`. The source-panel
/// cleanup is gated by [sourceStillContainsTab] (which the caller
/// resolves against the live tree via `findPanel`) because the
/// `splitAroundNode` step may have already absorbed the tab when the
/// source panel collapsed into the new wrapper — in that case the
/// extra `closeTab` would target a tab id that no longer exists, and
/// the notifier currently no-ops on missing ids but the contract is
/// brittle, so we check first.
void applyTabRootEdgeDrop({
  required SplitAroundNodeFn splitAroundNode,
  required CloseTabFn closeTab,
  required String rootId,
  required bool Function() sourceStillContainsTab,
  required TabDragData data,
  required DropZone zone,
}) {
  final params = dropZoneToSplitParams(zone);
  if (params == null) return;
  splitAroundNode(
    rootId,
    params.axis,
    data.tab,
    insertBefore: params.insertBefore,
  );
  if (sourceStillContainsTab()) {
    closeTab(data.sourcePanelId, data.tab.id);
  }
}
