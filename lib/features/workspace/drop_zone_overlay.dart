import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'panel_tab_bar.dart';

/// Which edge the user is hovering over during a drag.
///
/// [center] is kept in the enum for workspace-level compatibility but
/// panel drop targets never emit it — tab insertion into a panel is
/// handled exclusively by the tab bar (with positional ordering).
enum DropZone { center, left, right, top, bottom }

/// Wraps a panel's content area and shows snap/dock indicators when a
/// [TabDragData] is dragged over it.
///
/// Drop zones divide the panel into four edge regions. The center area
/// is intentionally inert — to add a tab to a panel, drag it onto the
/// panel's tab bar instead.
/// ```
/// ┌──────────────────────────┐
/// │         TOP (33%)         │
/// │┌──────┐──────────┌──────┐│
/// ││ LEFT ││  (inert) ││RIGHT││
/// ││ 33%  ││         ││ 33%  ││
/// │└──────┘──────────└──────┘│
/// │        BOTTOM (33%)       │
/// └──────────────────────────┘
/// ```
class PanelDropTarget extends StatefulWidget {
  final String panelId;
  final Widget child;
  final void Function(TabDragData data, DropZone zone) onDrop;

  const PanelDropTarget({
    super.key,
    required this.panelId,
    required this.child,
    required this.onDrop,
  });

  @override
  State<PanelDropTarget> createState() => _PanelDropTargetState();
}

class _PanelDropTargetState extends State<PanelDropTarget> {
  DropZone? _activeZone;
  final _key = GlobalKey();

  DropZone? _zoneFromPosition(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final local = box.globalToLocal(global);
    final size = box.size;

    const edgeFraction = 0.33;
    final edgeX = size.width * edgeFraction;
    final edgeY = size.height * edgeFraction;

    if (local.dx < edgeX) return DropZone.left;
    if (local.dx > size.width - edgeX) return DropZone.right;
    if (local.dy < edgeY) return DropZone.top;
    if (local.dy > size.height - edgeY) return DropZone.bottom;
    return null; // Center — inert, tab bar handles insertion.
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final zone = _activeZone;
        setState(() => _activeZone = null);
        if (zone != null) {
          widget.onDrop(d.data, zone);
        }
      },
      onMove: (d) {
        final zone = _zoneFromPosition(d.offset);
        if (zone != _activeZone) {
          setState(() => _activeZone = zone);
        }
      },
      onLeave: (_) {
        if (_activeZone != null) {
          setState(() => _activeZone = null);
        }
      },
      builder: (context, candidates, _) {
        final showOverlay = candidates.isNotEmpty && _activeZone != null;
        return Stack(
          key: _key,
          children: [
            widget.child,
            if (showOverlay) _buildZoneOverlay(_activeZone!),
          ],
        );
      },
    );
  }

  Widget _buildZoneOverlay(DropZone zone) {
    final color = AppTheme.accent.withValues(alpha: 0.15);
    final border = Border.all(color: AppTheme.accent, width: 2);

    Alignment alignment;
    double widthFactor;
    double heightFactor;

    switch (zone) {
      case DropZone.center:
        return const SizedBox.shrink();
      case DropZone.left:
        alignment = Alignment.centerLeft;
        widthFactor = 0.5;
        heightFactor = 1.0;
      case DropZone.right:
        alignment = Alignment.centerRight;
        widthFactor = 0.5;
        heightFactor = 1.0;
      case DropZone.top:
        alignment = Alignment.topCenter;
        widthFactor = 1.0;
        heightFactor = 0.5;
      case DropZone.bottom:
        alignment = Alignment.bottomCenter;
        widthFactor = 1.0;
        heightFactor = 0.5;
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            heightFactor: heightFactor,
            child: Container(
              decoration: BoxDecoration(color: color, border: border),
            ),
          ),
        ),
      ),
    );
  }
}
