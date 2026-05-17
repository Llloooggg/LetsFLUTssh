import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/hello.dart' as rust_hello;
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'app_selection_area.dart';
import 'toast.dart';

/// Bundled outcome of a successful Windows Hello wizard run. Returned
/// via `Navigator.pop` so the caller can refresh its key listing
/// without reaching back into FRB.
class HelloSshResult {
  final String keyId;
  final String label;
  final String authorizedKeysLine;
  final rust_hello.DbHelloTpmTier tier;
  const HelloSshResult({
    required this.keyId,
    required this.label,
    required this.authorizedKeysLine,
    required this.tier,
  });
}

/// Backend abstraction so widget tests can drive each wizard step
/// without booting FRB. Mirrors [EnclaveBackend] one file over.
abstract class HelloBackend {
  const HelloBackend();

  Future<rust_hello.DbHelloProbeResult> probe();

  Future<rust_hello.DbHelloImportResult> generate({
    required String label,
    required rust_hello.DbHelloAlgo algo,
  });
}

class HelloFrbBackend extends HelloBackend {
  const HelloFrbBackend();

  @override
  Future<rust_hello.DbHelloProbeResult> probe() => rust_hello.helloSshProbe();

  @override
  Future<rust_hello.DbHelloImportResult> generate({
    required String label,
    required rust_hello.DbHelloAlgo algo,
  }) {
    return rust_hello.helloSshGenerate(
      args: rust_hello.DbHelloGenerateArgs(label: label, algo: algo),
    );
  }
}

/// Linear wizard step ladder. Same shape the Apple Secure Enclave
/// wizard ships — probe first, render disabled-with-reason when the
/// host cannot reach the chip, otherwise let the user pick the
/// algorithm + label and hit Generate.
enum HelloWizardStep { probing, configure, generating, complete }

/// Windows Hello SSH key wizard.
///
/// 1. Probe — fires on open. If Hello is not configured / no PCP
///    provider / non-Windows build, the dialog renders disabled
///    with the localized reason. On `SoftwareKsp` tier, prints an
///    honest "Software-gated" warning before Generate.
/// 2. Configure — algorithm radio (P-256 / P-384 / RSA-2048) and a
///    label field.
/// 3. Generate — fires Windows Hello at the OS layer inside
///    `NCryptFinalizeKey`. On success the wizard surfaces the
///    `authorized_keys` line for the user to paste on the server.
class HelloSshDialog extends StatefulWidget {
  /// Backend injection. Defaults to the FRB-backed implementation.
  final HelloBackend backend;

  /// Initial label to seed the wizard's label field. Used by the
  /// key-manager stub re-generate flow so the user lands on a form
  /// that already carries the migrated stub's name; `null` means
  /// the wizard starts with an empty label.
  final String? initialLabel;

  const HelloSshDialog({
    super.key,
    this.backend = const HelloFrbBackend(),
    this.initialLabel,
  });

  static Future<HelloSshResult?> show(
    BuildContext context, {
    HelloBackend backend = const HelloFrbBackend(),
    String? initialLabel,
  }) {
    return AppDialog.show<HelloSshResult>(
      context,
      builder: (_) =>
          HelloSshDialog(backend: backend, initialLabel: initialLabel),
    );
  }

  @override
  State<HelloSshDialog> createState() => _HelloSshDialogState();
}

class _HelloSshDialogState extends State<HelloSshDialog> {
  HelloWizardStep _step = HelloWizardStep.probing;
  rust_hello.DbHelloProbeResult? _probe;
  rust_hello.DbHelloAlgo _algo = rust_hello.DbHelloAlgo.ecdsaP256;
  final TextEditingController _labelCtrl = TextEditingController();
  String? _generateError;
  HelloSshResult? _result;

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
        _step = HelloWizardStep.configure;
      });
    } catch (e, st) {
      AppLogger.instance.log(
        'hello probe failed: $e',
        name: 'Hello',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _probe = rust_hello.DbHelloProbeResult.other(e.toString());
        _step = HelloWizardStep.configure;
      });
    }
  }

  bool get _isAvailable => _probe is rust_hello.DbHelloProbeResult_Available;

  bool get _canGenerate => _isAvailable && _labelCtrl.text.trim().isNotEmpty;

  Future<void> _doGenerate() async {
    if (!_canGenerate) return;
    final label = _labelCtrl.text.trim();
    setState(() {
      _step = HelloWizardStep.generating;
      _generateError = null;
    });
    try {
      final result = await widget.backend.generate(label: label, algo: _algo);
      if (!mounted) return;
      setState(() {
        _result = HelloSshResult(
          keyId: result.keyId,
          label: result.label,
          authorizedKeysLine: result.authorizedKeysLine,
          tier: result.tier,
        );
        _step = HelloWizardStep.complete;
      });
    } catch (e, st) {
      AppLogger.instance.log(
        'hello generate failed: $e',
        name: 'Hello',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _generateError = e.toString();
        _step = HelloWizardStep.configure;
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
      title: s.helloWizardTitle,
      content: SizedBox(width: 520, child: _buildBody(s)),
      actions: _buildActions(s),
    );
  }

  Widget _buildBody(S s) {
    switch (_step) {
      case HelloWizardStep.probing:
        return const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case HelloWizardStep.configure:
        return _buildConfigure(s);
      case HelloWizardStep.generating:
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                s.helloPromptDescription,
                textAlign: TextAlign.center,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgDim,
                ),
              ),
            ],
          ),
        );
      case HelloWizardStep.complete:
        return _buildComplete(s);
    }
  }

  Widget _buildConfigure(S s) {
    final probe = _probe!;
    final disabled = !_isAvailable;
    final reason = _availabilityReason(s, probe);
    final softwareGated =
        probe is rust_hello.DbHelloProbeResult_Available &&
        probe.tier == rust_hello.DbHelloTpmTier.softwareKsp;
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
            s.sshKeyHelloDeviceBound,
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
        if (softwareGated) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppTheme.orange.withValues(alpha: 0.08),
              borderRadius: AppTheme.radiusSm,
              border: Border.all(color: AppTheme.orange.withValues(alpha: 0.4)),
            ),
            child: AppSelectionArea(
              child: Text(
                '${s.sshKeyHardwareUnavailableTier} - ${s.helloSoftwareGatedWarning}',
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.orange,
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
          decoration: InputDecoration(labelText: s.helloWizardLabelHint),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Algorithm radio — the wizard exposes all three; P-384 is
        // probe-guarded only at create time (the FRB call surfaces
        // `helloP384NotSupported` when the TPM firmware refuses).
        RadioGroup<rust_hello.DbHelloAlgo>(
          groupValue: _algo,
          onChanged: (rust_hello.DbHelloAlgo? v) {
            if (disabled || v == null) return;
            setState(() => _algo = v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<rust_hello.DbHelloAlgo>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_hello.DbHelloAlgo.ecdsaP256,
                title: Text(
                  s.sshKeyHelloAlgorithmEcdsa256,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
              RadioListTile<rust_hello.DbHelloAlgo>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_hello.DbHelloAlgo.ecdsaP384,
                title: Text(
                  s.sshKeyHelloAlgorithmEcdsa384,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
              RadioListTile<rust_hello.DbHelloAlgo>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_hello.DbHelloAlgo.rsa2048,
                title: Text(
                  s.sshKeyHelloAlgorithmRsa,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
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
    final tier = _result?.tier ?? rust_hello.DbHelloTpmTier.hardware;
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
        if (tier == rust_hello.DbHelloTpmTier.softwareKsp) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${s.sshKeyHardwareUnavailableTier} - ${s.helloSoftwareGatedWarning}',
            style: AppFonts.inter(
              fontSize: AppFonts.xs,
              color: AppTheme.orange,
            ),
          ),
        ],
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
      case HelloWizardStep.probing:
      case HelloWizardStep.generating:
        return [AppButton.cancel(onTap: _doCancel)];
      case HelloWizardStep.configure:
        return [
          AppButton.cancel(onTap: _doCancel),
          AppButton.primary(
            label: s.sshKeyGenerateCta,
            onTap: _canGenerate ? _doGenerate : null,
          ),
        ];
      case HelloWizardStep.complete:
        return [AppButton.primary(label: s.close, onTap: _doDone)];
    }
  }

  String _availabilityReason(S s, rust_hello.DbHelloProbeResult probe) {
    return switch (probe) {
      rust_hello.DbHelloProbeResult_Available() => '',
      rust_hello.DbHelloProbeResult_ProviderUnavailable(:final field0) =>
        '${s.sshKeyHardwareUnavailableHello}\n$field0',
      rust_hello.DbHelloProbeResult_HelloNotConfigured() =>
        s.helloConfigureFirst,
      rust_hello.DbHelloProbeResult_Unsupported() =>
        s.sshKeyHardwareUnavailableTitle,
      rust_hello.DbHelloProbeResult_Other(:final field0) => field0,
    };
  }
}

// ── Windows Hello row badge ─────────────────────────────────────────

/// Hardware badge variant for `backend = 'hello'` rows in the key
/// manager. Renders the localized `helloBadge` pill with a tap
/// affordance that surfaces the device-bound warning + CNG
/// persistent-key name.
///
/// Visual contract mirrors the Pkcs11 / Enclave badges so the row
/// tail reads consistently when multiple hardware-backed rows
/// co-exist on the key manager list.
class HelloBadge extends StatelessWidget {
  final String label;
  final String? credentialName;
  const HelloBadge({super.key, required this.label, this.credentialName});

  void _showInfo(BuildContext context) {
    final s = S.of(context);
    AppDialog.show<void>(
      context,
      builder: (ctx) => AppDialog(
        title: s.helloBadge,
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
                s.sshKeyHelloDeviceBound,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.orange,
                ),
              ),
            ),
            if (credentialName != null && credentialName!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              AppSelectionArea(
                child: Text(
                  credentialName!,
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                ),
              ),
            ],
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
            color: AppTheme.blue.withValues(alpha: 0.16),
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.blue.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 12, color: AppTheme.blue),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.xxs,
                  color: AppTheme.blue,
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
