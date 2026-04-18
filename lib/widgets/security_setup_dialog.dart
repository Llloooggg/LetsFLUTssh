import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/security/hardware_tier_vault.dart';
import '../core/security/secure_key_storage.dart';
import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_info_button.dart';
import 'password_strength_meter.dart';
import 'toast.dart';

/// Result of the first-launch security setup wizard.
class SecuritySetupResult {
  /// Tier picked by the user. `plaintext` is the fallback when the
  /// wizard never resolves (barrier-dismiss on desktop shutdown).
  final SecurityTier tier;

  /// Master password (tier == paranoid) chosen by the user.
  final String? masterPassword;

  /// Short password for the L2 keychain gate.
  final String? shortPassword;

  /// PIN digits chosen for the L3 hardware tier.
  final String? pin;

  /// Whether the OS keychain is available.
  final bool keychainAvailable;

  const SecuritySetupResult({
    this.tier = SecurityTier.plaintext,
    this.masterPassword,
    this.shortPassword,
    this.pin,
    this.keychainAvailable = false,
  });
}

/// First-launch tier wizard.
///
/// Numbered ladder (L0–L3) + separate Paranoid branch. Every row has
/// an `(i)` info button that opens an `AppInfoDialog` explaining what
/// the tier does and does not protect against. Tiers that the current
/// platform cannot satisfy render greyed with a tooltip explaining why.
class SecuritySetupDialog extends StatefulWidget {
  final SecureKeyStorage keyStorage;
  final HardwareTierVault hardwareVault;

  const SecuritySetupDialog({
    super.key,
    required this.keyStorage,
    required this.hardwareVault,
  });

  static Future<SecuritySetupResult> show(
    BuildContext context, {
    required SecureKeyStorage keyStorage,
    HardwareTierVault? hardwareVault,
  }) async {
    final result = await showDialog<SecuritySetupResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SecuritySetupDialog(
        keyStorage: keyStorage,
        hardwareVault: hardwareVault ?? HardwareTierVault(),
      ),
    );
    return result ?? const SecuritySetupResult();
  }

  @override
  State<SecuritySetupDialog> createState() => _SecuritySetupDialogState();
}

enum _Form { none, paranoid, l2Password, l3Pin }

class _SecuritySetupDialogState extends State<SecuritySetupDialog> {
  bool _probing = true;
  bool _keychainAvailable = false;
  bool _hardwareAvailable = false;

  _Form _form = _Form.none;
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _passwordCtrl.wipeAndClear();
    _confirmCtrl.wipeAndClear();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final results = await Future.wait([
      widget.keyStorage.isAvailable(),
      widget.hardwareVault.isAvailable(),
    ]);
    if (!mounted) return;
    setState(() {
      _keychainAvailable = results[0];
      _hardwareAvailable = results[1];
      _probing = false;
    });
  }

  void _pickPlaintext() {
    Navigator.of(context).pop(
      const SecuritySetupResult(
        tier: SecurityTier.plaintext,
        keychainAvailable: false,
      ),
    );
  }

  void _pickKeychain() {
    Navigator.of(context).pop(
      SecuritySetupResult(
        tier: SecurityTier.keychain,
        keychainAvailable: _keychainAvailable,
      ),
    );
  }

  void _showForm(_Form form) {
    _passwordCtrl.wipeAndClear();
    _confirmCtrl.wipeAndClear();
    setState(() => _form = form);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passwordFocus.requestFocus();
    });
  }

  void _submitParanoid() {
    final l10n = S.of(context);
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;
    if (password != _confirmCtrl.text) {
      Toast.show(context, message: l10n.passwordsDoNotMatch);
      return;
    }
    Navigator.of(context).pop(
      SecuritySetupResult(
        tier: SecurityTier.paranoid,
        masterPassword: password,
        keychainAvailable: _keychainAvailable,
      ),
    );
  }

  void _submitL2() {
    final l10n = S.of(context);
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;
    if (password != _confirmCtrl.text) {
      Toast.show(context, message: l10n.passwordsDoNotMatch);
      return;
    }
    Navigator.of(context).pop(
      SecuritySetupResult(
        tier: SecurityTier.keychainWithPassword,
        shortPassword: password,
        keychainAvailable: _keychainAvailable,
      ),
    );
  }

  void _submitL3() {
    final l10n = S.of(context);
    final pin = _passwordCtrl.text;
    if (!_isValidPin(pin)) {
      Toast.show(context, message: l10n.pinMustBe4To6Digits);
      return;
    }
    if (pin != _confirmCtrl.text) {
      Toast.show(context, message: l10n.pinsDoNotMatch);
      return;
    }
    Navigator.of(context).pop(
      SecuritySetupResult(
        tier: SecurityTier.hardware,
        pin: pin,
        keychainAvailable: _keychainAvailable,
      ),
    );
  }

  bool _isValidPin(String pin) {
    if (pin.length < 4 || pin.length > 6) return false;
    return RegExp(r'^\d+$').hasMatch(pin);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildContent(S.of(context)),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(S l10n) {
    if (_probing) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 16),
          CircularProgressIndicator(),
          SizedBox(height: 16),
        ],
      );
    }
    switch (_form) {
      case _Form.paranoid:
        return _buildParanoidForm(l10n);
      case _Form.l2Password:
        return _buildL2Form(l10n);
      case _Form.l3Pin:
        return _buildL3Form(l10n);
      case _Form.none:
        return _buildTierLadder(l10n);
    }
  }

  Widget _buildTierLadder(S l10n) {
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
        const SizedBox(height: 18),

        _TierRow(
          badge: 'L0',
          label: l10n.tierPlaintextLabel,
          subtitle: l10n.tierPlaintextSubtitle,
          infoTitle: l10n.tierPlaintextLabel,
          infoProtects: const [],
          infoDoesNotProtect: [
            l10n.tierPlaintextThreat1,
            l10n.tierPlaintextThreat2,
          ],
          infoNotes: l10n.tierPlaintextNotes,
          accent: AppTheme.red,
          onPick: _pickPlaintext,
        ),

        _TierRow(
          badge: 'L1',
          label: l10n.tierKeychainLabel,
          subtitle: l10n.tierKeychainSubtitle(_keychainName),
          infoTitle: l10n.tierKeychainLabel,
          infoProtects: [l10n.tierKeychainProtect1, l10n.tierKeychainProtect2],
          infoDoesNotProtect: [
            l10n.tierKeychainThreat1,
            l10n.tierKeychainThreat2,
          ],
          accent: AppTheme.accent,
          recommended: _keychainAvailable && !_hardwareAvailable,
          disabledReason: _keychainAvailable
              ? null
              : l10n.tierKeychainUnavailable,
          onPick: _keychainAvailable ? _pickKeychain : null,
        ),

        _TierRow(
          badge: 'L2',
          label: l10n.tierKeychainPassLabel,
          subtitle: l10n.tierKeychainPassSubtitle,
          infoTitle: l10n.tierKeychainPassLabel,
          infoProtects: [
            l10n.tierKeychainPassProtect1,
            l10n.tierKeychainPassProtect2,
          ],
          infoDoesNotProtect: [
            l10n.tierKeychainPassThreat1,
            l10n.tierKeychainPassThreat2,
          ],
          accent: AppTheme.accent,
          disabledReason: _keychainAvailable
              ? null
              : l10n.tierKeychainUnavailable,
          onPick: _keychainAvailable ? () => _showForm(_Form.l2Password) : null,
        ),

        _TierRow(
          badge: 'L3',
          label: l10n.tierHardwareLabel,
          subtitle: l10n.tierHardwareSubtitle,
          infoTitle: l10n.tierHardwareLabel,
          infoProtects: [l10n.tierHardwareProtect1, l10n.tierHardwareProtect2],
          infoDoesNotProtect: [
            l10n.tierHardwareThreat1,
            l10n.tierHardwareThreat2,
          ],
          accent: AppTheme.green,
          recommended: _hardwareAvailable,
          disabledReason: _hardwareAvailable
              ? null
              : l10n.tierHardwareUnavailable,
          onPick: _hardwareAvailable ? () => _showForm(_Form.l3Pin) : null,
        ),

        const SizedBox(height: 14),
        Divider(color: AppTheme.border),
        const SizedBox(height: 10),
        Text(
          l10n.tierAlternativeBranchLabel,
          style: TextStyle(
            fontSize: AppFonts.sm,
            color: AppTheme.fgDim,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        _TierRow(
          badge: null,
          label: l10n.tierParanoidLabel,
          subtitle: l10n.tierParanoidSubtitle,
          infoTitle: l10n.tierParanoidLabel,
          infoProtects: [l10n.tierParanoidProtect1, l10n.tierParanoidProtect2],
          infoDoesNotProtect: [
            l10n.tierParanoidThreat1,
            l10n.tierParanoidThreat2,
          ],
          infoNotes: l10n.tierParanoidNotes,
          accent: AppTheme.purple,
          recommended: !_keychainAvailable && !_hardwareAvailable,
          onPick: () => _showForm(_Form.paranoid),
        ),
      ],
    );
  }

  Widget _buildParanoidForm(S l10n) {
    return _FormShell(
      icon: Icons.lock,
      title: l10n.tierParanoidLabel,
      warning: l10n.masterPasswordWarning,
      primaryFields: [
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: true,
          onSubmitted: (_) => _submitParanoid(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.newPassword),
        ),
        PasswordStrengthMeter(controller: _passwordCtrl),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          onSubmitted: (_) => _submitParanoid(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.confirmPassword),
        ),
      ],
      onOk: _submitParanoid,
      onCancel: () => setState(() => _form = _Form.none),
    );
  }

  Widget _buildL2Form(S l10n) {
    return _FormShell(
      icon: Icons.lock_outline,
      title: l10n.tierKeychainPassLabel,
      warning: l10n.tierKeychainPassSetHint,
      primaryFields: [
        Text(
          l10n.tierKeychainPassSetPrompt,
          style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: true,
          onSubmitted: (_) => _submitL2(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.newPassword),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          onSubmitted: (_) => _submitL2(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.confirmPassword),
        ),
      ],
      onOk: _submitL2,
      onCancel: () => setState(() => _form = _Form.none),
    );
  }

  Widget _buildL3Form(S l10n) {
    return _FormShell(
      icon: Icons.pin,
      title: l10n.tierHardwareLabel,
      warning: l10n.tierHardwarePinSetHint,
      primaryFields: [
        Text(
          l10n.tierHardwarePinSetPrompt,
          style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onSubmitted: (_) => _submitL3(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.pinLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onSubmitted: (_) => _submitL3(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.confirmPin),
        ),
      ],
      onOk: _submitL3,
      onCancel: () => setState(() => _form = _Form.none),
    );
  }

  static String get _keychainName {
    if (Platform.isMacOS || Platform.isIOS) return 'Keychain';
    if (Platform.isWindows) return 'Credential Manager';
    if (Platform.isAndroid) return 'EncryptedSharedPreferences';
    return 'libsecret'; // Linux
  }
}

class _FormShell extends StatelessWidget {
  const _FormShell({
    required this.icon,
    required this.title,
    required this.warning,
    required this.primaryFields,
    required this.onOk,
    required this.onCancel,
  });

  final IconData icon;
  final String title;
  final String warning;
  final List<Widget> primaryFields;
  final VoidCallback onOk;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 40, color: AppTheme.accent),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          warning,
          style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
        const SizedBox(height: 16),
        ...primaryFields,
        const SizedBox(height: 24),
        FilledButton(onPressed: onOk, child: Text(l10n.ok)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: Text(l10n.cancel, style: TextStyle(color: AppTheme.fgDim)),
        ),
      ],
    );
  }
}

/// Single row in the tier ladder. Keeps the wizard layout readable —
/// the only non-trivial piece is the disabled-with-reason pattern
/// (fade + tooltip + toast on tap), which mirrors the canonical
/// `_Toggle` implementation in settings.
class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.badge,
    required this.label,
    required this.subtitle,
    required this.infoTitle,
    required this.infoProtects,
    required this.infoDoesNotProtect,
    required this.accent,
    this.infoNotes,
    this.recommended = false,
    this.disabledReason,
    this.onPick,
  });

  final String? badge;
  final String label;
  final String subtitle;
  final String infoTitle;
  final List<String> infoProtects;
  final List<String> infoDoesNotProtect;
  final String? infoNotes;
  final Color accent;
  final bool recommended;
  final String? disabledReason;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final enabled = onPick != null;
    VoidCallback? tap;
    if (enabled) {
      tap = onPick;
    } else if (disabledReason != null) {
      tap = () =>
          Toast.show(context, message: disabledReason!, level: ToastLevel.info);
    }

    Widget row = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        border: Border.all(
          color: recommended ? accent : AppTheme.border,
          width: recommended ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (badge != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                badge!,
                style: TextStyle(
                  color: accent,
                  fontSize: AppFonts.md,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: AppFonts.md,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.fg,
                        ),
                      ),
                    ),
                    if (recommended) ...[
                      const SizedBox(width: 6),
                      _RecommendedBadge(accent: accent),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fgDim,
                  ),
                ),
              ],
            ),
          ),
          AppInfoButton(
            title: infoTitle,
            protectsAgainst: infoProtects,
            doesNotProtectAgainst: infoDoesNotProtect,
            extraNotes: infoNotes,
          ),
          IconButton(
            tooltip: enabled ? null : disabledReason,
            onPressed: tap,
            icon: Icon(
              enabled ? Icons.arrow_forward_ios : Icons.lock_clock,
              size: 16,
              color: enabled ? accent : AppTheme.fgFaint,
            ),
          ),
        ],
      ),
    );
    if (!enabled) {
      row = Opacity(opacity: 0.55, child: row);
      if (disabledReason != null) {
        row = Tooltip(message: disabledReason!, child: row);
      }
    }
    return row;
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        S.of(context).tierRecommendedBadge,
        style: TextStyle(
          fontSize: AppFonts.xs,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}
