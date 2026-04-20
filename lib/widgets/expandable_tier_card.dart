import 'package:flutter/material.dart';

import '../core/security/security_tier.dart';
import '../core/security/threat_vocabulary.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'secure_password_field.dart';
import 'security_threat_list.dart' show threatTitle;

/// Callback the Settings Security section supplies to each card.
/// Invoked when the user taps the card's `Select` button with a
/// valid modifier combo. The Settings side routes the request into
/// the existing `_applyTierChange` pipeline (always-rekey + marker
/// + provider flip).
typedef TierSelectCallback =
    Future<void> Function({
      required SecurityTier tier,
      required SecurityTierModifiers modifiers,
      String? shortPassword,
      String? pin,
      String? masterPassword,
    });

/// Expandable tier card — the Settings Security ladder unit.
///
/// Collapsed: badge + title + status (current / unavailable / plain).
/// Expanded: threat split + per-tier modifier toggles + input fields
/// (password / PIN / master password as the tier needs) + Select
/// button. Select routes straight to [onSelect] — there is no
/// intermediate wizard; the card itself is the wizard.
///
/// Current tier is rendered with an accent border and the Select
/// button is replaced with a "✓ Current" pill until the user toggles
/// a modifier that would change the applied config (flipping to a
/// different variant of the same tier, e.g. T1 → T1+password, still
/// re-enables Select so the user can apply the new modifiers).
///
/// Unavailable tier (T2 without TPM, T1 without keychain) stays
/// expandable so the user can read the threat split — the Select
/// button is disabled and the [unavailableReason] line surfaces
/// under the threat list.
class ExpandableTierCard extends StatefulWidget {
  const ExpandableTierCard({
    super.key,
    required this.tier,
    required this.currentTier,
    required this.currentModifiers,
    required this.tierAvailable,
    required this.onSelect,
    this.unavailableReason,
    this.initiallyExpanded = false,
  });

  final SecurityTier tier;
  final SecurityTier currentTier;
  final SecurityTierModifiers currentModifiers;

  /// Probe result: can this tier actually be picked on this host?
  /// T0 and Paranoid are always true; T1 depends on keychain probe;
  /// T2 depends on hardware probe.
  final bool tierAvailable;

  /// Non-null when [tierAvailable] is false. Shown under the threat
  /// list to explain why the Select button is disabled.
  final String? unavailableReason;

  /// Initial expand state. Settings pre-expands the current tier so
  /// the user sees its details without an extra tap.
  final bool initiallyExpanded;

  final TierSelectCallback onSelect;

  @override
  State<ExpandableTierCard> createState() => _ExpandableTierCardState();
}

class _ExpandableTierCardState extends State<ExpandableTierCard> {
  late bool _expanded;
  late bool _passwordEnabled;
  late bool _biometricEnabled;
  bool _busy = false;

  final _passwordCtrl = TextEditingController();
  final _passwordConfirmCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _masterPasswordCtrl = TextEditingController();
  final _masterPasswordConfirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _passwordEnabled = _derivePassword(
      widget.currentTier,
      widget.currentModifiers,
    );
    _biometricEnabled = widget.currentModifiers.biometric;
  }

  @override
  void dispose() {
    _passwordCtrl.wipeAndClear();
    _passwordConfirmCtrl.wipeAndClear();
    _pinCtrl.wipeAndClear();
    _masterPasswordCtrl.wipeAndClear();
    _masterPasswordConfirmCtrl.wipeAndClear();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    _pinCtrl.dispose();
    _masterPasswordCtrl.dispose();
    _masterPasswordConfirmCtrl.dispose();
    super.dispose();
  }

  bool _derivePassword(SecurityTier current, SecurityTierModifiers mods) {
    if (widget.tier != current &&
        !(widget.tier == SecurityTier.keychain &&
            current == SecurityTier.keychainWithPassword)) {
      // Non-current tier card: start with password off (T1/T2) or
      // on (Paranoid — always on by design). This is the pending
      // selection the user can tweak before tapping Select.
      return widget.tier == SecurityTier.paranoid;
    }
    return mods.password ||
        current == SecurityTier.keychainWithPassword ||
        current == SecurityTier.paranoid;
  }

  bool get _isCurrent {
    final t = widget.tier;
    final c = widget.currentTier;
    if (t == c) return true;
    // T1 card matches both `keychain` and `keychainWithPassword`.
    if (t == SecurityTier.keychain && c == SecurityTier.keychainWithPassword) {
      return true;
    }
    return false;
  }

  /// True when the current config exactly matches the card's pending
  /// state. Drives whether Select reads "Current" (disabled) or
  /// "Apply" (flippable) — a user on T1+password who toggles password
  /// off should see Select re-enable.
  bool get _matchesCurrentConfig {
    if (!_isCurrent) return false;
    final current = widget.currentTier;
    final mods = widget.currentModifiers;
    final currentHasPassword =
        mods.password ||
        current == SecurityTier.keychainWithPassword ||
        current == SecurityTier.paranoid;
    if (_passwordEnabled != currentHasPassword) return false;
    // Biometric is managed outside the tier-card's pending state
    // (see [_biometricToggleAvailable]), so it doesn't factor into
    // the "does the pending config match current?" check.
    return true;
  }

  bool get _passwordToggleAvailable =>
      widget.tier == SecurityTier.keychain ||
      widget.tier == SecurityTier.hardware;

  // Biometric stays out of the tier card because its setup flow is
  // more than a modifier flag — it runs a BiometricPrompt, stashes
  // the DB key into the biometric-gated vault, and can fail in ways
  // the Select path can't easily surface. Biometric lives in its
  // own Settings row below the ladder, same as before.
  bool get _biometricToggleAvailable => false;

  bool get _requiresPasswordInput =>
      !_matchesCurrentConfig &&
      widget.tier == SecurityTier.keychain &&
      _passwordEnabled;

  bool get _requiresPinInput =>
      !_matchesCurrentConfig && widget.tier == SecurityTier.hardware;

  bool get _requiresMasterPasswordInput =>
      !_matchesCurrentConfig && widget.tier == SecurityTier.paranoid;

  bool get _inputsReady {
    if (_requiresPasswordInput) {
      if (_passwordCtrl.text.isEmpty) return false;
      if (_passwordCtrl.text != _passwordConfirmCtrl.text) return false;
    }
    if (_requiresPinInput) {
      if (_pinCtrl.text.isEmpty) return false;
    }
    if (_requiresMasterPasswordInput) {
      if (_masterPasswordCtrl.text.isEmpty) return false;
      if (_masterPasswordCtrl.text != _masterPasswordConfirmCtrl.text) {
        return false;
      }
    }
    return true;
  }

  bool get _selectEnabled {
    if (_busy) return false;
    if (!widget.tierAvailable) return false;
    if (_matchesCurrentConfig) return false;
    return _inputsReady;
  }

  ThreatModel get _previewModel => ThreatModel(
    tier: _toThreatTier(widget.tier),
    password: _passwordEnabled || widget.tier == SecurityTier.paranoid,
    biometric: _biometricEnabled,
  );

  ThreatTier _toThreatTier(SecurityTier t) {
    switch (t) {
      case SecurityTier.plaintext:
        return ThreatTier.plaintext;
      case SecurityTier.keychain:
      case SecurityTier.keychainWithPassword:
        return ThreatTier.keychain;
      case SecurityTier.hardware:
        return ThreatTier.hardware;
      case SecurityTier.paranoid:
        return ThreatTier.paranoid;
    }
  }

  Future<void> _onSelect() async {
    if (!_selectEnabled) return;
    setState(() => _busy = true);
    try {
      SecurityTier target = widget.tier;
      if (target == SecurityTier.keychain && _passwordEnabled) {
        target = SecurityTier.keychainWithPassword;
      }
      final mods = SecurityTierModifiers(
        password: _passwordEnabled && widget.tier != SecurityTier.paranoid,
        biometric: _biometricEnabled,
      );
      await widget.onSelect(
        tier: target,
        modifiers: mods,
        shortPassword: _requiresPasswordInput ? _passwordCtrl.text : null,
        pin: _requiresPinInput ? _pinCtrl.text : null,
        masterPassword: _requiresMasterPasswordInput
            ? _masterPasswordCtrl.text
            : null,
      );
    } finally {
      if (mounted) {
        // Clear sensitive inputs once applied — the caller rebuilt
        // the widget tree with the new current-tier state, but the
        // local controllers retain what the user typed until dispose.
        _passwordCtrl.wipeAndClear();
        _passwordConfirmCtrl.wipeAndClear();
        _pinCtrl.wipeAndClear();
        _masterPasswordCtrl.wipeAndClear();
        _masterPasswordConfirmCtrl.wipeAndClear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final accent = _accentFor(widget.tier);
    final dim = !widget.tierAvailable && !_isCurrent;

    Widget body = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(
          color: _isCurrent ? accent : AppTheme.border,
          width: _isCurrent ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            badge: _badgeFor(widget.tier),
            title: _titleFor(widget.tier, l10n),
            subtitle: _subtitleFor(widget.tier, l10n),
            accent: accent,
            expanded: _expanded,
            trailing: _headerTrailing(l10n, accent),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SplitThreatListCompact(model: _previewModel, l10n: l10n),
                  if (!widget.tierAvailable &&
                      widget.unavailableReason != null) ...[
                    const SizedBox(height: 8),
                    _UnavailableReason(text: widget.unavailableReason!),
                  ],
                  if (_passwordToggleAvailable ||
                      _biometricToggleAvailable) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                  ],
                  if (_passwordToggleAvailable)
                    _ModifierRow(
                      label: l10n.modifierPasswordLabel,
                      value: _passwordEnabled,
                      enabled: widget.tierAvailable,
                      onChanged: (v) {
                        setState(() {
                          _passwordEnabled = v;
                          if (!v) _biometricEnabled = false;
                          _passwordCtrl.wipeAndClear();
                          _passwordConfirmCtrl.wipeAndClear();
                        });
                      },
                    ),
                  if (_biometricToggleAvailable)
                    _ModifierRow(
                      label: l10n.biometricUnlockTitle,
                      value: _biometricEnabled,
                      enabled: widget.tierAvailable,
                      onChanged: (v) => setState(() => _biometricEnabled = v),
                    ),
                  if (_requiresPasswordInput) ...[
                    const SizedBox(height: 8),
                    _PasswordPair(
                      primary: _passwordCtrl,
                      confirm: _passwordConfirmCtrl,
                      primaryHint: l10n.passwordLabel,
                      confirmHint: l10n.confirmPassword,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  if (_requiresPinInput) ...[
                    const SizedBox(height: 8),
                    _PinField(
                      controller: _pinCtrl,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  if (_requiresMasterPasswordInput) ...[
                    const SizedBox(height: 8),
                    _PasswordPair(
                      primary: _masterPasswordCtrl,
                      confirm: _masterPasswordConfirmCtrl,
                      primaryHint: l10n.masterPasswordLabel,
                      confirmHint: l10n.confirmPassword,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _selectEnabled ? _onSelect : null,
                      child: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_selectLabel(l10n)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (dim) body = Opacity(opacity: 0.55, child: body);
    return body;
  }

  Widget? _headerTrailing(S l10n, Color accent) {
    if (_matchesCurrentConfig) {
      return _CurrentBadge(label: l10n.tierBadgeCurrent, accent: accent);
    }
    return null;
  }

  String _selectLabel(S l10n) => l10n.securitySetupApply;

  String _badgeFor(SecurityTier tier) {
    switch (tier) {
      case SecurityTier.plaintext:
        return 'T0';
      case SecurityTier.keychain:
      case SecurityTier.keychainWithPassword:
        return 'T1';
      case SecurityTier.hardware:
        return 'T2';
      case SecurityTier.paranoid:
        return 'P';
    }
  }

  String _titleFor(SecurityTier tier, S l10n) {
    switch (tier) {
      case SecurityTier.plaintext:
        return l10n.tierPlaintextLabel;
      case SecurityTier.keychain:
      case SecurityTier.keychainWithPassword:
        return l10n.tierKeychainLabel;
      case SecurityTier.hardware:
        return l10n.tierHardwareLabel;
      case SecurityTier.paranoid:
        return l10n.tierParanoidLabel;
    }
  }

  String _subtitleFor(SecurityTier tier, S l10n) {
    switch (tier) {
      case SecurityTier.plaintext:
        return l10n.tierPlaintextSubtitle;
      case SecurityTier.keychain:
      case SecurityTier.keychainWithPassword:
        return l10n.tierKeychainSubtitle(_keychainName());
      case SecurityTier.hardware:
        return l10n.tierHardwareSubtitleHonest;
      case SecurityTier.paranoid:
        return l10n.tierParanoidSubtitleHonest;
    }
  }

  Color _accentFor(SecurityTier tier) {
    switch (tier) {
      case SecurityTier.plaintext:
        return AppTheme.red;
      case SecurityTier.paranoid:
        return AppTheme.purple;
      default:
        return AppTheme.accent;
    }
  }

  String _keychainName() {
    if (Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS) {
      return 'Keychain';
    }
    if (Theme.of(context).platform == TargetPlatform.windows) {
      return 'Credential Manager';
    }
    if (Theme.of(context).platform == TargetPlatform.android) {
      return 'Keystore';
    }
    return 'libsecret';
  }
}

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
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusSm,
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
    );
  }
}

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

class _SplitThreatListCompact extends StatelessWidget {
  const _SplitThreatListCompact({required this.model, required this.l10n});

  final ThreatModel model;
  final S l10n;

  @override
  Widget build(BuildContext context) {
    final statusMap = evaluate(model);
    final protects = <SecurityThreat>[];
    final doesNot = <SecurityThreat>[];
    for (final t in SecurityThreat.values) {
      final s = statusMap[t]!;
      if (s == ThreatStatus.protects) {
        protects.add(t);
      } else {
        doesNot.add(t);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in protects)
          _ThreatLine(threat: t, protects: true, l10n: l10n),
        if (protects.isNotEmpty && doesNot.isNotEmpty)
          Divider(height: 6, thickness: 1, color: AppTheme.border),
        for (final t in doesNot)
          _ThreatLine(threat: t, protects: false, l10n: l10n),
      ],
    );
  }
}

class _ThreatLine extends StatelessWidget {
  const _ThreatLine({
    required this.threat,
    required this.protects,
    required this.l10n,
  });

  final SecurityThreat threat;
  final bool protects;
  final S l10n;

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              threatTitle(threat, l10n),
              style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.xs),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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

class _ModifierRow extends StatelessWidget {
  const _ModifierRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.sm),
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

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

class _PinField extends StatelessWidget {
  const _PinField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SecurePasswordField(
      controller: controller,
      onChanged: (_) => onChanged(),
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'PIN',
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
