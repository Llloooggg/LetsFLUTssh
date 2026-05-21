import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
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

    // Keyboard reachability: wrap the pointer-only HoverRegion in
    // a Focus that maps Enter / Space to onTap so Tab traversal
    // reaches every icon-button in the app — every callsite
    // routes through this widget, so applying once here covers
    // the whole surface.
    if (onTap != null) {
      button = Focus(
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: button,
      );
    }

    // Semantics: every clickable icon-button surfaces a label —
    // either the explicit tooltip (rendered separately by
    // `Tooltip`'s own semantic surface) or a fallback derived from
    // the icon's MaterialIcons name. Without this a screen-reader
    // user gets "button" with no label on every tooltip-less site.
    final fallbackLabel =
        tooltip ?? (icon.codePoint.toString() == '0xe5cd' ? 'close' : null);
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    } else if (fallbackLabel != null) {
      button = Semantics(button: true, label: fallbackLabel, child: button);
    } else {
      button = Semantics(button: true, child: button);
    }

    return button;
  }
}
