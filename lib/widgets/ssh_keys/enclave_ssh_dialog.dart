import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../src/rust/api/enclave.dart' as rust_enclave;
import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../core/app_selection_area.dart';
import 'hardware_key_badge.dart';
import 'hardware_key_wizard.dart';

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

/// Apple Secure Enclave SSH key wizard. Walks the shared
/// [HardwareKeyWizardMixin] ladder:
///
/// 1. Probe — runs at open. If the host can't reach the chip
///    (`errSecMissingEntitlement`, no SE silicon, no passcode), the
///    configure step renders disabled with the localized reason +
///    "Cancel". Configuration surfaces follow AGENTS.md's "disable,
///    don't hide" rule: the user is exploring what the app can do.
/// 2. Configure — label + auth-policy radio (Touch ID / Face ID
///    required vs passcode fallback).
/// 3. Generate — fires the OS biometric prompt at the
///    `enclaveSshGenerate` boundary, then surfaces the
///    `authorized_keys`-shaped public-key line with a copy affordance.
class EnclaveSshDialog extends StatefulWidget {
  /// Backend injection. Defaults to the FRB-backed implementation.
  final EnclaveBackend backend;

  /// Initial label to seed the wizard's label field. Used by the
  /// key-manager stub re-generate flow so the user lands on a form
  /// that already carries the migrated stub's name; `null` means
  /// the wizard starts with an empty label.
  final String? initialLabel;

  const EnclaveSshDialog({
    super.key,
    this.backend = const EnclaveFrbBackend(),
    this.initialLabel,
  });

  /// Convenience opener. Always returns whatever the dialog popped
  /// — `null` when the user dismissed without generating.
  static Future<EnclaveSshResult?> show(
    BuildContext context, {
    EnclaveBackend backend = const EnclaveFrbBackend(),
    String? initialLabel,
  }) {
    return AppDialog.show<EnclaveSshResult>(
      context,
      builder: (_) =>
          EnclaveSshDialog(backend: backend, initialLabel: initialLabel),
    );
  }

  @override
  State<EnclaveSshDialog> createState() => _EnclaveSshDialogState();
}

class _EnclaveSshDialogState extends State<EnclaveSshDialog>
    with HardwareKeyWizardMixin {
  rust_enclave.DbEnclaveAvailability? _availability;
  rust_enclave.DbEnclaveAuthPolicy _policy =
      rust_enclave.DbEnclaveAuthPolicy.biometryCurrentSet;
  EnclaveSshResult? _result;

  @override
  String wizardTitle(S s) => s.sshKeyEnclaveWizardTitle;

  @override
  String get wizardLogName => 'Enclave';

  @override
  String? get wizardInitialLabel => widget.initialLabel;

  @override
  Future<void> runProbe() async {
    _availability = await widget.backend.probe();
  }

  @override
  void onProbeFailure(Object error) {
    _availability = rust_enclave.DbEnclaveAvailability.other(error.toString());
  }

  @override
  bool get canGenerate {
    final a = _availability;
    if (a is! rust_enclave.DbEnclaveAvailability_Available) return false;
    return labelCtrl.text.trim().isNotEmpty;
  }

  @override
  Future<String?> runGenerate() async {
    final result = await widget.backend.generate(
      label: labelCtrl.text.trim(),
      policy: _policy,
    );
    _result = EnclaveSshResult(
      keyId: result.keyId,
      label: result.label,
      authorizedKeysLine: result.authorizedKeysLine,
    );
    return result.authorizedKeysLine;
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
  Widget buildComplete(S s) => authorizedKeysBox(s);

  @override
  Widget buildConfigure(S s) {
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
          controller: labelCtrl,
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
        // two child radios. Disabled state passes a `null` `onChanged`
        // so the children render greyed-out and reject taps.
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

/// Apple Secure Enclave row badge for `backend = 'enclave'` key-manager
/// rows. A thin [HardwareKeyBadge] caller — the green shield pill with a
/// tap popover surfacing the device-bound warning + captured algorithm.
class EnclaveBadge extends StatelessWidget {
  final String label;
  const EnclaveBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final iosCopy = Theme.of(context).platform == TargetPlatform.iOS;
    return HardwareKeyBadge(
      label: label,
      color: AppTheme.green,
      icon: Icons.shield_outlined,
      info: HardwareKeyBadgeInfo(
        title: s.sshKeyEnclaveBadge,
        lines: [
          HardwareKeyInfoLine(s.sshKeyHardwareBoundExplainer),
          HardwareKeyInfoLine.warn(
            iosCopy
                ? s.sshKeyEnclaveDeviceBoundIos
                : s.sshKeyEnclaveDeviceBound,
          ),
          HardwareKeyInfoLine.mono(s.sshKeyEnclaveAlgorithm),
        ],
      ),
    );
  }
}
