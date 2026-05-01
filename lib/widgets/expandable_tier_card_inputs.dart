part of 'expandable_tier_card.dart';

/// Modifier toggle row — label + optional subtitle + Switch. Shape
/// mirrors the auto-lock `_SettingsRow` so password / biometric /
/// auto-lock read as the same kind of setting instead of two bare
/// switches plus an explanatory tile. Disabled rows surface
/// [disabledReason] as a hover tooltip so the user understands why
/// the toggle cannot flip.
class _ModifierRow extends StatelessWidget {
  const _ModifierRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.icon,
    this.subtitle,
    this.disabledReason,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Leading icon rendered in the muted `fgDim` tone at size 16 to
  /// match the [_SettingsRow] leading-icon style that the auto-lock
  /// tile uses. Null hides the icon column — kept optional so
  /// unrelated callers (if any) can skip it.
  final IconData? icon;

  /// Second line under the label — one-sentence caption in `fgDim`
  /// at `AppFonts.xs`, mirrors the `_SettingsRow.subtitle` shape the
  /// auto-lock tile renders with. Shared so the three modifier rows
  /// (password / biometric / auto-lock) read as the same kind of
  /// setting instead of password+biometric looking like bare
  /// switches next to an explanatory auto-lock tile.
  final String? subtitle;

  /// Shown as a hover tooltip when the row is disabled — explains
  /// *why* the toggle cannot flip (tier not current, password not
  /// set, biometric unsupported by the platform, etc.). Tooltip is
  /// skipped when the row is enabled so the active state does not
  /// carry stale copy.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final labelBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          // Muted (`fgDim`) across every modifier row so password
          // / biometric / auto-lock labels sit at the same visual
          // weight. Earlier revisions used `fg` (full white) on
          // password + biometric while auto-lock used a
          // `_SettingsRow` with its default mix of `fg` label +
          // `fgDim` subtitle, which read as "three different
          // kinds of setting" instead of "three rows of the
          // same kind". Consistent muting keeps the Switch /
          // selector as the only element that draws attention.
          style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Text(
            subtitle!,
            style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.xs),
          ),
      ],
    );
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppTheme.fgDim),
            const SizedBox(width: 10),
          ],
          Expanded(child: labelBlock),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
    if (!enabled && disabledReason != null && disabledReason!.isNotEmpty) {
      row = Tooltip(message: disabledReason!, child: row);
    }
    return row;
  }
}

/// Two stacked password fields with live mismatch validation. Used
/// by the T1+password and Paranoid input panes; the secondary field
/// surfaces a `passwordsDoNotMatch` error as soon as the user types
/// a non-matching confirmation, and the parent State.[onChanged]
/// callback fires on every keystroke so the Apply button can update
/// its enabled state.
class _PasswordPair extends StatelessWidget {
  const _PasswordPair({
    required this.primary,
    required this.confirm,
    required this.primaryHint,
    required this.confirmHint,
    required this.onChanged,
  });

  final TextEditingController primary;
  final TextEditingController confirm;
  final String primaryHint;
  final String confirmHint;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecurePasswordField(
          controller: primary,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: primaryHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        SecurePasswordField(
          controller: confirm,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: confirmHint,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: confirm.text.isNotEmpty && confirm.text != primary.text
                ? S.of(context).passwordsDoNotMatch
                : null,
          ),
        ),
      ],
    );
  }
}
