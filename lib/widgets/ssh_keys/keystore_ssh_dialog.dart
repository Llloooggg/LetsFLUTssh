import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../src/rust/api/keystore_ssh.dart' as rust_ks;
import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../core/app_selection_area.dart';
import 'hardware_key_badge.dart';
import 'hardware_key_wizard.dart';

/// Bundled outcome of a successful Android Keystore SSH wizard run.
/// Returned via `Navigator.pop` so the caller can refresh its key
/// listing without reaching back into FRB.
class KeystoreSshResult {
  final String keyId;
  final String label;
  final String authorizedKeysLine;
  final bool strongbox;
  final String? platform;
  const KeystoreSshResult({
    required this.keyId,
    required this.label,
    required this.authorizedKeysLine,
    required this.strongbox,
    this.platform,
  });
}

/// Backend abstraction so widget tests can drive each wizard step
/// without booting FRB. Mirrors the [TpmBackend] / [HelloBackend]
/// surfaces one file over.
abstract class KeystoreBackend {
  const KeystoreBackend();

  Future<rust_ks.DbKeystoreProbeResult> probe();

  Future<rust_ks.DbKeystoreGenerateOutcome> generate({
    required String label,
    required rust_ks.DbKeystoreAlgo algo,
    required bool strongbox,
  });
}

class KeystoreFrbBackend extends KeystoreBackend {
  const KeystoreFrbBackend();

  @override
  Future<rust_ks.DbKeystoreProbeResult> probe() => rust_ks.keystoreSshProbe();

  @override
  Future<rust_ks.DbKeystoreGenerateOutcome> generate({
    required String label,
    required rust_ks.DbKeystoreAlgo algo,
    required bool strongbox,
  }) {
    return rust_ks.keystoreSshGenerate(
      args: rust_ks.DbKeystoreGenerateArgs(
        label: label,
        algo: algo,
        strongbox: strongbox,
      ),
    );
  }
}

/// Android Hardware Keystore / StrongBox SSH key wizard. Walks the
/// shared [HardwareKeyWizardMixin] ladder:
///
/// 1. Probe — fires on open. If StrongBox + biometric are both
///    unreachable, the configure step renders disabled with the
///    matching localized reason.
/// 2. Configure — algorithm radio (P-256 / Ed25519 / RSA-2048), label,
///    StrongBox toggle.
/// 3. Generate — fires the AndroidKeyStore generate inside
///    `spawn_blocking`; success surfaces the `authorized_keys` line.
///
/// The BiometricPrompt fires only on subsequent sign calls — not at
/// generate time — because `setUserAuthenticationParameters(0,
/// AUTH_BIOMETRIC_STRONG)` only gates `Signature` operations.
class KeystoreSshDialog extends StatefulWidget {
  final KeystoreBackend backend;

  /// Initial label to seed the wizard's label field. Used by the
  /// key-manager stub re-generate flow so the user lands on a form
  /// that already carries the migrated stub's name; `null` means
  /// the wizard starts with an empty label.
  final String? initialLabel;

  const KeystoreSshDialog({
    super.key,
    this.backend = const KeystoreFrbBackend(),
    this.initialLabel,
  });

  static Future<KeystoreSshResult?> show(
    BuildContext context, {
    KeystoreBackend backend = const KeystoreFrbBackend(),
    String? initialLabel,
  }) {
    return AppDialog.show<KeystoreSshResult>(
      context,
      builder: (_) =>
          KeystoreSshDialog(backend: backend, initialLabel: initialLabel),
    );
  }

  @override
  State<KeystoreSshDialog> createState() => _KeystoreSshDialogState();
}

class _KeystoreSshDialogState extends State<KeystoreSshDialog>
    with HardwareKeyWizardMixin {
  rust_ks.DbKeystoreProbeResult? _probe;
  rust_ks.DbKeystoreAlgo _algo = rust_ks.DbKeystoreAlgo.ecdsaP256;
  bool _wantStrongBox = true;
  KeystoreSshResult? _result;

  @override
  String wizardTitle(S s) => s.keystoreWizardTitle;

  @override
  String get wizardLogName => 'Keystore';

  @override
  String? get wizardInitialLabel => widget.initialLabel;

  @override
  String generatingLabel(S s) => s.keystoreKeyGenerating;

  @override
  Future<void> runProbe() async {
    _probe = await widget.backend.probe();
  }

  @override
  void onProbeFailure(Object error) {
    _probe = const rust_ks.DbKeystoreProbeResult.other('probe failed');
  }

  bool get _isAvailable => _probe is rust_ks.DbKeystoreProbeResult_Available;

  bool get _strongBoxFeature {
    final p = _probe;
    if (p is rust_ks.DbKeystoreProbeResult_Available) {
      return p.strongboxAvailable;
    }
    return false;
  }

  // StrongBox toggle is meaningful only when:
  //   1) the device has the FEATURE_STRONGBOX_KEYSTORE capability;
  //   2) the chosen algorithm is uniformly StrongBox-eligible at our
  //      min-SDK — ECDSA P-256 + RSA-2048 only. Ed25519 has no
  //      StrongBox guarantee even on capable devices.
  bool get _algoStrongBoxEligible => _algo != rust_ks.DbKeystoreAlgo.ed25519;

  bool get _strongBoxToggleEnabled =>
      _strongBoxFeature && _algoStrongBoxEligible;

  @override
  bool get canGenerate => _isAvailable && labelCtrl.text.trim().isNotEmpty;

  @override
  Future<String?> runGenerate() async {
    final wantStrongBox = _strongBoxToggleEnabled && _wantStrongBox;
    final outcome = await widget.backend.generate(
      label: labelCtrl.text.trim(),
      algo: _algo,
      strongbox: wantStrongBox,
    );
    if (!mounted) return null;
    switch (outcome) {
      case rust_ks.DbKeystoreGenerateOutcome_Generated(:final field0):
        _result = KeystoreSshResult(
          keyId: field0.keyId,
          label: field0.label,
          authorizedKeysLine: field0.authorizedKeysLine,
          strongbox: field0.strongbox,
          platform: field0.platform,
        );
        return field0.authorizedKeysLine;
      case rust_ks.DbKeystoreGenerateOutcome_StrongBoxUnavailable():
        // No key landed in the AndroidKeyStore. Drop back to configure
        // and ask whether to accept a TEE-backed key before retrying.
        backToConfigure();
        final confirmed = await _confirmStrongBoxFallback();
        if (!mounted) return null;
        if (confirmed) {
          _wantStrongBox = false;
          unawaited(runGenerateFlow());
        }
        return null;
    }
  }

  Future<bool> _confirmStrongBoxFallback() async {
    final s = S.of(context);
    final ok = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.keystoreStrongBoxFallbackTitle,
        content: AppSelectionArea(
          child: Text(
            s.keystoreStrongBoxFallbackBody,
            style: AppFonts.inter(fontSize: AppFonts.sm),
          ),
        ),
        actions: [
          AppButton.secondary(
            label: s.keystoreStrongBoxFallbackCancel,
            onTap: () => Navigator.of(ctx).pop(false),
          ),
          AppButton.primary(
            label: s.keystoreStrongBoxFallbackConfirm,
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _doDone() {
    final r = _result;
    if (r != null) finishWith(r);
  }

  @override
  Widget build(BuildContext context) {
    return buildWizard(S.of(context), onDone: _doDone);
  }

  @override
  Widget buildComplete(S s) {
    final r = _result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSelectionArea(
          child: Text(
            r != null && r.strongbox
                ? s.keystoreKeyStrongBoxLabel
                : s.keystoreKeyTeeLabel,
            style: AppFonts.inter(
              fontSize: AppFonts.sm,
              color: AppTheme.fgDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        authorizedKeysBox(s),
      ],
    );
  }

  @override
  Widget buildConfigure(S s) {
    final disabled = !_isAvailable;
    final reason = _availabilityReason(s);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (disabled) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.08),
              borderRadius: AppTheme.radiusSm,
              border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
            ),
            child: AppSelectionArea(
              child: Text(
                reason,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.red,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        AppSelectionArea(
          child: Text(
            s.keystoreKeyAndroidLabel,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: labelCtrl,
          enabled: !disabled,
          autofocus: !disabled,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: s.tpmSshLabel),
        ),
        const SizedBox(height: AppSpacing.lg),
        RadioGroup<rust_ks.DbKeystoreAlgo>(
          groupValue: _algo,
          onChanged: (rust_ks.DbKeystoreAlgo? v) {
            if (disabled || v == null) return;
            setState(() {
              _algo = v;
              if (!_algoStrongBoxEligible) {
                _wantStrongBox = false;
              }
            });
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<rust_ks.DbKeystoreAlgo>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_ks.DbKeystoreAlgo.ecdsaP256,
                title: Text(
                  s.keystoreAlgEcdsaP256,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
              RadioListTile<rust_ks.DbKeystoreAlgo>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_ks.DbKeystoreAlgo.ed25519,
                title: Text(
                  s.keystoreAlgEd25519,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
              RadioListTile<rust_ks.DbKeystoreAlgo>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_ks.DbKeystoreAlgo.rsa2048,
                title: Text(
                  s.keystoreAlgRsa2048,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Tooltip(
          message: _strongBoxToggleEnabled
              ? s.keystoreKeyStrongBoxLabel
              : s.keystoreKeyStrongBoxUnavailable,
          child: CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              s.keystoreKeyStrongBoxLabel,
              style: AppFonts.inter(fontSize: AppFonts.sm),
            ),
            subtitle: !_strongBoxToggleEnabled
                ? Text(
                    s.keystoreKeyStrongBoxUnavailable,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  )
                : null,
            value: _strongBoxToggleEnabled && _wantStrongBox,
            onChanged: (disabled || !_strongBoxToggleEnabled)
                ? null
                : (v) => setState(() => _wantStrongBox = v ?? false),
          ),
        ),
        if (generateError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppSelectionArea(
            child: Text(
              generateError!,
              style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.red),
            ),
          ),
        ],
      ],
    );
  }

  String _availabilityReason(S s) {
    final p = _probe;
    if (p is rust_ks.DbKeystoreProbeResult_BiometricNotEnrolled) {
      return s.keystoreKeyBiometricNotEnrolled;
    }
    if (p is rust_ks.DbKeystoreProbeResult_Unsupported) {
      return s.keystoreKeyAndroidLabel;
    }
    if (p is rust_ks.DbKeystoreProbeResult_Other) {
      return p.field0;
    }
    return '';
  }
}

/// Android Keystore row badge for `backend = 'keystore'` key-manager
/// rows. A thin [HardwareKeyBadge] caller — the green security pill with
/// a tap popover surfacing the StrongBox / TEE tier + enrollment caveat.
class KeystoreBadge extends StatelessWidget {
  final String label;
  final bool strongbox;
  final String? platform;
  const KeystoreBadge({
    super.key,
    required this.label,
    this.strongbox = false,
    this.platform,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final plat = platform;
    return HardwareKeyBadge(
      label: label,
      color: AppTheme.green,
      icon: Icons.security,
      info: HardwareKeyBadgeInfo(
        title: s.keystoreBadge,
        lines: [
          HardwareKeyInfoLine(
            strongbox ? s.keystoreKeyStrongBoxLabel : s.keystoreKeyTeeLabel,
          ),
          if (plat != null && plat.isNotEmpty) HardwareKeyInfoLine(plat),
          HardwareKeyInfoLine(s.keystoreKeyExportDisabled),
          HardwareKeyInfoLine.warn(s.keystoreKeyInvalidatedByEnrollment),
        ],
      ),
    );
  }
}
