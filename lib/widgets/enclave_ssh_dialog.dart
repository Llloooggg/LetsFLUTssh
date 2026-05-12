import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/enclave.dart' as rust_enclave;
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'app_selection_area.dart';
import 'toast.dart';

/// Bundled outcome of a successful Secure Enclave wizard run.
/// Returned via `Navigator.pop` so the caller can refresh its key
/// listing without reaching back into FRB — the row already landed
/// Rust-side as part of `enclaveSshGenerate`.
class EnclaveSshResult {
  /// The new `ssh_keys.id` Rust assigned.
  final String keyId;
  final String label;
  final String authorizedKeysLine;
  const EnclaveSshResult({
    required this.keyId,
    required this.label,
    required this.authorizedKeysLine,
  });
}

/// Backend abstraction so widget tests can drive each wizard step
/// without booting FRB. The production implementation
/// ([EnclaveFrbBackend]) delegates straight to the FRB shim; tests
/// override individual methods to seed deterministic responses.
abstract class EnclaveBackend {
  const EnclaveBackend();

  /// Probe whether SE-SSH is reachable on this host.
  Future<rust_enclave.DbEnclaveAvailability> probe();

  /// Mint a fresh key + persist it as an `ssh_keys` row. Surfaces
  /// the OS biometric / passcode prompt inside the call.
  Future<rust_enclave.DbEnclaveImportResult> generate({
    required String label,
    required rust_enclave.DbEnclaveAuthPolicy policy,
  });
}

class EnclaveFrbBackend extends EnclaveBackend {
  const EnclaveFrbBackend();

  @override
  Future<rust_enclave.DbEnclaveAvailability> probe() =>
      rust_enclave.enclaveSshProbe();

  @override
  Future<rust_enclave.DbEnclaveImportResult> generate({
    required String label,
    required rust_enclave.DbEnclaveAuthPolicy policy,
  }) {
    return rust_enclave.enclaveSshGenerate(
      args: rust_enclave.DbEnclaveGenerateArgs(label: label, policy: policy),
    );
  }
}

/// Linear wizard step ladder. The dialog walks these in order; the
/// probe step short-circuits to the disabled-with-reason UI when the
/// host cannot reach the chip (ad-hoc-signed bundle, no SE, no
/// passcode, non-Apple build).
enum EnclaveWizardStep { probing, configure, generating, complete }

/// Apple Secure Enclave SSH key wizard. Renders a 3-stage flow:
///
/// 1. Probe — runs at open. If the host can't reach the chip
///    (`errSecMissingEntitlement`, no SE silicon, no passcode), the
///    dialog renders disabled with the localized reason + "Cancel"
///    affordance. Configuration surfaces follow CLAUDE.md's
///    "disable, don't hide" rule: the user is exploring what the
///    app can do, so the toolbar action stays visible with the
///    reason in a tooltip.
/// 2. Configure — label + auth-policy radio (Touch ID / Face ID
///    required vs passcode fallback). The user clicks "Generate".
/// 3. Complete — fires the OS biometric prompt at the
///    `enclaveSshGenerate` boundary, displays the
///    authorized_keys-shaped public-key line with a copy
///    affordance, and offers "Done" to pop the dialog.
class EnclaveSshDialog extends StatefulWidget {
  /// Backend injection. Defaults to the FRB-backed implementation.
  final EnclaveBackend backend;

  const EnclaveSshDialog({super.key, this.backend = const EnclaveFrbBackend()});

  /// Convenience opener. Always returns whatever the dialog popped
  /// — `null` when the user dismissed without generating.
  static Future<EnclaveSshResult?> show(
    BuildContext context, {
    EnclaveBackend backend = const EnclaveFrbBackend(),
  }) {
    return AppDialog.show<EnclaveSshResult>(
      context,
      builder: (_) => EnclaveSshDialog(backend: backend),
    );
  }

  @override
  State<EnclaveSshDialog> createState() => _EnclaveSshDialogState();
}

class _EnclaveSshDialogState extends State<EnclaveSshDialog> {
  EnclaveWizardStep _step = EnclaveWizardStep.probing;
  rust_enclave.DbEnclaveAvailability? _availability;
  rust_enclave.DbEnclaveAuthPolicy _policy =
      rust_enclave.DbEnclaveAuthPolicy.biometryCurrentSet;
  final TextEditingController _labelCtrl = TextEditingController();
  String? _generateError;
  EnclaveSshResult? _result;

  @override
  void initState() {
    super.initState();
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
        _availability = out;
        _step = EnclaveWizardStep.configure;
      });
    } catch (e, st) {
      AppLogger.instance.log(
        'enclave probe failed: $e',
        name: 'Enclave',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _availability = rust_enclave.DbEnclaveAvailability.other(e.toString());
        _step = EnclaveWizardStep.configure;
      });
    }
  }

  bool get _canGenerate {
    final a = _availability;
    if (a == null) return false;
    if (a is! rust_enclave.DbEnclaveAvailability_Available) return false;
    return _labelCtrl.text.trim().isNotEmpty;
  }

  Future<void> _doGenerate() async {
    if (!_canGenerate) return;
    final label = _labelCtrl.text.trim();
    setState(() {
      _step = EnclaveWizardStep.generating;
      _generateError = null;
    });
    try {
      final result = await widget.backend.generate(
        label: label,
        policy: _policy,
      );
      if (!mounted) return;
      setState(() {
        _result = EnclaveSshResult(
          keyId: result.keyId,
          label: result.label,
          authorizedKeysLine: result.authorizedKeysLine,
        );
        _step = EnclaveWizardStep.complete;
      });
    } catch (e, st) {
      AppLogger.instance.log(
        'enclave generate failed: $e',
        name: 'Enclave',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _generateError = e.toString();
        _step = EnclaveWizardStep.configure;
      });
    }
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
      title: s.sshKeyEnclaveWizardTitle,
      content: SizedBox(width: 520, child: _buildBody(s)),
      actions: _buildActions(s),
    );
  }

  Widget _buildBody(S s) {
    switch (_step) {
      case EnclaveWizardStep.probing:
        return const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case EnclaveWizardStep.configure:
        return _buildConfigure(s);
      case EnclaveWizardStep.generating:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: AppSpacing.md),
              Text(
                s.sshKeyGenerateInProgress,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
            ],
          ),
        );
      case EnclaveWizardStep.complete:
        return _buildComplete(s);
    }
  }

  Widget _buildConfigure(S s) {
    final a = _availability!;
    final disabled = a is! rust_enclave.DbEnclaveAvailability_Available;
    final reason = _availabilityReason(s, a);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSelectionArea(
          child: Text(
            s.sshKeyHardwareBoundExplainer,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppSelectionArea(
          child: Text(
            Theme.of(context).platform == TargetPlatform.iOS
                ? s.sshKeyEnclaveDeviceBoundIos
                : s.sshKeyEnclaveDeviceBound,
            style: AppFonts.inter(
              fontSize: AppFonts.xs,
              color: AppTheme.orange,
            ),
          ),
        ),
        if (disabled) ...[
          const SizedBox(height: AppSpacing.md),
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
        ],
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _labelCtrl,
          enabled: !disabled,
          autofocus: !disabled,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: s.sshKeyEnclaveWizardLabelHint,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          s.sshKeyEnclaveAlgorithm,
          style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
        const SizedBox(height: AppSpacing.lg),
        // `RadioGroup` ancestor manages the selected value for the
        // two child radios — replaces the per-tile `groupValue` /
        // `onChanged` props deprecated in Flutter 3.32. Disabled
        // state passes a `null` `onChanged` so the children render
        // greyed-out and reject taps.
        RadioGroup<rust_enclave.DbEnclaveAuthPolicy>(
          groupValue: _policy,
          onChanged: (rust_enclave.DbEnclaveAuthPolicy? v) {
            if (disabled || v == null) return;
            setState(() => _policy = v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<rust_enclave.DbEnclaveAuthPolicy>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_enclave.DbEnclaveAuthPolicy.biometryCurrentSet,
                title: Text(
                  s.sshKeyEnclaveTouchIdRequired,
                  style: AppFonts.inter(fontSize: AppFonts.sm),
                ),
              ),
              RadioListTile<rust_enclave.DbEnclaveAuthPolicy>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_enclave.DbEnclaveAuthPolicy.userPresence,
                title: Text(
                  s.sshKeyEnclavePasscodeFallback,
                  style: AppFonts.inter(fontSize: AppFonts.sm),
                ),
              ),
            ],
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
    final line = _result?.authorizedKeysLine ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSelectionArea(
          child: Text(
            s.sshKeyAuthorizedKeysHint,
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
      case EnclaveWizardStep.probing:
      case EnclaveWizardStep.generating:
        return [AppButton.cancel(onTap: _doCancel)];
      case EnclaveWizardStep.configure:
        return [
          AppButton.cancel(onTap: _doCancel),
          AppButton.primary(
            label: s.sshKeyGenerateCta,
            onTap: _canGenerate ? _doGenerate : null,
          ),
        ];
      case EnclaveWizardStep.complete:
        return [AppButton.primary(label: s.close, onTap: _doDone)];
    }
  }

  String _availabilityReason(S s, rust_enclave.DbEnclaveAvailability a) {
    return switch (a) {
      rust_enclave.DbEnclaveAvailability_Available() => '',
      rust_enclave.DbEnclaveAvailability_CodeSignRequired() =>
        s.sshKeyHardwareUnavailableSe,
      rust_enclave.DbEnclaveAvailability_NoSecureEnclave() =>
        s.sshKeyHardwareUnavailableTitle,
      rust_enclave.DbEnclaveAvailability_PasscodeNotSet() =>
        s.sshKeyHardwareUnavailableTitle,
      rust_enclave.DbEnclaveAvailability_Other(:final field0) => field0,
      rust_enclave.DbEnclaveAvailability_UnsupportedPlatform() =>
        s.sshKeyHardwareUnavailableTitle,
    };
  }
}

// ── Apple Secure Enclave row badge ───────────────────────────────────

/// Hardware badge variant for `backend = 'enclave'` rows in the key
/// manager. Renders the localized `sshKeyEnclaveBadge` pill with a
/// tap affordance that surfaces the device-bound warning + the
/// captured algorithm string.
///
/// Visual contract mirrors the PKCS#11 / FIDO2 badges so the row
/// tail reads consistently when multiple hardware-backed rows
/// co-exist on the key manager list.
class EnclaveBadge extends StatelessWidget {
  final String label;
  const EnclaveBadge({super.key, required this.label});

  void _showInfo(BuildContext context) {
    final s = S.of(context);
    final iosCopy = Theme.of(context).platform == TargetPlatform.iOS;
    AppDialog.show<void>(
      context,
      builder: (ctx) => AppDialog(
        title: s.sshKeyEnclaveBadge,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSelectionArea(
              child: Text(
                s.sshKeyHardwareBoundExplainer,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppSelectionArea(
              child: Text(
                iosCopy
                    ? s.sshKeyEnclaveDeviceBoundIos
                    : s.sshKeyEnclaveDeviceBound,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.orange,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppSelectionArea(
              child: Text(
                s.sshKeyEnclaveAlgorithm,
                style: AppFonts.mono(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgDim,
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
              Icon(Icons.shield_outlined, size: 12, color: AppTheme.green),
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
