import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact icon + number indicator with an optional tooltip.
///
/// Used in status bars and footers to display counts (e.g. sessions,
/// active connections, open tabs) in a uniform style.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.icon,
    required this.count,
    required this.tooltip,
    this.iconColor,
  });

  /// The icon to display.
  final IconData icon;

  /// The numeric count shown next to the icon.
  final int count;

  /// Tooltip text shown on hover.
  final String tooltip;

  /// Override for the icon color. When null, uses the default dim color.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final dimColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    final color = iconColor ?? dimColor;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: AppFonts.inter(fontSize: AppFonts.xs, color: dimColor),
          ),
        ],
      ),
    );
  }
}
