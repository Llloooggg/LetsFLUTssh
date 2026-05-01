part of 'expandable_tier_card.dart';

/// Header row of the tier card — badge + title + subtitle + chevron.
/// The whole row is the click target that toggles
/// [_ExpandableTierCardState._expanded]; tapping anywhere on it
/// expands or collapses, never just the chevron.
class _Header extends StatelessWidget {
  const _Header({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.expanded,
    required this.trailing,
    required this.onTap,
  });

  final String badge;
  final String title;
  final String subtitle;
  final Color accent;
  final bool expanded;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The whole header is clickable (tap → expand/collapse), so its
    // contents opt out of the ambient settings `SelectionArea`. Without
    // this wrap the title / subtitle were selectable yet the cursor
    // stayed a pointer (the InkWell's click cursor wins over the
    // ambient Selectable text cursor), which users read as "half-
    // broken". Rule: clickable tile ≠ selectable.
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusSm,
      child: SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: accent, width: 1),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: accent,
                    fontSize: AppFonts.xs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.fg,
                        fontSize: AppFonts.sm,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.fgDim,
                        fontSize: AppFonts.xs,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppTheme.fgDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Green "✓ Current" pill rendered in the trailing slot of the
/// header when this card matches the active tier and modifiers. The
/// header swaps it for the Select button as soon as the user toggles
/// any modifier that would change the applied config.
class _CurrentBadge extends StatelessWidget {
  const _CurrentBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.green, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 12, color: AppTheme.green),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.green,
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
