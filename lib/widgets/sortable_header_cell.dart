import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_region.dart';

/// Reusable sortable column-header cell for table views.
///
/// Shows a label with optional sort-direction arrow.
/// Highlights on hover and when active (sorted by this column).
class SortableHeaderCell extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool sortAscending;
  final VoidCallback onTap;
  final TextStyle style;
  final double? width;
  final TextAlign? textAlign;

  const SortableHeaderCell({
    super.key,
    required this.label,
    required this.isActive,
    required this.sortAscending,
    required this.onTap,
    required this.style,
    this.width,
    this.textAlign,
  });

  static String _sortSuffix(bool active, bool ascending) {
    if (!active) return '';
    return ascending ? ' ↑' : ' ↓';
  }

  @override
  Widget build(BuildContext context) {
    final sortSuffix = _sortSuffix(isActive, sortAscending);
    return HoverRegion(
      cursor: SystemMouseCursors.click,
      onTap: onTap,
      builder: (hovered) {
        final color = _headerColor(isActive, hovered);
        return SizedBox(
          width: width,
          child: Text(
            '$label$sortSuffix',
            style: color != null ? style.copyWith(color: color) : style,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
          ),
        );
      },
    );
  }

  static Color? _headerColor(bool isActive, bool hovered) {
    if (isActive) return AppTheme.accent;
    if (hovered) return AppTheme.fgDim;
    return null;
  }
}

/// Thin vertical divider between table columns (for data rows, not headers).
///
/// Headers use [ColumnResizeHandle] instead.
Widget columnDivider() {
  return SizedBox(
    width: 10,
    child: Center(
      child: Container(
        width: 1,
        color: AppTheme.fgFaint.withValues(alpha: 0.15),
      ),
    ),
  );
}
