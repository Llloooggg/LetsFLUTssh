import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_region.dart';

/// Consistent icon button — rectangular hover, no splash, no ripple.
///
/// Replaces all `IconButton` / `GestureDetector(child: Icon(...))` patterns
/// across the app with a single unified look:
/// - Rectangular shape (no circular splash)
/// - Hover background via [AppTheme.hover] (or custom [hoverColor])
/// - Active state via [AppTheme.active]
/// - Disabled state (null [onTap]) dims icon to 30% opacity
///
/// ```dart
/// AppIconButton(
///   icon: Icons.settings,
///   onTap: () => openSettings(),
///   tooltip: 'Settings',
/// )
/// ```
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double boxSize;
  final Color? color;
  final Color? hoverColor;
  final Color? backgroundColor;
  final bool active;
  final BorderRadius? borderRadius;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 14,
    this.boxSize = 26,
    this.color,
    this.hoverColor,
    this.backgroundColor,
    this.active = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? (active ? AppTheme.fg : AppTheme.fgDim);
    final disabledColor = iconColor.withValues(alpha: 0.3);

    Widget button = HoverRegion(
      onTap: onTap,
      builder: (hovered) {
        final Color bg;
        if (active) {
          bg = AppTheme.active;
        } else if (hovered && onTap != null) {
          bg = hoverColor ?? AppTheme.hover;
        } else {
          bg = backgroundColor ?? Colors.transparent;
        }
        return Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
          child: Icon(
            icon,
            size: size,
            color: onTap != null ? iconColor : disabledColor,
          ),
        );
      },
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
