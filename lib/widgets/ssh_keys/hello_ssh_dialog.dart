import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../src/rust/api/hello.dart' as rust_hello;
import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../core/app_selection_area.dart';
import 'hardware_key_badge.dart';
import 'hardware_key_wizard.dart';

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

/// Windows Hello SSH key wizard. Walks the shared
/// [HardwareKeyWizardMixin] ladder:
///
/// 1. Probe — fires on open. If Hello is not configured / no PCP
///    provider / non-Windows build, the configure step renders disabled
///    with the localized reason. On `SoftwareKsp` tier it prints an
///    honest "Software-gated" warning before Generate.
/// 2. Configure — algorithm radio (P-256 / P-384 / RSA-2048) + label.
/// 3. Generate — fires Windows Hello inside `NCryptFinalizeKey`, then
///    surfaces the `authorized_keys` line for the user to paste.
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

class _HelloSshDialogState extends State<HelloSshDialog>
    with HardwareKeyWizardMixin {
  rust_hello.DbHelloProbeResult? _probe;
  rust_hello.DbHelloAlgo _algo = rust_hello.DbHelloAlgo.ecdsaP256;
  HelloSshResult? _result;

  @override
  String wizardTitle(S s) => s.helloWizardTitle;

  @override
  String get wizardLogName => 'Hello';

  @override
  String? get wizardInitialLabel => widget.initialLabel;

  @override
  Future<void> runProbe() async {
    _probe = await widget.backend.probe();
  }

  @override
  void onProbeFailure(Object error) {
    _probe = rust_hello.DbHelloProbeResult.other(error.toString());
  }

  bool get _isAvailable => _probe is rust_hello.DbHelloProbeResult_Available;

  @override
  bool get canGenerate => _isAvailable && labelCtrl.text.trim().isNotEmpty;

  @override
  Future<String?> runGenerate() async {
    final result = await widget.backend.generate(
      label: labelCtrl.text.trim(),
      algo: _algo,
    );
    _result = HelloSshResult(
      keyId: result.keyId,
      label: result.label,
      authorizedKeysLine: result.authorizedKeysLine,
      tier: result.tier,
    );
    return result.authorizedKeysLine;
  }

  void _doDone() {
    final r = _result;
    if (r != null) finishWith(r);
  }

  @override
  Widget generatingExtra(S s) => Text(
    s.helloPromptDescription,
    textAlign: TextAlign.center,
    style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
  );

  @override
  Widget build(BuildContext context) {
    return buildWizard(S.of(context), onDone: _doDone);
  }

  String _softwareGatedNote(S s) =>
      '${s.sshKeyHardwareUnavailableTier} - ${s.helloSoftwareGatedWarning}';

  @override
  Widget buildComplete(S s) {
    final tier = _result?.tier ?? rust_hello.DbHelloTpmTier.hardware;
    if (tier != rust_hello.DbHelloTpmTier.softwareKsp) {
      return authorizedKeysBox(s);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _softwareGatedNote(s),
          style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.orange),
        ),
        const SizedBox(height: AppSpacing.md),
        authorizedKeysBox(s),
      ],
    );
  }

  @override
  Widget buildConfigure(S s) {
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
                _softwareGatedNote(s),
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
          controller: labelCtrl,
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

/// Windows Hello row badge for `backend = 'hello'` key-manager rows. A
/// thin [HardwareKeyBadge] caller — the blue shield pill with a tap
/// popover surfacing the device-bound warning + CNG persistent-key name.
class HelloBadge extends StatelessWidget {
  final String label;
  final String? credentialName;
  const HelloBadge({super.key, required this.label, this.credentialName});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final name = credentialName;
    return HardwareKeyBadge(
      label: label,
      color: AppTheme.blue,
      icon: Icons.shield_outlined,
      info: HardwareKeyBadgeInfo(
        title: s.helloBadge,
        lines: [
          HardwareKeyInfoLine(s.sshKeyHardwareBoundExplainer),
          HardwareKeyInfoLine.warn(s.sshKeyHelloDeviceBound),
          if (name != null && name.isNotEmpty) HardwareKeyInfoLine.mono(name),
        ],
      ),
    );
  }
}
