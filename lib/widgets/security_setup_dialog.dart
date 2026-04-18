import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/security/secure_key_storage.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_info_button.dart';
import 'password_strength_meter.dart';
import 'toast.dart';

/// Result of the first-launch security setup wizard.
class SecuritySetupResult {
  /// The master password chosen by the user, or null if they skipped.
  final String? masterPassword;

  /// Whether the OS keychain is available.
  final bool keychainAvailable;

  const SecuritySetupResult({
    this.masterPassword,
    required this.keychainAvailable,
  });
}

/// First-launch tier wizard.
///
/// Renders a numbered ladder (L0–L3) + a separate **Paranoid**
/// alternative branch. L2 (keychain + password) and L3 (hardware +
/// PIN) rows are disabled with an "Unlock in a future version"
/// tooltip — the underlying vault / PIN plumbing ships in follow-on
/// commits. Every row has an `(i)` info button that opens an
/// [AppInfoDialog] explaining what that tier protects against and
/// what it does not.
///
/// Non-dismissible. Returns [SecuritySetupResult] so the legacy
/// `main.dart._firstLaunchSetup` handler can continue to drive the
/// existing `SecurityLevel` state — `main` mirrors the resolved
/// level into `config.json`'s `security_tier` field separately.
class SecuritySetupDialog extends StatefulWidget {
  final SecureKeyStorage keyStorage;

  const SecuritySetupDialog({super.key, required this.keyStorage});

  static Future<SecuritySetupResult> show(
    BuildContext context, {
    required SecureKeyStorage keyStorage,
  }) async {
    final result = await showDialog<SecuritySetupResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SecuritySetupDialog(keyStorage: keyStorage),
    );
    return result ?? const SecuritySetupResult(keychainAvailable: false);
  }

  @override
  State<SecuritySetupDialog> createState() => _SecuritySetupDialogState();
}

class _SecuritySetupDialogState extends State<SecuritySetupDialog> {
  bool _probing = true;
  bool _keychainAvailable = false;

  // Master password form state.
  bool _showPasswordForm = false;
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _probeKeychain();
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

  Future<void> _probeKeychain() async {
    final available = await widget.keyStorage.isAvailable();
    if (mounted) {
      setState(() {
        _keychainAvailable = available;
        _probing = false;
      });
    }
  }

  void _pickKeychain() {
    Navigator.of(
      context,
    ).pop(const SecuritySetupResult(keychainAvailable: true));
  }

  void _pickPlaintext() {
    Navigator.of(
      context,
    ).pop(const SecuritySetupResult(keychainAvailable: false));
  }

  void _pickParanoid() {
    setState(() => _showPasswordForm = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passwordFocus.requestFocus();
    });
  }

  void _submitMasterPassword() {
    final l10n = S.of(context);
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;
    if (password != _confirmCtrl.text) {
      Toast.show(context, message: l10n.passwordsDoNotMatch);
      return;
    }
    Navigator.of(context).pop(
      SecuritySetupResult(
        masterPassword: password,
        keychainAvailable: _keychainAvailable,
      ),
    );
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
    if (_showPasswordForm) return _buildPasswordForm(l10n);
    return _buildTierLadder(l10n);
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

        // L0 — Plaintext. Always available; shown with a red warning
        // because it is the only tier that offers no crypto at all.
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

        // L1 — Keychain. Recommended default when an OS keychain is
        // available (iOS/macOS Secure Enclave, Android Keystore,
        // Windows DPAPI, Linux libsecret). On platforms without it
        // the row is disabled and Paranoid becomes the obvious pick.
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
          recommended: _keychainAvailable,
          disabledReason: _keychainAvailable
              ? null
              : l10n.tierKeychainUnavailable,
          onPick: _keychainAvailable ? _pickKeychain : null,
        ),

        // L2 — Keychain + short password. Wizard row is a placeholder
        // until the pass-on-open + persisted rate-limit plumbing
        // ships; disabled with an "upcoming" tooltip so the user sees
        // the option exists and knows why it's off.
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
          infoNotes: l10n.tierUpcomingNotes,
          accent: AppTheme.accent,
          disabledReason: l10n.tierUpcomingTooltip,
          onPick: null,
        ),

        // L3 — Hardware + PIN. Same upcoming-feature placeholder.
        // The underlying hardware-vault + PIN-rate-limit wiring is
        // scoped for a dedicated commit; wizard row is disabled with
        // an honest reason tooltip today.
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
          infoNotes: l10n.tierUpcomingNotes,
          accent: AppTheme.green,
          disabledReason: l10n.tierUpcomingTooltip,
          onPick: null,
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

        // Paranoid — no number, alternative branch. Always
        // available; recommended when L1 is not available on the
        // host (no OS keychain).
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
          recommended: !_keychainAvailable,
          onPick: _pickParanoid,
        ),
      ],
    );
  }

  Widget _buildPasswordForm(S l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock, size: 40, color: AppTheme.accent),
        const SizedBox(height: 12),
        Text(
          l10n.tierParanoidLabel,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.masterPasswordWarning,
          style: TextStyle(
            fontSize: AppFonts.sm,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: true,
          onSubmitted: (_) => _submitMasterPassword(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.newPassword),
        ),
        PasswordStrengthMeter(controller: _passwordCtrl),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          onSubmitted: (_) => _submitMasterPassword(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.confirmPassword),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _submitMasterPassword, child: Text(l10n.ok)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _showPasswordForm = false),
          child: Text(l10n.cancel, style: TextStyle(color: AppTheme.fgDim)),
        ),
      ],
    );
  }

  static String get _keychainName {
    if (Platform.isMacOS || Platform.isIOS) return 'Keychain';
    if (Platform.isWindows) return 'Credential Manager';
    if (Platform.isAndroid) return 'EncryptedSharedPreferences';
    return 'libsecret'; // Linux
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
