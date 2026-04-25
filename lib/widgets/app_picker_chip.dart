import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_region.dart';

/// Reusable selector chip — a button that visually represents one
/// choice in a small set (e.g. ProxyJump mode picker, port-forward
/// kind picker). Active state pulses the border + background with
/// the accent colour.
///
/// **Why a custom chip instead of Material's `ChoiceChip`.** ChoiceChip
/// brings Material visuals that don't match the rest of the design
/// system (rounded pill, ripple, internal padding). We already have
/// `AppTheme.bg3` / `AppTheme.borderLight` / `AppTheme.accent` and
/// `HoverRegion` for hover state — keeping the chip in the same
/// language stays consistent.
///
/// **`SelectionContainer.disabled`** disables the global
/// SelectionArea wrapper, so the chip's label cannot be selected /
/// copied like body text. The chip is a button — text-selection
/// gestures inside it are a UX bug, not a feature.
class AppPickerChip extends StatelessWidget {
  /// Whether this chip represents the currently-active choice.
  final bool active;

  /// Visible label.
  final String label;

  /// Click handler. Null disables the chip (used for "this option is
  /// not applicable in current mode" hints).
  final VoidCallback? onTap;

  /// Optional icon shown left of the label.
  final IconData? icon;

  /// When true, the chip stretches to fill its parent (used in
  /// equal-width chip rows). When false, the chip hugs its content
  /// (used in inline contexts).
  final bool expand;

  const AppPickerChip({
    super.key,
    required this.active,
    required this.label,
    this.onTap,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final chip = SelectionContainer.disabled(
      child: HoverRegion(
        onTap: onTap,
        builder: (hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.15)
                : (hovered ? AppTheme.hover : AppTheme.bg3),
            borderRadius: AppTheme.radiusSm,
            border: Border.all(
              color: active ? AppTheme.accent : AppTheme.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 12,
                  color: active ? AppTheme.fg : AppTheme.fgFaint,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? AppTheme.fg : AppTheme.fgFaint,
                    fontFamily: 'Inter',
                    fontSize: AppFonts.xs,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? Expanded(child: chip) : chip;
  }
}
