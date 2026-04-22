import 'package:flutter/material.dart';

import '../core/security/security_tier.dart';
import '../core/security/threat_vocabulary.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_button.dart';
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
    this.activeTierExtras,
    this.biometricSpec,
    this.autoLockRow,
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

  /// Rows rendered inside the expandable section, under the Apply
  /// button and a separator, on the card whose tier matches the
  /// currently-applied security state. Intended for orthogonal
  /// "active-tier settings" — biometric unlock, auto-lock — that
  /// take effect immediately on toggle rather than being queued
  /// for the Apply button. Null on non-current cards, and also on
  /// the current card when none of the orthogonal toggles are
  /// meaningful (e.g. T0, which has no user secret to lock).
  final Widget? activeTierExtras;

  /// Optional auto-lock row rendered inside the modifier section
  /// after the biometric toggle. Parent passes a pre-built
  /// `_AutoLockTile` (or null to hide) so the same `disabledReason`
  /// priority ladder biometric uses (platform / tier-availability /
  /// current-tier / password-required) applies to auto-lock with
  /// per-tier tooltip copy owned by the parent.
  final Widget? autoLockRow;

  /// When non-null, a biometric modifier row renders after the
  /// password toggle. Callers pass their resolved state:
  ///
  ///   * `enabled` — true when the toggle can actually flip
  ///     (current tier, password modifier active, biometric
  ///     available on the platform).
  ///   * `value` — current biometric-unlock state from the
  ///     Settings section's own probe; read-only display when
  ///     the row is disabled.
  ///   * `disabledReason` — tooltip message shown on hover when
  ///     the toggle is disabled (platform unsupported, password
  ///     required, tier not current, etc.). Pass null when the
  ///     row is enabled.
  ///   * `onChanged` — fires the actual BiometricPrompt + vault
  ///     stash flow owned by the Settings section. Invoked only
  ///     when the toggle is enabled.
  ///
  /// A null `biometricSpec` hides the row — used on T0 (nothing
  /// to gate) and Paranoid (design rule: biometric undermines the
  /// "no OS trust" premise of the tier).
  final BiometricModifierSpec? biometricSpec;

  @override
  State<ExpandableTierCard> createState() => _ExpandableTierCardState();
}

/// Config for the tier-card biometric toggle. Decoupled from the
/// card so the Settings section can compute enabled / tooltip copy
/// from its own state (probe results, current tier, modifier flags)
/// and pass the result in without the card re-implementing the
/// rule set.
class BiometricModifierSpec {
  const BiometricModifierSpec({
    required this.enabled,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? disabledReason;
}

class _ExpandableTierCardState extends State<ExpandableTierCard> {
  late bool _expanded;
  late bool _passwordEnabled;
  bool _busy = false;

  final _passwordCtrl = TextEditingController();
  final _passwordConfirmCtrl = TextEditingController();
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
  }

  @override
  void dispose() {
    _passwordCtrl.wipeAndClear();
    _passwordConfirmCtrl.wipeAndClear();
    _masterPasswordCtrl.wipeAndClear();
    _masterPasswordConfirmCtrl.wipeAndClear();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
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
    // Biometric flips through the Settings BiometricPrompt +
    // vault-stash path directly (via [ExpandableTierCard.biometricSpec]),
    // not through this card's pending Apply state — so the
    // "does pending match current?" check ignores biometric.
    return true;
  }

  bool get _passwordToggleAvailable =>
      widget.tier == SecurityTier.keychain ||
      widget.tier == SecurityTier.hardware;

  /// T1 and T2 use the same short-password input path when the
  /// password modifier toggle is on. T2 historically had a
  /// separate "PIN" field; it was renamed to "password" in the UI
  /// so users do not have to learn two terms for the same thing.
  /// The underlying semantics (T1: brute-force resistance from a
  /// long password; T2: brute-force resistance from the hardware
  /// lockout on a short password) are surfaced as a hint under
  /// the field, not as a different field name.
  bool get _requiresPasswordInput =>
      !_matchesCurrentConfig &&
      (widget.tier == SecurityTier.keychain ||
          widget.tier == SecurityTier.hardware) &&
      _passwordEnabled;

  bool get _requiresMasterPasswordInput =>
      !_matchesCurrentConfig && widget.tier == SecurityTier.paranoid;

  bool get _inputsReady {
    if (_requiresPasswordInput) {
      if (_passwordCtrl.text.isEmpty) return false;
      if (_passwordCtrl.text != _passwordConfirmCtrl.text) return false;
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
    biometric: widget.currentModifiers.biometric,
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
        biometric: widget.currentModifiers.biometric,
      );
      // T1 uses `shortPassword` against the keychain-password gate;
      // T2 uses the same value as the PIN HMAC input to the hw
      // vault. Same UX field, different backend consumer — the
      // tier switcher routes it. Paranoid uses `masterPassword`.
      final shortPw =
          _requiresPasswordInput && widget.tier == SecurityTier.keychain
          ? _passwordCtrl.text
          : null;
      final pin = _requiresPasswordInput && widget.tier == SecurityTier.hardware
          ? _passwordCtrl.text
          : null;
      await widget.onSelect(
        tier: target,
        modifiers: mods,
        shortPassword: shortPw,
        pin: pin,
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

    // `clipBehavior: Clip.antiAlias` on the container stops the
    // header `InkWell` hover / splash from painting over the
    // rounded border when the pointer enters from outside the
    // card's clip shape — the hover halo otherwise bleeds onto
    // the top strip. Safe with decoration + borderRadius; Flutter
    // uses the decoration's border radius as the clip path.
    Widget body = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
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
          if (_expanded) _buildExpandedBody(l10n),
        ],
      ),
    );

    // 0.5 matches the `_AutoLockTile` and `_Toggle` disabled
    // dimming — keeping every Settings-section disabled state on the
    // same alpha so the user does not read "password" as a different
    // severity of disabled than "auto-lock".
    if (dim) body = Opacity(opacity: 0.5, child: body);
    return body;
  }

  /// Expanded-card body. Extracted from [build] so the method stays
  /// under the S3776 cognitive-complexity threshold — the card's
  /// expanded state renders threat preview, unavailable-reason hint,
  /// modifier rows, optional secret input pair(s), Apply button and
  /// active-tier extras, each guarded by an `if`. Flattening them
  /// inside `build` pushed the method past the limit.
  Widget _buildExpandedBody(S l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ThreatListFixed(model: _previewModel, l10n: l10n),
          if (!widget.tierAvailable && widget.unavailableReason != null) ...[
            const SizedBox(height: 8),
            _UnavailableReason(text: widget.unavailableReason!),
          ],
          if (_hasModifierSection) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
          ],
          if (_passwordToggleAvailable) _buildPasswordToggleRow(l10n),
          if (widget.biometricSpec != null) _buildBiometricRow(l10n),
          if (widget.autoLockRow != null) widget.autoLockRow!,
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
            child: AppButton.primary(
              label: _selectLabel(l10n),
              loading: _busy,
              onTap: _selectEnabled ? _onSelect : null,
            ),
          ),
          // Active-tier orthogonal settings (biometric unlock,
          // auto-lock). Rendered under a divider so the user
          // reads them as "settings of the current tier" and
          // not as pending changes gated by Apply. Only the
          // current tier card passes a non-null widget here.
          if (widget.activeTierExtras != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 4),
            widget.activeTierExtras!,
          ],
        ],
      ),
    );
  }

  bool get _hasModifierSection =>
      _passwordToggleAvailable ||
      widget.biometricSpec != null ||
      widget.autoLockRow != null;

  Widget _buildPasswordToggleRow(S l10n) => _ModifierRow(
    label: l10n.modifierPasswordLabel,
    subtitle: l10n.modifierPasswordSubtitle,
    icon: Icons.password,
    value: _passwordEnabled,
    enabled: widget.tierAvailable,
    onChanged: (v) {
      setState(() {
        _passwordEnabled = v;
        _passwordCtrl.wipeAndClear();
        _passwordConfirmCtrl.wipeAndClear();
      });
    },
  );

  Widget _buildBiometricRow(S l10n) => _ModifierRow(
    label: l10n.biometricUnlockTitle,
    subtitle: l10n.biometricUnlockSubtitle,
    icon: Icons.fingerprint,
    value: widget.biometricSpec!.value,
    enabled: widget.biometricSpec!.enabled,
    onChanged: widget.biometricSpec!.onChanged,
    disabledReason: widget.biometricSpec!.disabledReason,
  );

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
