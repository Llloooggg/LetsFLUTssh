import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Draggable column-resize handle for table headers.
///
/// Place between a flexible column and a fixed-width column.
/// The [onDrag] callback receives the raw horizontal delta (positive = right).
/// Callers negate the delta when the fixed column is to the right of the handle
/// (so dragging right shrinks the column).
class ColumnResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;

  const ColumnResizeHandle({super.key, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: 10,
          height: 24,
          child: Center(
            child: Container(
              width: 1,
              height: 14,
              color: AppTheme.fgFaint.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
