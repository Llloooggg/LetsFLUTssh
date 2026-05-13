import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/keystore_ssh.dart' as rust_ks;
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'app_selection_area.dart';
import 'toast.dart';

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

/// Linear wizard step ladder.
enum KeystoreWizardStep { probing, configure, generating, complete }

/// Android Hardware Keystore / StrongBox SSH key wizard.
///
/// 1. Probe — fires on open. If StrongBox + biometric are both
///    unreachable, renders disabled with the matching localized
///    reason via tooltip + tap-toast.
/// 2. Configure — algorithm radio (P-256 / Ed25519 / RSA-2048),
///    label, StrongBox toggle.
/// 3. Generate — fires the AndroidKeyStore generate inside
///    `spawn_blocking`. Success surfaces the `authorized_keys` line
///    for paste.
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

class _KeystoreSshDialogState extends State<KeystoreSshDialog> {
  KeystoreWizardStep _step = KeystoreWizardStep.probing;
  rust_ks.DbKeystoreProbeResult? _probe;
  rust_ks.DbKeystoreAlgo _algo = rust_ks.DbKeystoreAlgo.ecdsaP256;
  bool _wantStrongBox = true;
  final TextEditingController _labelCtrl = TextEditingController();
  String? _generateError;
  KeystoreSshResult? _result;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialLabel;
    if (seed != null && seed.isNotEmpty) {
      _labelCtrl.text = seed;
    }
    _kickProbe();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _kickProbe() async {
    try {
      final out = await widget.backend.probe();
      if (!mounted) return;
      setState(() {
        _probe = out;
        _step = KeystoreWizardStep.configure;
      });
    } catch (e, st) {
      AppLogger.instance.log(
        'keystore probe failed: $e',
        name: 'Keystore',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _probe = const rust_ks.DbKeystoreProbeResult.other('probe failed');
        _step = KeystoreWizardStep.configure;
      });
    }
  }

  bool get _isAvailable {
    final p = _probe;
    return p is rust_ks.DbKeystoreProbeResult_Available;
  }

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

  bool get _canGenerate => _isAvailable && _labelCtrl.text.trim().isNotEmpty;

  Future<void> _doGenerate() async {
    if (!_canGenerate) return;
    final label = _labelCtrl.text.trim();
    final wantStrongBox = _strongBoxToggleEnabled && _wantStrongBox;
    await _runGenerate(label: label, strongbox: wantStrongBox);
  }

  Future<void> _runGenerate({
    required String label,
    required bool strongbox,
  }) async {
    setState(() {
      _step = KeystoreWizardStep.generating;
      _generateError = null;
    });
    try {
      final outcome = await widget.backend.generate(
        label: label,
        algo: _algo,
        strongbox: strongbox,
      );
      if (!mounted) return;
      switch (outcome) {
        case rust_ks.DbKeystoreGenerateOutcome_Generated(:final field0):
          setState(() {
            _result = KeystoreSshResult(
              keyId: field0.keyId,
              label: field0.label,
              authorizedKeysLine: field0.authorizedKeysLine,
              strongbox: field0.strongbox,
              platform: field0.platform,
            );
            _step = KeystoreWizardStep.complete;
          });
        case rust_ks.DbKeystoreGenerateOutcome_StrongBoxUnavailable():
          // No key landed in the AndroidKeyStore. Ask the user whether
          // to accept a TEE-backed key before retrying.
          setState(() => _step = KeystoreWizardStep.configure);
          final confirmed = await _confirmStrongBoxFallback();
          if (!mounted) return;
          if (confirmed) {
            await _runGenerate(label: label, strongbox: false);
          }
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'keystore generate failed: $e',
        name: 'Keystore',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _generateError = e.toString();
        _step = KeystoreWizardStep.configure;
      });
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
    if (r != null) Navigator.of(context).pop(r);
  }

  void _doCancel() => Navigator.of(context).pop();

  Future<void> _copyAuthorizedKeysLine() async {
    final line = _result?.authorizedKeysLine ?? '';
    if (line.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: line));
    if (!mounted) return;
    Toast.show(
      context,
      message: S.of(context).copiedToClipboard,
      level: ToastLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.keystoreWizardTitle,
      content: SizedBox(width: 520, child: _buildBody(s)),
      actions: _buildActions(s),
    );
  }

  Widget _buildBody(S s) {
    switch (_step) {
      case KeystoreWizardStep.probing:
        return const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case KeystoreWizardStep.configure:
        return _buildConfigure(s);
      case KeystoreWizardStep.generating:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: AppSpacing.md),
              Text(
                s.keystoreKeyGenerating,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
            ],
          ),
        );
      case KeystoreWizardStep.complete:
        return _buildComplete(s);
    }
  }

  Widget _buildConfigure(S s) {
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
          controller: _labelCtrl,
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
        if (_generateError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AppSelectionArea(
            child: Text(
              _generateError!,
              style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.red),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComplete(S s) {
    final r = _result;
    final line = r?.authorizedKeysLine ?? '';
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
        AppSelectionArea(
          child: Text(
            s.sshKeyAuthorizedKeysHint,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppTheme.bg2,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: AppSelectionArea(
                  child: Text(
                    line,
                    style: AppFonts.mono(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fg,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.content_copy,
                tooltip: s.sshKeyPublicCopy,
                dense: true,
                onTap: _copyAuthorizedKeysLine,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(S s) {
    switch (_step) {
      case KeystoreWizardStep.probing:
      case KeystoreWizardStep.generating:
        return [AppButton.cancel(onTap: _doCancel)];
      case KeystoreWizardStep.configure:
        return [
          AppButton.cancel(onTap: _doCancel),
          AppButton.primary(
            label: s.sshKeyGenerateCta,
            onTap: _canGenerate ? _doGenerate : null,
          ),
        ];
      case KeystoreWizardStep.complete:
        return [AppButton.primary(label: s.close, onTap: _doDone)];
    }
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

// ── Android Keystore SSH row badge ────────────────────────────────

/// Hardware badge variant for `backend = 'keystore'` rows in the key
/// manager. Mirrors [HelloBadge] / [EnclaveBadge] / [Pkcs11Badge] /
/// [TpmBadge].
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

  void _showInfo(BuildContext context) {
    final s = S.of(context);
    final lines = <String>[
      strongbox ? s.keystoreKeyStrongBoxLabel : s.keystoreKeyTeeLabel,
      ?platform,
      s.keystoreKeyExportDisabled,
    ];
    AppDialog.show<void>(
      context,
      builder: (ctx) => AppDialog(
        title: s.keystoreBadge,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) ...[
              AppSelectionArea(
                child: Text(
                  line,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fgDim,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.sm),
            AppSelectionArea(
              child: Text(
                s.keystoreKeyInvalidatedByEnrollment,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.orange,
                ),
              ),
            ),
          ],
        ),
        actions: [AppButton.cancel(onTap: () => Navigator.of(ctx).pop())],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => _showInfo(context),
        borderRadius: AppTheme.radiusSm,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppTheme.green.withValues(alpha: 0.16),
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.security, size: 12, color: AppTheme.green),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.xxs,
                  color: AppTheme.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Suppress unused warning for the Android-only conditional reference
// some import sites pick up via `Platform.isAndroid`.
// ignore: unused_element
bool _suppressUnused() => Platform.isAndroid;
