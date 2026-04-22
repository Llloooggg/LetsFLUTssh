import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_region.dart';

/// Left-aligned picker button used in the session-edit form for
/// "pick a key from the key store" / "pick a key file" flows.
///
/// Why a dedicated widget instead of another [AppButton] factory:
/// the picker row needs a column-wide, left-aligned row with a
/// leading icon, a primary label that ellipsises, and a trailing
/// chevron that signals "tap to open a picker". [AppButton] centers
/// its content and drops the leading chevron — fighting both with
/// overrides would leak a `DropdownSelectButton` shape into
/// [AppButton]'s API for the benefit of two callsites. Cleaner to
/// ship it as its own widget.
///
/// Visually matches [StyledFormField] (same `bg3` fill, `borderLight`
/// border, `radiusSm`, `controlHeightMd`) so the picker aligns with
/// the adjacent text fields in a form column.
class DropdownSelectButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;
  final double? height;

  const DropdownSelectButton({
    super.key,
    this.icon,
    required this.label,
    this.onTap,
    this.showChevron = true,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveHeight = height ?? AppTheme.controlHeightMd;
    final fg = enabled ? AppTheme.fg : AppTheme.fgFaint;
    final iconColor = enabled ? AppTheme.fgDim : AppTheme.fgFaint;

    return HoverRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: enabled ? onTap : null,
      builder: (hovered) => Container(
        height: effectiveHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hovered && enabled ? AppTheme.hover : AppTheme.bg3,
          borderRadius: AppTheme.radiusSm,
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.inter(fontSize: AppFonts.sm, color: fg),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down, size: 18, color: iconColor),
            ],
          ],
        ),
      ),
    );
  }
}
