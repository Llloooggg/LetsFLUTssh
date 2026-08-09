import 'package:flutter/material.dart';

import '../../core/security/security_tier.dart';
import '../../core/security/threat_vocabulary.dart';
import 'expandable_tier_card_logic.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/secret_controller.dart';
import '../core/app_button.dart';
import 'secure_password_field.dart';
import 'security_threat_list.dart' show threatTitle;

// Part files keep the private helper widgets next to the main card
// without polluting the public widgets/ namespace. Library-private
// underscore classes stay reachable from `_ExpandableTierCardState`
// because `part of` joins them into the same library.
part 'expandable_tier_card_header.dart';
part 'expandable_tier_card_inputs.dart';
part 'expandable_tier_card_threats.dart';

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
      String? hardwarePassword,
      String? masterPassword,
      bool? pendingBiometric,
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

  /// Pending biometric-modifier state. Starts at whatever the parent
  /// spec reports as the current applied value; the toggle mutates
  /// this flag only — the actual enable / disable work (platform
  /// biometric prompt + vault stash) is deferred until the user taps
  /// Apply, which batches the password prompt with the tier change.
  /// Trap: prompting on every toggle flip surprises users who flip
  /// the toggle twice before Applying.
  late bool _pendingBiometric;
  late bool _initialBiometric;

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
    final initial = widget.biometricSpec?.value ?? false;
    _pendingBiometric = initial;
    _initialBiometric = initial;
  }

  @override
  void didUpdateWidget(ExpandableTierCard old) {
    super.didUpdateWidget(old);
    // Re-seat every pending-vs-applied field when the parent pushes
    // a new applied-state snapshot down (tier switch completed,
    // settings reset, biometric toggled externally). Without these
    // resets the card keeps the PRE-apply pending values and the
    // Apply button stays enabled even though the tier + modifiers
    // now match the fresh applied state.
    if (old.currentTier != widget.currentTier ||
        old.currentModifiers != widget.currentModifiers) {
      _passwordEnabled = _derivePassword(
        widget.currentTier,
        widget.currentModifiers,
      );
      // Typed secrets from the prior provisioning flow are also
      // stale — the user's last Apply consumed them. Wipe so the
      // input fields render empty on the next expand.
      _passwordCtrl.wipeAndClear();
      _passwordConfirmCtrl.wipeAndClear();
      _masterPasswordCtrl.wipeAndClear();
      _masterPasswordConfirmCtrl.wipeAndClear();
    }
    final next = widget.biometricSpec?.value ?? false;
    if (next != _initialBiometric) {
      _initialBiometric = next;
      _pendingBiometric = next;
    }
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

  bool _derivePassword(SecurityTier current, SecurityTierModifiers mods) =>
      derivePasswordModifierForCard(
        cardTier: widget.tier,
        currentTier: current,
        currentModifiers: mods,
      );

  bool get _isCurrent =>
      tierCardIsCurrent(cardTier: widget.tier, currentTier: widget.currentTier);

  /// True when the current config exactly matches the card's pending
  /// state. Drives whether Select reads "Current" (disabled) or
  /// "Apply" (flippable) — a user on T1+password who toggles password
  /// off should see Select re-enable.
  bool get _matchesCurrentConfig {
    if (!_isCurrent) return false;
    if (_passwordEnabled != _currentHasPassword) return false;
    // Pending biometric: the card owns the toggle state and batches
    // the enable / disable work into the Apply step. A toggle that
    // diverges from the applied value must re-enable Apply so the
    // user can commit the change with a single password prompt.
    if (_pendingBiometric != _initialBiometric) return false;
    return true;
  }

  bool get _passwordToggleAvailable =>
      tierCardPasswordToggleAvailable(widget.tier);

  /// T1 and T2 use the same short-password input path when the
  /// password modifier toggle is on. T2 historically had a
  /// separate "PIN" field; it was renamed to "password" in the UI
  /// so users do not have to learn two terms for the same thing.
  /// The underlying semantics (T1: brute-force resistance from a
  /// long password; T2: brute-force resistance from the hardware
  /// lockout on a short password) are surfaced as a hint under
  /// the field, not as a different field name.
  ///
  /// Suppressed when the user is already on this tier *with the
  /// password modifier on* — the only remaining divergence in that
  /// state is the biometric flag, and the post-Apply biometric step
  /// prompts for the live password through its own dialog. Asking
  /// the user to re-type the password twice (card fields + dialog)
  /// was the user-report bug that "two password fields are showing
  /// on my own tier".
  bool get _requiresPasswordInput => requiresShortPasswordInput(
    cardTier: widget.tier,
    passwordModifierEnabled: _passwordEnabled,
    isCurrent: _isCurrent,
    currentHasPassword: _currentHasPassword,
  );

  /// Same reasoning as [_requiresPasswordInput]: on Paranoid a
  /// biometric-only toggle does not change the master password, and
  /// the post-Apply biometric step re-prompts via the shared dialog,
  /// so rendering the master-password pair on the current card is
  /// redundant UI.
  bool get _requiresMasterPasswordInput =>
      requiresMasterPasswordInput(cardTier: widget.tier, isCurrent: _isCurrent);

  /// Whether the currently-applied tier + modifiers already carry a
  /// user-typed password. Paranoid is always true; T1+password is
  /// true; T2 with `password` modifier is true. Derived from the
  /// applied state the parent pushed down, not the pending card
  /// state, because this predicate exists to tell the render code
  /// whether we need a fresh password from the user.
  bool get _currentHasPassword => currentConfigHasPassword(
    currentTier: widget.currentTier,
    currentModifiers: widget.currentModifiers,
  );

  bool get _inputsReady {
    if (_requiresPasswordInput) {
      if (_passwordCtrl.text.isEmpty) return false;
      if (_passwordCtrl.text != _passwordConfirmCtrl.text) return false;
    }
    if (_requiresMasterPasswordInput) {
      if (_masterPasswordCtrl.text.isEmpty) return false;
      if (_masterPasswordCtrl.text != _masterPasswordConfirmCtrl.text) return false;
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
        return ThreatTier.keychain;
      case SecurityTier.hardware:
        return ThreatTier.hardware;
      case SecurityTier.paranoid:
        return ThreatTier.paranoid;
    }
  }

  /// Normalize the card's tier to the target tier the apply pipeline
  /// expects. Bank-style: the UI treats T1 as a single tier card
  /// and the password signal lives on `result.modifiers.password`,
  /// which `_applyTierChange` reads to decide whether to drive the
  /// gate-bearing flow. The tier itself stays `keychain` regardless
  /// of the password modifier value.
  SecurityTier _resolveTargetTier() => widget.tier;

  SecurityTierModifiers _resolveModifiers() {
    // Paranoid and Hardware both carry a mandatory password by
    // tier — `_passwordEnabled` is locked on for those cards but
    // the resolved modifier still has to be coherent in case the
    // toggle row was bypassed (e.g. the password row is hidden on
    // these cards, so the local pending flag is irrelevant).
    final passwordRequired =
        widget.tier == SecurityTier.paranoid ||
        widget.tier == SecurityTier.hardware;
    return SecurityTierModifiers(
      password: passwordRequired || _passwordEnabled,
      biometric: widget.currentModifiers.biometric,
    );
  }

  String? _shortPasswordPayload() {
    if (!_requiresPasswordInput) return null;
    if (widget.tier != SecurityTier.keychain) return null;
    return _passwordCtrl.text;
  }

  String? _hardwarePasswordPayload() {
    if (!_requiresPasswordInput) return null;
    if (widget.tier != SecurityTier.hardware) return null;
    return _passwordCtrl.text;
  }

  /// `null` means "no change to biometric"; otherwise the pending
  /// value the user has toggled to. Only the post-apply biometric
  /// step cares about the true/false; a diverged pending drives the
  /// batched password prompt in `onSelectTier`.
  bool? _pendingBiometricDiff() {
    if (widget.biometricSpec == null) return null;
    if (_pendingBiometric == _initialBiometric) return null;
    return _pendingBiometric;
  }

  Future<void> _onSelect() async {
    if (!_selectEnabled) return;
    setState(() => _busy = true);
    try {
      // T1 uses `shortPassword` against the keychain-password gate;
      // T2 uses `hardwarePassword` — the typed gate fed to the
      // hw-vault HMAC. Same UX field, different backend consumer
      // — the tier switcher routes it. Paranoid uses
      // `masterPassword`.
      await widget.onSelect(
        tier: _resolveTargetTier(),
        modifiers: _resolveModifiers(),
        shortPassword: _shortPasswordPayload(),
        hardwarePassword: _hardwarePasswordPayload(),
        masterPassword: _requiresMasterPasswordInput
            ? _masterPasswordCtrl.text
            : null,
        pendingBiometric: _pendingBiometricDiff(),
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
        // Post-frame sync: after the parent's Apply pipeline has
        // flushed its `setState` + our build runs, re-read the
        // applied spec value and snap both `_initial` and
        // `_pending` to it. `didUpdateWidget` already does this
        // when `spec.value` transitions, but it only fires on
        // change — if the value never changed (apply cancelled /
        // failed / no-op) but local `_pending` diverged from it,
        // Apply would stay enabled. This guard snaps on every
        // apply exit, success OR abort, so the card always lands
        // back on the applied state when the flow unwinds.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final applied = widget.biometricSpec?.value ?? false;
          if (applied == _initialBiometric && applied == _pendingBiometric) {
            return;
          }
          setState(() {
            _initialBiometric = applied;
            _pendingBiometric = applied;
          });
        });
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
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ThreatListFixed(model: _previewModel, l10n: l10n),
          if (!widget.tierAvailable && widget.unavailableReason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _UnavailableReason(text: widget.unavailableReason!),
          ],
          if (_hasModifierSection) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_passwordToggleAvailable) _buildPasswordToggleRow(l10n),
          if (widget.biometricSpec != null) _buildBiometricRow(l10n),
          if (widget.autoLockRow != null) widget.autoLockRow!,
          if (_requiresPasswordInput) ...[
            const SizedBox(height: AppSpacing.sm),
            _PasswordPair(
              primary: _passwordCtrl,
              confirm: _passwordConfirmCtrl,
              primaryHint: l10n.passwordLabel,
              confirmHint: l10n.confirmPassword,
              onChanged: () => setState(() {}),
            ),
          ],
          if (_requiresMasterPasswordInput) ...[
            const SizedBox(height: AppSpacing.sm),
            _PasswordPair(
              primary: _masterPasswordCtrl,
              confirm: _masterPasswordConfirmCtrl,
              primaryHint: l10n.masterPasswordLabel,
              confirmHint: l10n.confirmPassword,
              onChanged: () => setState(() {}),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: AppSpacing.xs),
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
    // Show the *pending* value so rapid-fire toggles read correctly
    // (on → off → on leaves the user back at the applied state with
    // the Apply button disabled because `_matchesCurrentConfig`
    // equates pending == applied, not "any interaction happened").
    value: _pendingBiometric,
    enabled: widget.biometricSpec!.enabled,
    // Mutate local pending state only — the actual enable / disable
    // runs from `onSelectTier` after a single batched password
    // prompt.
    onChanged: (v) => setState(() => _pendingBiometric = v),
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
