import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_region.dart';

/// Collapsible "What to export/import" wrapper.
///
/// Renders a hoverable header with an expand/collapse chevron, a bold title,
/// and a subtitle on the right — typically used to surface the active preset
/// while the checkbox grid is collapsed. Shared by the unified export dialog
/// and the LFS import preview dialog so their headers stay visually
/// identical without duplicating the chevron/hover plumbing.
class CollapsibleCheckboxesSection extends StatelessWidget {
  final String title;
  final String? trailingLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget body;

  const CollapsibleCheckboxesSection({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.body,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HoverRegion(
          onTap: onToggle,
          builder: (hovered) => Container(
            color: hovered ? AppTheme.hover : null,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: AppTheme.fgDim,
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.fg,
                  ),
                ),
                if (trailingLabel != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trailingLabel!,
                      style: AppFonts.inter(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgDim,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (expanded) body,
      ],
    );
  }
}

/// One row in a data-selection grid: icon + label + optional subtitle /
/// warning text below the label + trailing text (count or size).
///
/// Shared by the export and import preview dialogs. The whole row is
/// tappable, so clicks anywhere toggle the checkbox.
///
/// Two subtitle slots on purpose: [subtitle] is a neutral dim caption (e.g.
/// the file path under a key name), [warningText] flips the icon + label
/// orange to flag the row as problematic. They're shown independently, so
/// a row can carry both a neutral path and a warning.
class DataCheckboxRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Nullable so callers can render a tristate "partially selected" state
  /// for select-all rows (null = mixed). Treated as false when [tristate]
  /// is false and value is null.
  final bool? value;

  /// When true, the underlying Checkbox is rendered as tristate — a null
  /// [value] shows the "mixed" indeterminate square instead of an empty box.
  final bool tristate;
  final VoidCallback onTap;

  /// Right-aligned status label (count, size, "Yes"/"No"). Null hides it.
  final String? trailingLabel;

  /// Optional warning text rendered under the label. When set, the icon and
  /// label are tinted with [AppTheme.orange].
  final String? warningText;

  /// Optional neutral subtitle rendered under the label in dim color.
  /// Useful for metadata like a file path or a `user@host:port` summary.
  final String? subtitle;

  /// Optional explicit foreground color for the label. Overrides the
  /// warning/fg auto-pick. Used to render already-imported rows dimmed out.
  final Color? labelColor;

  /// Optional explicit color for the leading icon. When omitted the icon
  /// follows [labelColor] / warning styling, preserving the old behaviour.
  /// Used by the tag picker to render a tag-coloured dot as the leading
  /// glyph without tinting the label text itself.
  final Color? iconColor;

  const DataCheckboxRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailingLabel,
    this.warningText,
    this.subtitle,
    this.labelColor,
    this.iconColor,
    this.tristate = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasWarning = warningText != null;
    final accent = labelColor ?? (hasWarning ? AppTheme.orange : AppTheme.fg);
    final iconTint = iconColor ?? accent;
    return HoverRegion(
      onTap: onTap,
      builder: (hovered) => Container(
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Checkbox(
              value: tristate ? value : (value ?? false),
              tristate: tristate,
              onChanged: (_) => onTap(),
            ),
            Icon(icon, size: 16, color: iconTint),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: AppFonts.md,
                      color: accent,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppFonts.mono(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgDim,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (hasWarning)
                    Text(
                      warningText!,
                      style: AppFonts.inter(
                        fontSize: AppFonts.xs,
                        color: AppTheme.orange,
                      ),
                    ),
                ],
              ),
            ),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
