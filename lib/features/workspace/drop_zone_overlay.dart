import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'panel_tab_bar.dart';

/// Which edge (or center) the user is hovering over during a drag.
enum DropZone { center, left, right, top, bottom }

/// Wraps a panel's content area and shows snap/dock indicators when a
/// [TabDragData] is dragged over it.
///
/// Drop zones divide the panel into five regions:
/// ```
/// ┌──────────────────────────┐
/// │         TOP (25%)         │
/// │┌──────┐──────────┌──────┐│
/// ││ LEFT ││ CENTER  ││RIGHT ││
/// ││ 25%  ││  50%    ││ 25%  ││
/// │└──────┘──────────└──────┘│
/// │        BOTTOM (25%)       │
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

  DropZone _zoneFromPosition(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return DropZone.center;

    final local = box.globalToLocal(global);
    final size = box.size;

    const edgeFraction = 0.25;
    final edgeX = size.width * edgeFraction;
    final edgeY = size.height * edgeFraction;

    if (local.dx < edgeX) return DropZone.left;
    if (local.dx > size.width - edgeX) return DropZone.right;
    if (local.dy < edgeY) return DropZone.top;
    if (local.dy > size.height - edgeY) return DropZone.bottom;
    return DropZone.center;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        final zone = _activeZone ?? DropZone.center;
        setState(() => _activeZone = null);
        widget.onDrop(d.data, zone);
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
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(color: color, border: border),
              child: Center(
                child: Icon(
                  Icons.tab,
                  size: 32,
                  color: AppTheme.accent.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        );
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
