part of 'security_setup_dialog.dart';

/// Single tier row inside the wizard's tier list. Renders a radio
/// dot + accent badge + label + subtitle, with optional `current` /
/// `recommended` chips. Disabled rows (passing a null `onSelect`)
/// dim themselves and surface [disabledReason] in place of the
/// subtitle.
class _TierRow extends StatelessWidget {
  final String badge;
  final String label;
  final String subtitle;
  final Color accent;
  final bool selected;
  final bool current;
  final bool recommended;
  final String? disabledReason;
  final VoidCallback? onSelect;

  const _TierRow({
    required this.badge,
    required this.label,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.current,
    required this.onSelect,
    this.recommended = false,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onSelect == null;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: _radioIconColor(
              disabled: disabled,
              selected: selected,
              accent: accent,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: AppFonts.xs,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppFonts.md,
                        fontWeight: FontWeight.w600,
                        color: disabled ? AppTheme.fgFaint : AppTheme.fg,
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.fgDim.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          S.of(context).currentTierBadge,
                          style: TextStyle(
                            fontSize: AppFonts.xxs,
                            color: AppTheme.fgDim,
                          ),
                        ),
                      ),
                    ],
                    if (recommended && !current) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.green.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          S.of(context).recommendedBadge,
                          style: TextStyle(
                            fontSize: AppFonts.xxs,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  disabledReason ?? subtitle,
                  style: TextStyle(
                    fontSize: AppFonts.xs,
                    color: disabled ? AppTheme.fgFaint : AppTheme.fgDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: disabled ? null : onSelect,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? accent : AppTheme.borderLight,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Opacity(opacity: disabled ? 0.55 : 1.0, child: content),
      ),
    );
  }

  static Color _radioIconColor({
    required bool disabled,
    required bool selected,
    required Color accent,
  }) {
    if (disabled) return AppTheme.fgFaint;
    return selected ? accent : AppTheme.fgDim;
  }
}

/// Single modifier row (password / biometric / auto-lock toggle).
/// Two-line layout — bold label + muted subtitle / disabled-reason
/// — plus a leading icon and trailing Switch. Disabled rows surface
/// [disabledReason] in place of the subtitle so the user understands
/// why the toggle won't flip.
class _ModifierToggle extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final bool enabled;
  final String? disabledReason;
  final ValueChanged<bool> onChanged;

  const _ModifierToggle({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.fgDim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFonts.sm,
                    color: enabled ? AppTheme.fg : AppTheme.fgFaint,
                  ),
                ),
                Text(
                  disabledReason ?? subtitle,
                  style: TextStyle(
                    fontSize: AppFonts.xs,
                    color: enabled ? AppTheme.fgDim : AppTheme.fgFaint,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

/// Horizontal rule with a centered caption — splits the wizard into
/// "primary tier picks" and "Paranoid alternative" sections so the
/// user reads them as discrete options instead of a single long list.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppTheme.borderLight)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            S.of(context).paranoidAlternativeHeader,
            style: TextStyle(
              fontSize: AppFonts.xs,
              color: AppTheme.fgDim,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: AppTheme.borderLight)),
      ],
    );
  }
}

/// Warning banner shown at the top of the wizard when the capability
/// probe came back with no T1 and no T2. Yellow — the user is about
/// to pick between unencrypted storage and a master password with
/// no middle ground, which is a diminished-state posture worth
/// flagging.
class _ReducedWizardBanner extends StatelessWidget {
  const _ReducedWizardBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.yellow.withValues(alpha: 0.12),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: AppTheme.yellow),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, size: 18, color: AppTheme.yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Red-bordered acknowledgement panel attached to the T0 (plaintext)
/// option. The Apply button stays disabled until the user ticks the
/// checkbox — a hard gate so a stray click cannot drop the user into
/// unencrypted storage without a deliberate action.
class _PlaintextAckPanel extends StatelessWidget {
  final bool acknowledged;
  final ValueChanged<bool> onChanged;

  const _PlaintextAckPanel({
    required this.acknowledged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
        color: AppTheme.red.withValues(alpha: 0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, size: 18, color: AppTheme.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.plaintextWarningTitle,
                  style: TextStyle(
                    fontSize: AppFonts.sm,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.plaintextWarningBody,
            style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: acknowledged,
                onChanged: (v) => onChanged(v ?? false),
              ),
              Expanded(
                child: Text(
                  l10n.plaintextAcknowledge,
                  style: TextStyle(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Yellow info card that surfaces the capability-probe note for the
/// currently-selected tier ("biometric not enrolled", "TPM
/// requires reboot", etc.) under the tier list.
class _HonestyNote extends StatelessWidget {
  final String text;

  const _HonestyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.yellow.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
        color: AppTheme.yellow.withValues(alpha: 0.05),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
            ),
          ),
        ],
      ),
    );
  }
}
