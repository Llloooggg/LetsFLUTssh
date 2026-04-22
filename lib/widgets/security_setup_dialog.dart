import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/security/hardware_tier_vault.dart';
import '../core/security/secure_key_storage.dart';
import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';
import '../providers/security_provider.dart'
    show
        hardwareProbeDetailText,
        keyringProbeDetailText,
        decodeHardwareProbeCode;
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'password_strength_meter.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';
import 'security_comparison_table.dart';
import 'toast.dart';

/// Result of the first-launch security setup wizard.
///
/// Carries both the legacy (tier + typed-secret-field) shape and the
/// new bank-style (tier + modifiers) shape. Downstream call sites
/// still read the legacy fields (`masterPassword`, `shortPassword`,
/// `pin`); the `modifiers` field is populated for code paths that
/// already consume the new shape (Phase F wiring).
class SecuritySetupResult {
  /// Tier picked by the user. `plaintext` is the fallback when the
  /// wizard never resolves (barrier-dismiss on desktop shutdown).
  final SecurityTier tier;

  /// Bank-style modifier flags — password + biometric.
  final SecurityTierModifiers modifiers;

  /// Master password chosen for Paranoid.
  final String? masterPassword;

  /// Bank-style password chosen for T1 + password.
  final String? shortPassword;

  /// Secret routed into the hardware-tier PIN slot. When the user
  /// picks T2 + password (bank-style shape), the typed password lands
  /// here — `HardwareTierVault.store` treats it as arbitrary bytes
  /// and HMAC-hashes it with the per-install salt, so a full password
  /// works identically to a 4-6 digit PIN.
  final String? pin;

  /// Whether the OS keychain is available.
  final bool keychainAvailable;

  const SecuritySetupResult({
    this.tier = SecurityTier.plaintext,
    this.modifiers = SecurityTierModifiers.defaults,
    this.masterPassword,
    this.shortPassword,
    this.pin,
    this.keychainAvailable = false,
  });
}

/// First-launch tier wizard.
///
/// 3-row numbered ladder (T0, T1, T2) + a separated "Paranoid
/// alternative" section below. Orthogonal password / biometric
/// modifiers expand inline under the selected row. A single
/// "Compare all tiers" link opens the [SecurityComparisonTable]
/// — the per-tier info popups from the v1 wizard are replaced by
/// this single matrix so the user reads one source of truth.
class SecuritySetupDialog extends StatefulWidget {
  final SecureKeyStorage keyStorage;
  final HardwareTierVault hardwareVault;
  final SecurityTier? currentTier;

  /// DI hook — when non-null the wizard skips the platform capability
  /// probe and renders against the injected caps. Production call
  /// sites never set this; tests supply a fixed [SecurityCapabilities]
  /// so `pumpAndSettle` does not time out on real D-Bus / biometric
  /// probes that never return inside a unit-test harness.
  final SecurityCapabilities? capabilitiesOverride;

  /// When true (the Settings "Change tier" entry point) the dialog
  /// honours Cancel / barrier-tap / Esc / back-gesture. When false
  /// (the first-launch fallback, shown when the keychain is
  /// unreachable) dismissal is blocked — the user must pick either
  /// T0 or Paranoid before the app can proceed past startup.
  final bool dismissible;

  const SecuritySetupDialog({
    super.key,
    required this.keyStorage,
    required this.hardwareVault,
    this.currentTier,
    this.capabilitiesOverride,
    this.dismissible = false,
  });

  static Future<SecuritySetupResult> show(
    BuildContext context, {
    required SecureKeyStorage keyStorage,
    HardwareTierVault? hardwareVault,
    SecurityTier? currentTier,
    SecurityCapabilities? capabilitiesOverride,
    bool dismissible = false,
  }) async {
    final result = await showDialog<SecuritySetupResult>(
      context: context,
      barrierDismissible: dismissible,
      builder: (_) => SecuritySetupDialog(
        keyStorage: keyStorage,
        hardwareVault: hardwareVault ?? HardwareTierVault(),
        currentTier: currentTier,
        capabilitiesOverride: capabilitiesOverride,
        dismissible: dismissible,
      ),
    );
    return result ?? const SecuritySetupResult();
  }

  @override
  State<SecuritySetupDialog> createState() => _SecuritySetupDialogState();
}

class _SecuritySetupDialogState extends State<SecuritySetupDialog> {
  SecurityCapabilities? _caps;
  WizardTier _selected = WizardTier.keychain;

  // Modifier toggles. Password is implied-on for Paranoid, but the
  // flag is tracked so the invariant `biometric → password` can be
  // enforced uniformly across every tier.
  bool _password = false;
  bool _biometric = false;

  final _secretCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _secretFocus = FocusNode();

  bool _plaintextAcknowledged = false;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _secretCtrl.wipeAndClear();
    _confirmCtrl.wipeAndClear();
    _secretCtrl.dispose();
    _confirmCtrl.dispose();
    _secretFocus.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final caps =
        widget.capabilitiesOverride ??
        await probeCapabilities(
          keyStorage: widget.keyStorage,
          hardwareVault: widget.hardwareVault,
        );
    if (!mounted) return;
    setState(() {
      _caps = caps;
      // Pre-select the current tier when settings opened this wizard
      // so the user sees where they are.
      _selected = _initialSelection(caps);
    });
  }

  /// Pick the tier to flag as "Recommended" in the wizard. Preference
  /// order mirrors the default-selection logic: hardware-bound when
  /// available (stronger off-device guarantees), else keychain, else
  /// plaintext. Paranoid is never auto-recommended — it is a
  /// conscious opt-in for users who distrust the OS.
  WizardTier? _recommendedTier(SecurityCapabilities caps) {
    if (caps.hardwareVaultAvailable) return WizardTier.hardware;
    if (caps.keychainAvailable) return WizardTier.keychain;
    return WizardTier.plaintext;
  }

  WizardTier _initialSelection(SecurityCapabilities caps) {
    switch (widget.currentTier) {
      case SecurityTier.plaintext:
        return WizardTier.plaintext;
      case SecurityTier.keychain:
      case SecurityTier.keychainWithPassword:
        _password = widget.currentTier == SecurityTier.keychainWithPassword;
        return WizardTier.keychain;
      case SecurityTier.hardware:
        _password = true;
        return WizardTier.hardware;
      case SecurityTier.paranoid:
        _password = true;
        return WizardTier.paranoid;
      case null:
        if (caps.hardwareVaultAvailable) return WizardTier.hardware;
        if (caps.keychainAvailable) return WizardTier.keychain;
        return WizardTier.plaintext;
    }
  }

  bool get _biometricToggleEnabled {
    final caps = _caps;
    if (caps == null) return false;
    if (!caps.canOfferBiometricModifier) return false;
    // Invariant: biometric requires password.
    if (!_password) return false;
    // Paranoid forbids biometric by design.
    if (_selected == WizardTier.paranoid) return false;
    // Plaintext has nothing to gate.
    if (_selected == WizardTier.plaintext) return false;
    return true;
  }

  bool get _passwordToggleEnabled {
    // Paranoid has a mandatory password; the toggle is not interactive.
    if (_selected == WizardTier.paranoid) return false;
    // Plaintext has no secret to add.
    if (_selected == WizardTier.plaintext) return false;
    // T1 / T2 — both allow the password modifier to be on or off.
    // Passwordless T2 seals the DB key under an empty auth value and
    // relies on SE / TPM isolation alone; the unlock path in
    // `_unlockHardware` reads the modifier back and skips the PIN
    // pad when the user opted out. The earlier force-on for T2 is
    // gone — the downstream code handles both branches now.
    return true;
  }

  bool _needsSecretInput() {
    // Paranoid always asks for a master password.
    if (_selected == WizardTier.paranoid) return true;
    // T1/T2 + password asks for the bank-style secret.
    if ((_selected == WizardTier.keychain ||
            _selected == WizardTier.hardware) &&
        _password) {
      return true;
    }
    return false;
  }

  /// Gate the Continue button up front so a disabled state is the
  /// visible cue instead of a toast on tap. Today the only hard-block
  /// is "Plaintext tier requires explicit acknowledgement" — the
  /// password / passphrase fields rely on _submit's post-tap error
  /// paths because their validation depends on both controllers
  /// being in sync, which is fiddlier to wire to button state.
  bool _canSubmit() {
    if (_selected == WizardTier.plaintext && !_plaintextAcknowledged) {
      return false;
    }
    return true;
  }

  void _submit() {
    final l10n = S.of(context);
    if (_selected == WizardTier.plaintext && !_plaintextAcknowledged) {
      Toast.show(context, message: l10n.plaintextAcknowledgeRequired);
      return;
    }
    if (_needsSecretInput()) {
      if (_secretCtrl.text.isEmpty) {
        _secretFocus.requestFocus();
        return;
      }
      if (_secretCtrl.text != _confirmCtrl.text) {
        Toast.show(context, message: l10n.passwordsDoNotMatch);
        return;
      }
    }

    // Enforce invariant before mapping.
    if (_biometric && !_password) _biometric = false;

    final mapped = mapWizardChoice(
      chosen: _selected,
      password: _password,
      biometric: _biometric,
      typedSecret: _needsSecretInput() ? _secretCtrl.text : null,
    );

    Navigator.of(context).pop(
      SecuritySetupResult(
        tier: mapped.tier,
        modifiers: mapped.modifiers,
        masterPassword: mapped.masterPassword,
        shortPassword: mapped.shortPassword,
        pin: mapped.pin,
        keychainAvailable: _caps?.keychainAvailable ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreenScope(
      child: PopScope(
        canPop: widget.dismissible,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _buildContent(S.of(context)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(S l10n) {
    final caps = _caps;
    if (caps == null) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16),
          CircularProgressIndicator(),
          SizedBox(height: 16),
        ],
      );
    }

    // Reduced-choice mode: neither T1 nor T2 is offerable on this
    // host, so the wizard collapses to T0 vs Paranoid. Hiding the
    // greyed rows (instead of showing them disabled) matches what
    // the user can actually pick and keeps the dialog short enough
    // that the real decision — "do I want a master password?" —
    // stands out. An info banner above the rows names the missing
    // dependency so the user knows it is not a hidden feature.
    final reduced = !caps.keychainAvailable && !caps.hardwareVaultAvailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shield, size: 40, color: AppTheme.accent),
        const SizedBox(height: 12),
        Text(
          l10n.securitySetupTitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.table_chart_outlined, size: 16),
            label: Text(l10n.compareAllTiers),
            onPressed: () => SecurityComparisonTable.show(context),
          ),
        ),
        const SizedBox(height: 18),
        if (reduced) ...[
          _ReducedWizardBanner(reason: l10n.wizardReducedBanner),
          const SizedBox(height: 14),
        ],

        _TierRow(
          badge: 'T0',
          label: l10n.tierPlaintextLabel,
          subtitle: l10n.tierPlaintextSubtitle,
          accent: AppTheme.red,
          selected: _selected == WizardTier.plaintext,
          current: widget.currentTier == SecurityTier.plaintext,
          onSelect: () => setState(() => _selected = WizardTier.plaintext),
        ),
        if (!reduced)
          _TierRow(
            badge: 'T1',
            label: l10n.tierKeychainLabel,
            subtitle: l10n.tierKeychainSubtitle(_keychainName),
            accent: AppTheme.accent,
            selected: _selected == WizardTier.keychain,
            current:
                widget.currentTier == SecurityTier.keychain ||
                widget.currentTier == SecurityTier.keychainWithPassword,
            recommended: _recommendedTier(caps) == WizardTier.keychain,
            // Prefer the classified probe reason over the generic
            // "tierKeychainUnavailable" copy so the user sees WHY
            // the row is greyed (no secret-service on Linux, ad-hoc
            // signing entitlement error on macOS, etc.). Fall back
            // to the generic string when the probe classifier
            // returns `available` yet some earlier gate still said
            // unavailable — defensive, should not happen in
            // practice.
            disabledReason: caps.keychainAvailable
                ? null
                : () {
                    final reason = keyringProbeDetailText(
                      l10n,
                      caps.keychainProbe,
                    );
                    return reason.isEmpty
                        ? l10n.tierKeychainUnavailable
                        : reason;
                  }(),
            onSelect: caps.keychainAvailable
                ? () => setState(() => _selected = WizardTier.keychain)
                : null,
          ),
        if (!reduced)
          _TierRow(
            badge: 'T2',
            label: l10n.tierHardwareLabel,
            subtitle: l10n.tierHardwareSubtitleHonest,
            accent: AppTheme.accent,
            selected: _selected == WizardTier.hardware,
            current: widget.currentTier == SecurityTier.hardware,
            recommended: _recommendedTier(caps) == WizardTier.hardware,
            // Same "prefer classified reason over generic copy"
            // pattern as the T1 row. The raw code comes from the
            // native `HardwareTierVault.probeDetail` channel or
            // from the Linux TPM CLI wrapper; `decodeHardwareProbeCode`
            // maps it to the `HardwareProbeDetail` enum and the
            // existing `hardwareProbeDetailText` helper supplies the
            // localised string. Unknown / missing codes fall through
            // to the generic "unavailable" copy.
            disabledReason: caps.hardwareVaultAvailable
                ? null
                : () {
                    final detail = decodeHardwareProbeCode(
                      caps.hardwareProbeCode,
                    );
                    final reason = hardwareProbeDetailText(l10n, detail);
                    return reason.isEmpty
                        ? l10n.tierHardwareUnavailable
                        : reason;
                  }(),
            onSelect: caps.hardwareVaultAvailable
                ? () => setState(() => _selected = WizardTier.hardware)
                : null,
          ),

        const SizedBox(height: 10),
        const _SectionDivider(),
        const SizedBox(height: 10),

        _TierRow(
          badge: 'P',
          label: l10n.tierParanoidLabel,
          subtitle: l10n.tierParanoidSubtitleHonest,
          accent: AppTheme.purple,
          selected: _selected == WizardTier.paranoid,
          current: widget.currentTier == SecurityTier.paranoid,
          onSelect: () => setState(() {
            _selected = WizardTier.paranoid;
            _password = true; // Paranoid is always password-gated.
            _biometric = false; // Forbidden by design.
          }),
        ),

        const SizedBox(height: 18),
        _buildModifierPanel(l10n, caps),

        const SizedBox(height: 18),
        Wrap(
          // spaceBetween keeps Cancel on the left and Apply on the right
          // on the edit path (two buttons present). On the first-launch
          // path Cancel is hidden (see note below), so the Wrap holds a
          // single child — end-align in that branch so the primary
          // action lands on the right instead of drifting to the left
          // edge (spaceBetween with one child collapses to start).
          alignment: widget.dismissible
              ? WrapAlignment.spaceBetween
              : WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            // Cancel is only meaningful on the edit path (Settings →
            // change tier). On first-launch the dialog is
            // non-dismissible (`PopScope(canPop: false)`), so a Cancel
            // button there is a dead control — hide it to avoid
            // confusing the user.
            if (widget.dismissible)
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.cancel),
              ),
            FilledButton(
              onPressed: _canSubmit() ? _submit : null,
              // "Apply" on the edit path (user is already set up and
              // just changing tier) vs "Enable" on the first-launch
              // path (keychain probe came back false → user picks
              // between T0 and Paranoid before startup can proceed).
              // "Continue with Recommended" was a lie when T0 or
              // another non-recommended tier was selected — replaced
              // unconditionally.
              child: Text(
                widget.currentTier == null
                    ? l10n.securitySetupEnable
                    : l10n.securitySetupApply,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModifierPanel(S l10n, SecurityCapabilities caps) {
    switch (_selected) {
      case WizardTier.plaintext:
        return _PlaintextAckPanel(
          acknowledged: _plaintextAcknowledged,
          onChanged: (v) => setState(() => _plaintextAcknowledged = v),
        );
      case WizardTier.keychain:
      case WizardTier.hardware:
        final linuxNote =
            caps.isLinuxHost && _selected == WizardTier.hardware && !_password;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModifierToggle(
              label: l10n.modifierPasswordLabel,
              subtitle: l10n.modifierPasswordSubtitle,
              icon: Icons.password,
              value: _password,
              enabled: _passwordToggleEnabled,
              onChanged: (v) => setState(() {
                _password = v;
                if (!v) _biometric = false;
                if (!v) {
                  _secretCtrl.wipeAndClear();
                  _confirmCtrl.wipeAndClear();
                }
              }),
            ),
            _ModifierToggle(
              label: l10n.modifierBiometricLabel,
              subtitle: l10n.modifierBiometricSubtitle,
              icon: Icons.fingerprint,
              value: _biometric,
              enabled: _biometricToggleEnabled,
              disabledReason: _biometric
                  ? null
                  : _biometricDisabledReason(l10n, caps),
              onChanged: (v) => setState(() => _biometric = v),
            ),
            if (linuxNote) ...[
              const SizedBox(height: 8),
              _HonestyNote(text: l10n.linuxTpmWithoutPasswordNote),
            ],
            if (_needsSecretInput()) _buildSecretForm(l10n),
          ],
        );
      case WizardTier.paranoid:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HonestyNote(text: l10n.paranoidMasterPasswordNote),
            _buildSecretForm(l10n, strengthMeter: true),
          ],
        );
    }
  }

  Widget _buildSecretForm(S l10n, {bool strengthMeter = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SecurePasswordField(
            controller: _secretCtrl,
            focusNode: _secretFocus,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _selected == WizardTier.paranoid
                  ? l10n.masterPasswordLabel
                  : l10n.passwordLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          if (strengthMeter) ...[
            const SizedBox(height: 6),
            PasswordStrengthMeter(controller: _secretCtrl),
          ],
          const SizedBox(height: 8),
          SecurePasswordField(
            controller: _confirmCtrl,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.confirmPassword,
              border: const OutlineInputBorder(),
              errorText:
                  _confirmCtrl.text.isNotEmpty &&
                      _confirmCtrl.text != _secretCtrl.text
                  ? l10n.passwordsDoNotMatch
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  String? _biometricDisabledReason(S l10n, SecurityCapabilities caps) {
    if (!_password) return l10n.biometricRequiresPassword;
    if (_selected == WizardTier.paranoid) {
      return l10n.biometricForbiddenParanoid;
    }
    if (_selected == WizardTier.plaintext) return null;
    if (caps.isLinuxHost && !caps.fprintdAvailable) {
      return l10n.fprintdNotAvailable;
    }
    if (!caps.biometricAvailable) {
      return l10n.biometricSensorNotAvailable;
    }
    return null;
  }

  String get _keychainName {
    if (Platform.isMacOS || Platform.isIOS) return 'Keychain';
    if (Platform.isWindows) return 'Credential Manager';
    if (Platform.isAndroid) return 'EncryptedSharedPreferences';
    return 'libsecret';
  }
}

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
