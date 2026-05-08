import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';
import '../providers/security_provider.dart'
    show
        hardwareProbeDetailText,
        keyringProbeDetailText,
        decodeHardwareProbeCode;
import '../src/rust/api/app.dart' as rust_app;
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_button.dart';
import 'password_strength_meter.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';
import 'security_comparison_table.dart';
import 'security_setup_dialog_logic.dart';
import 'toast.dart';

// Six private helper widgets (_TierRow / _ModifierToggle /
// _SectionDivider / _ReducedWizardBanner / _PlaintextAckPanel /
// _HonestyNote) live in a part-of sibling so the State + the
// 511-LOC build chain stay focused. Same pattern as
// expandable_tier_card_widgets.
part 'security_setup_dialog_widgets.dart';

/// Result of the first-launch security setup wizard.
///
/// Carries both the legacy (tier + typed-secret-field) shape and the
/// new bank-style (tier + modifiers) shape. The typed secret bytes
/// land in the Rust-side SecretStore under transient ids; only the
/// ids cross `Navigator.pop`. Callers take (atomic read-and-remove)
/// the bytes via [SecuritySetupResult.takeMasterPassword] etc.
/// inside the same dispatch tick they use them, so the Dart-heap
/// residency window is bounded to a single function call rather
/// than the wizard's awaiter frame lifetime.
class SecuritySetupResult {
  /// Tier picked by the user. `plaintext` is the fallback when the
  /// wizard never resolves (barrier-dismiss on desktop shutdown).
  final SecurityTier tier;

  /// Bank-style modifier flags — password + biometric.
  final SecurityTierModifiers modifiers;

  /// SecretStore id of the master password chosen for Paranoid.
  /// `null` when the chosen tier is not Paranoid.
  final String? masterPasswordSecretId;

  /// SecretStore id of the bank-style password chosen for T1+password.
  /// `null` when the chosen tier is not T1+pw.
  final String? shortPasswordSecretId;

  /// SecretStore id of the secret routed into the hardware-tier PIN
  /// slot when the user picks T2+password (bank-style). `null` for
  /// the passwordless variant. `HardwareTierVault.store` treats the
  /// bytes as arbitrary input and HMAC-hashes them with the per-
  /// install salt, so a full password works identically to a 4-6
  /// digit PIN.
  final String? pinSecretId;

  /// Whether the OS keychain is available.
  final bool keychainAvailable;

  const SecuritySetupResult({
    this.tier = SecurityTier.plaintext,
    this.modifiers = SecurityTierModifiers.defaults,
    this.masterPasswordSecretId,
    this.shortPasswordSecretId,
    this.pinSecretId,
    this.keychainAvailable = false,
  });

  /// Stage `value` (UTF-8) under a fresh `wizard.<uuid>` SecretStore
  /// id and return the id. Lets call sites that build a
  /// [SecuritySetupResult] from already-typed plaintext (the inline
  /// Settings → Apply path's `onSelectTier`) reuse the same
  /// SecretStore-backed transit shape the wizard pop-result uses,
  /// so `take*` accessors work uniformly across both.
  ///
  /// Returns `null` when the value is null / empty.
  static String? stageSecret(String? value) {
    if (value == null || value.isEmpty) return null;
    final id = 'wizard.${const Uuid().v4()}';
    rust_app.secretsPut(id: id, bytes: utf8.encode(value));
    return id;
  }

  /// Take (atomic read-and-remove) the staged master-password
  /// bytes out of the SecretStore and return them as a UTF-8
  /// String. Returns `null` when the wizard didn't capture a
  /// master password (every tier other than Paranoid).
  ///
  /// Single-shot: a second call returns `null` because the
  /// SecretStore entry is gone. Callers should consume the
  /// returned String immediately and let it drop.
  String? takeMasterPassword() => _takeBytesAsString(masterPasswordSecretId);

  /// Same shape as [takeMasterPassword] but for the T1+pw + password
  /// short-password slot.
  String? takeShortPassword() => _takeBytesAsString(shortPasswordSecretId);

  /// Same shape as [takeMasterPassword] but for the T2 + password
  /// PIN slot.
  String? takePin() => _takeBytesAsString(pinSecretId);

  static String? _takeBytesAsString(String? id) {
    if (id == null) return null;
    final bytes = rust_app.secretsTake(id: id);
    // `secretsTake` returns `null` for a missing slot; the previous
    // `bytes.isEmpty` check collapsed missing-id and empty-bytes
    // (a legitimate empty-password setup intent) into the same
    // null. The wire shape is now `Option<Vec<u8>>` so the
    // distinction round-trips intact.
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }
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
  final SecurityTier? currentTier;

  /// Bank-style v3 modifiers for [currentTier]. Carried alongside
  /// the tier so the wizard can pre-fill the password toggle when
  /// the user re-opens it from Settings (previously the T1+password
  /// case was inferred from the dedicated `keychainWithPassword`
  /// tier value alone). `null` matches `currentTier == null` —
  /// first-launch entry, no existing config to honour.
  final SecurityTierModifiers? currentModifiers;

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
    this.currentTier,
    this.currentModifiers,
    this.capabilitiesOverride,
    this.dismissible = false,
  });

  static Future<SecuritySetupResult> show(
    BuildContext context, {
    SecurityTier? currentTier,
    SecurityTierModifiers? currentModifiers,
    SecurityCapabilities? capabilitiesOverride,
    bool dismissible = false,
  }) async {
    final result = await showDialog<SecuritySetupResult>(
      context: context,
      barrierDismissible: dismissible,
      builder: (_) => SecuritySetupDialog(
        currentTier: currentTier,
        currentModifiers: currentModifiers,
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
    final caps = widget.capabilitiesOverride ?? await probeCapabilities();
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
        // Bank-style v3: T1+password is `keychain` + the password
        // modifier; the wizard pre-fills the toggle from
        // `currentModifiers.password` instead of the prior dedicated
        // `keychainWithPassword` tier check.
        _password = widget.currentModifiers?.password ?? false;
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
    return wizardBiometricToggleEnabled(
      selected: _selected,
      password: _password,
      canOfferBiometric: caps.canOfferBiometricModifier,
    );
  }

  bool get _passwordToggleEnabled => wizardPasswordToggleEnabled(_selected);

  bool _needsSecretInput() =>
      wizardNeedsSecretInput(selected: _selected, password: _password);

  /// Gate the Continue button up front so a disabled state is the
  /// visible cue instead of a toast on tap. Today the only hard-block
  /// is "Plaintext tier requires explicit acknowledgement" — the
  /// password / passphrase fields rely on _submit's post-tap error
  /// paths because their validation depends on both controllers
  /// being in sync, which is fiddlier to wire to button state.
  bool _canSubmit() => wizardCanSubmit(
    selected: _selected,
    plaintextAcknowledged: _plaintextAcknowledged,
  );

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
    _biometric = resolveBiometricInvariant(
      password: _password,
      biometric: _biometric,
    );

    final mapped = mapWizardChoice(
      chosen: _selected,
      password: _password,
      biometric: _biometric,
      typedSecret: _needsSecretInput() ? _secretCtrl.text : null,
    );

    // Stage every typed secret in the Rust-side SecretStore under a
    // fresh transient id. Only the ids cross Navigator.pop; the
    // plaintext String stays in the dialog's State which the
    // dispose-time wipeAndClear has already drained. The awaiter
    // takes (atomic read-and-remove) the bytes immediately before
    // use so the Dart-heap residency window collapses to one call.
    final result = SecuritySetupResult(
      tier: mapped.tier,
      modifiers: mapped.modifiers,
      masterPasswordSecretId: SecuritySetupResult.stageSecret(
        mapped.masterPassword,
      ),
      shortPasswordSecretId: SecuritySetupResult.stageSecret(
        mapped.shortPassword,
      ),
      pinSecretId: SecuritySetupResult.stageSecret(mapped.pin),
      keychainAvailable: _caps?.keychainAvailable ?? false,
    );
    Navigator.of(context).pop(result);
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
          child: AppButton(
            label: l10n.compareAllTiers,
            icon: Icons.table_chart_outlined,
            onTap: () => SecurityComparisonTable.show(context),
            dense: true,
          ),
        ),
        const SizedBox(height: 18),
        if (reduced) ...[
          _ReducedWizardBanner(reason: l10n.wizardReducedBanner),
          const SizedBox(height: 14),
        ],

        _buildPlaintextRow(l10n),
        if (!reduced) _buildKeychainRow(l10n, caps),
        if (!reduced) _buildHardwareRow(l10n, caps),

        const SizedBox(height: 10),
        const _SectionDivider(),
        const SizedBox(height: 10),

        _buildParanoidRow(l10n),

        const SizedBox(height: 18),
        _buildModifierPanel(l10n, caps),

        const SizedBox(height: 18),
        _buildFooterActions(l10n),
      ],
    );
  }

  Widget _buildPlaintextRow(S l10n) => _TierRow(
    badge: 'T0',
    label: l10n.tierPlaintextLabel,
    subtitle: l10n.tierPlaintextSubtitle,
    accent: AppTheme.red,
    selected: _selected == WizardTier.plaintext,
    current: widget.currentTier == SecurityTier.plaintext,
    onSelect: () => setState(() => _selected = WizardTier.plaintext),
  );

  Widget _buildKeychainRow(S l10n, SecurityCapabilities caps) => _TierRow(
    badge: 'T1',
    label: l10n.tierKeychainLabel,
    subtitle: l10n.tierKeychainSubtitle(_keychainName),
    accent: AppTheme.accent,
    selected: _selected == WizardTier.keychain,
    // Bank-style v3: T1+password is `keychain` + modifier; the
    // pre-v3 dedicated `keychainWithPassword` enum check went away.
    current: widget.currentTier == SecurityTier.keychain,
    recommended: _recommendedTier(caps) == WizardTier.keychain,
    // Prefer the classified probe reason over the generic
    // "tierKeychainUnavailable" copy so the user sees WHY
    // the row is greyed (no secret-service on Linux, ad-hoc
    // signing entitlement error on macOS, etc.). Fall back
    // to the generic string when the probe classifier returns
    // `available` yet some earlier gate still said unavailable
    // — defensive, should not happen in practice.
    disabledReason: caps.keychainAvailable
        ? null
        : _keychainDisabledReason(l10n, caps),
    onSelect: caps.keychainAvailable
        ? () => setState(() => _selected = WizardTier.keychain)
        : null,
  );

  Widget _buildHardwareRow(S l10n, SecurityCapabilities caps) => _TierRow(
    badge: 'T2',
    label: l10n.tierHardwareLabel,
    subtitle: l10n.tierHardwareSubtitleHonest,
    accent: AppTheme.accent,
    selected: _selected == WizardTier.hardware,
    current: widget.currentTier == SecurityTier.hardware,
    recommended: _recommendedTier(caps) == WizardTier.hardware,
    // Same "prefer classified reason over generic copy" pattern
    // as the T1 row. The raw code comes from the native
    // `HardwareTierVault.probeDetail` channel or from the Linux
    // TPM CLI wrapper; `decodeHardwareProbeCode` maps it to the
    // `HardwareProbeDetail` enum and the existing
    // `hardwareProbeDetailText` helper supplies the localised
    // string. Unknown / missing codes fall through to the
    // generic "unavailable" copy.
    disabledReason: caps.hardwareVaultAvailable
        ? null
        : _hardwareDisabledReason(l10n, caps),
    onSelect: caps.hardwareVaultAvailable
        ? () => setState(() => _selected = WizardTier.hardware)
        : null,
  );

  Widget _buildParanoidRow(S l10n) => _TierRow(
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
  );

  String _keychainDisabledReason(S l10n, SecurityCapabilities caps) {
    final reason = keyringProbeDetailText(l10n, caps.keychainProbe);
    return reason.isEmpty ? l10n.tierKeychainUnavailable : reason;
  }

  String _hardwareDisabledReason(S l10n, SecurityCapabilities caps) {
    final detail = decodeHardwareProbeCode(caps.hardwareProbeCode);
    final reason = hardwareProbeDetailText(l10n, detail);
    return reason.isEmpty ? l10n.tierHardwareUnavailable : reason;
  }

  Widget _buildFooterActions(S l10n) {
    return Wrap(
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
        // change tier). On first-launch the dialog is non-dismissible
        // (`PopScope(canPop: false)`), so a Cancel button there is a
        // dead control — hide it to avoid confusing the user.
        if (widget.dismissible)
          AppButton.cancel(onTap: () => Navigator.of(context).maybePop()),
        // "Apply" on the edit path (user is already set up and just
        // changing tier) vs "Enable" on the first-launch path
        // (keychain probe came back false → user picks between T0
        // and Paranoid before startup can proceed). "Continue with
        // Recommended" was a lie when T0 or another non-recommended
        // tier was selected — replaced unconditionally.
        AppButton.primary(
          label: widget.currentTier == null
              ? l10n.securitySetupEnable
              : l10n.securitySetupApply,
          onTap: _canSubmit() ? _submit : null,
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
        return _buildMidTierPanel(l10n, caps);
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

  /// Modifier panel for the T1 / T2 branch (keychain + hardware) —
  /// they share the password + biometric toggles and an optional
  /// Linux-TPM honesty note. Extracted so [_buildModifierPanel]
  /// stays under the S3776 threshold; the switch itself is simple
  /// dispatch, each case's body belongs in its own method.
  Widget _buildMidTierPanel(S l10n, SecurityCapabilities caps) {
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
          onChanged: _onPasswordToggle,
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
  }

  /// Pair of effects triggered when the user toggles the password
  /// modifier: turning it off also turns biometric off (there is
  /// nothing to shortcut) and wipes the entry buffers so a later
  /// toggle-on starts with fresh fields. Pulled out of the inline
  /// `onChanged` so the call site stays a one-line reference.
  void _onPasswordToggle(bool v) {
    setState(() {
      _password = v;
      if (!v) {
        _biometric = false;
        _secretCtrl.wipeAndClear();
        _confirmCtrl.wipeAndClear();
      }
    });
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
    if (Platform.isAndroid) return 'AndroidKeyStore';
    return 'libsecret';
  }
}
