/// Pure helpers for the workspace's tab-drop handlers. Splitting a
/// panel from a drop zone walks two independent decisions —
/// horizontal vs vertical axis, and "before" vs "after" — which
/// were inlined inside both `_handleDrop` and `_handleRootEdgeDrop`
/// in `WorkspaceViewState`. Extracting the mapping here keeps the
/// two call sites in lockstep and gives one test target for the
/// "center is inert" / four-zone-axis-pair contract.
library;

import 'package:flutter/material.dart' show Axis;

import 'drop_zone_overlay.dart';

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
