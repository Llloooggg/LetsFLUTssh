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
  final double? size;
  final double? boxSize;
  final Color? color;
  final Color? hoverColor;
  final Color? backgroundColor;
  final bool active;
  final BorderRadius? borderRadius;

  /// Pick a tighter default [boxSize]/[size] pair when unset. Used by dense
  /// toolbars (file browser, dialog headers) that want to stay compact on
  /// desktop without sacrificing the mobile touch target.
  final bool dense;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size,
    this.boxSize,
    this.color,
    this.hoverColor,
    this.backgroundColor,
    this.active = false,
    this.borderRadius,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? (active ? AppTheme.fg : AppTheme.fgDim);
    final disabledColor = iconColor.withValues(alpha: 0.3);
    final effectiveBox =
        boxSize ?? (dense ? AppTheme.iconBtnBoxDense : AppTheme.iconBtnBox);
    final effectiveIcon =
        size ?? (dense ? AppTheme.iconBtnIconDense : AppTheme.iconBtnIcon);

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
          width: effectiveBox,
          height: effectiveBox,
          decoration: BoxDecoration(color: bg, borderRadius: borderRadius),
          child: Icon(
            icon,
            size: effectiveIcon,
            color: onTap != null ? iconColor : disabledColor,
          ),
        );
      },
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    } else {
      button = Semantics(button: true, child: button);
    }

    return button;
  }
}
