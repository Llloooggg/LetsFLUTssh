part of 'expandable_tier_card.dart';

/// Fixed-order threat list — same 8 items, same positions, on every
/// tier card. Users scanning four cards side-by-side compare the
/// ✓/✗ column vertically without re-reading labels.
///
/// *Status rule:* rows render the **best-case** status for this
/// tier — i.e. what the tier protects against once all applicable
/// modifiers are on. Rows that the password modifier unlocks carry
/// an "only with password" hint (text on wide layouts, key icon on
/// narrow). The hint disambiguates "this tier can protect it, but
/// only if you enable the password toggle" from "this tier protects
/// it unconditionally" — which is what separates T1 from T2 on the
/// `keyringFileTheft` row without needing to flip the checkmark
/// itself. Showing the live ✗ when the toggle is off flattened the
/// T1-vs-T2 comparison because both tiers ended up with the same
/// checkmark shape — the hint is the signal users rely on instead.
class _ThreatListFixed extends StatelessWidget {
  const _ThreatListFixed({required this.model, required this.l10n});

  final ThreatModel model;
  final S l10n;

  @override
  Widget build(BuildContext context) {
    // Evaluate the tier at its best-case config — password on where
    // the tier supports the modifier, always on for Paranoid. The
    // rendered ✓/✗ does not depend on the user's current toggle
    // state; only the per-row "only with password" hint does.
    final bestModel = ThreatModel(
      tier: model.tier,
      password: model.tier != ThreatTier.plaintext,
    );
    final statusMap = evaluate(bestModel);
    final withoutPassword = evaluate(ThreatModel(tier: model.tier));
    // "This row is password-gated" — best case is ✓ but the
    // no-password version is ✗. The hint surfaces regardless of
    // whether the toggle is currently on: the user should always
    // know which rows depend on the password modifier, even when
    // that modifier is already enabled. Keeps the comparison
    // between tier cards stable — same hint pattern on T1 vs T2
    // no matter what the pending selection is.
    final passwordGated = <SecurityThreat>{};
    for (final t in SecurityThreat.values) {
      if (statusMap[t] == ThreatStatus.protects &&
          withoutPassword[t] == ThreatStatus.doesNotProtect) {
        passwordGated.add(t);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in SecurityThreat.values)
          _ThreatLine(
            threat: t,
            protects: statusMap[t] == ThreatStatus.protects,
            showsPasswordHint: passwordGated.contains(t),
            l10n: l10n,
          ),
      ],
    );
  }
}

class _ThreatLine extends StatelessWidget {
  const _ThreatLine({
    required this.threat,
    required this.protects,
    required this.showsPasswordHint,
    required this.l10n,
  });

  final SecurityThreat threat;
  final bool protects;
  final bool showsPasswordHint;
  final S l10n;

  @override
  Widget build(BuildContext context) {
    // Layout threshold — below this width the text form of the
    // "(only with password)" hint runs out of room next to a
    // translated threat title (German / Russian / Portuguese grow
    // the title by 30-50 %), so we fall back to a key icon that
    // conveys the same "needs password" signal in ~12 px instead
    // of ~120 px. Keeps the two-line ellipsis workaround from
    // triggering on phones. Tooltip on the icon carries the full
    // text for accessibility and desktop-wide hover.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHint = constraints.maxWidth < 340;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  protects ? Icons.check : Icons.close,
                  size: 12,
                  color: protects ? AppTheme.green : AppTheme.red,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        threatTitle(threat, l10n),
                        style: TextStyle(
                          color: AppTheme.fg,
                          fontSize: AppFonts.xs,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showsPasswordHint) ...[
                      const SizedBox(width: 6),
                      if (compactHint)
                        Tooltip(
                          message: l10n.modifierOnlyWithPassword,
                          child: Icon(
                            Icons.key,
                            size: 12,
                            color: AppTheme.fgDim,
                          ),
                        )
                      else
                        Flexible(
                          child: Text(
                            '(${l10n.modifierOnlyWithPassword})',
                            style: TextStyle(
                              color: AppTheme.fgDim,
                              fontSize: AppFonts.xs,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnavailableReason extends StatelessWidget {
  const _UnavailableReason({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.yellow.withValues(alpha: 0.1),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.yellow.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, size: 14, color: AppTheme.yellow),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.xs),
            ),
          ),
        ],
      ),
    );
  }
}
