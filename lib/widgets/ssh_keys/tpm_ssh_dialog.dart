import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../src/rust/api/tpm_ssh.dart' as rust_tpm;
import '../../theme/app_theme.dart';
import '../core/app_dialog.dart';
import '../core/app_selection_area.dart';
import 'hardware_key_badge.dart';
import 'hardware_key_wizard.dart';

/// Bundled outcome of a successful TPM SSH wizard run. Returned via
/// `Navigator.pop` so the caller can refresh its key listing without
/// reaching back into FRB.
class TpmSshResult {
  final String keyId;
  final String label;
  final String authorizedKeysLine;
  final bool silentTpm;
  const TpmSshResult({
    required this.keyId,
    required this.label,
    required this.authorizedKeysLine,
    required this.silentTpm,
  });
}

/// Backend abstraction so widget tests can drive each wizard step
/// without booting FRB. Mirrors [HelloBackend] one file over.
abstract class TpmBackend {
  const TpmBackend();

  Future<rust_tpm.DbTpmSshProbeResult> probe();

  Future<rust_tpm.DbTpmSshImportResult> generate({
    required String label,
    required rust_tpm.DbTpmSshAlgorithm algo,
    String? pin,
    required rust_tpm.DbTpmSshStorageMode storage,
    int? persistentHandle,
    required bool silentTpm,
  });

  Future<String> importBlob({required List<int> blob, required String label});

  Future<String> importBlobFromPath({
    required String path,
    required String label,
  });
}

class TpmFrbBackend extends TpmBackend {
  const TpmFrbBackend();

  @override
  Future<rust_tpm.DbTpmSshProbeResult> probe() => rust_tpm.tpmSshProbe();

  @override
  Future<rust_tpm.DbTpmSshImportResult> generate({
    required String label,
    required rust_tpm.DbTpmSshAlgorithm algo,
    String? pin,
    required rust_tpm.DbTpmSshStorageMode storage,
    int? persistentHandle,
    required bool silentTpm,
  }) {
    return rust_tpm.tpmSshGenerate(
      args: rust_tpm.DbTpmSshGenerateArgs(
        label: label,
        algo: algo,
        pin: pin,
        storage: storage,
        persistentHandle: persistentHandle,
        silentTpm: silentTpm,
      ),
    );
  }

  @override
  Future<String> importBlob({required List<int> blob, required String label}) =>
      rust_tpm.tpmSshImportBlob(blob: blob, label: label);

  @override
  Future<String> importBlobFromPath({
    required String path,
    required String label,
  }) => rust_tpm.tpmSshImportBlobFromPath(path: path, label: label);
}

/// TPM 2.0 SSH key wizard. Walks the shared [HardwareKeyWizardMixin]
/// ladder:
///
/// 1. Probe — fires on open. If `/dev/tpmrm0` is missing, no PCP on
///    Windows, or the user isn't in the `tss` group, the configure step
///    renders disabled with the matching localized reason.
/// 2. Configure — algorithm radio (P-256 / RSA-2048), label, optional
///    PIN, storage radio (Linux only).
/// 3. Generate — fires the TPM round trip in `spawn_blocking`; success
///    surfaces the `authorized_keys` line for paste.
class TpmSshDialog extends StatefulWidget {
  final TpmBackend backend;

  /// Initial label to seed the wizard's label field. Used by the
  /// key-manager stub re-generate flow so the user lands on a form
  /// that already carries the migrated stub's name; `null` means
  /// the wizard starts with an empty label.
  final String? initialLabel;

  const TpmSshDialog({
    super.key,
    this.backend = const TpmFrbBackend(),
    this.initialLabel,
  });

  static Future<TpmSshResult?> show(
    BuildContext context, {
    TpmBackend backend = const TpmFrbBackend(),
    String? initialLabel,
  }) {
    return AppDialog.show<TpmSshResult>(
      context,
      builder: (_) =>
          TpmSshDialog(backend: backend, initialLabel: initialLabel),
    );
  }

  @override
  State<TpmSshDialog> createState() => _TpmSshDialogState();
}

class _TpmSshDialogState extends State<TpmSshDialog>
    with HardwareKeyWizardMixin {
  rust_tpm.DbTpmSshProbeResult? _probe;
  rust_tpm.DbTpmSshAlgorithm _algo = rust_tpm.DbTpmSshAlgorithm.ecdsaP256;
  rust_tpm.DbTpmSshStorageMode _storage = rust_tpm.DbTpmSshStorageMode.blob;
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _pinConfirmCtrl = TextEditingController();
  bool _protectWithPin = false;
  TpmSshResult? _result;

  bool get _isLinux => Platform.isLinux;
  bool get _isWindows => Platform.isWindows;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  String wizardTitle(S s) => s.tpmSshTitle;

  @override
  String get wizardLogName => 'TpmSsh';

  @override
  String? get wizardInitialLabel => widget.initialLabel;

  @override
  String generatingLabel(S s) => s.tpmSshGenerating;

  @override
  Future<void> runProbe() async {
    _probe = await widget.backend.probe();
  }

  @override
  void onProbeFailure(Object error) {
    _probe = rust_tpm.DbTpmSshProbeResult.probeFailed;
  }

  bool get _isAvailable => _probe == rust_tpm.DbTpmSshProbeResult.available;

  bool get _pinValid {
    if (!_protectWithPin) return true;
    final a = _pinCtrl.text;
    final b = _pinConfirmCtrl.text;
    return a.isNotEmpty && a == b;
  }

  @override
  bool get canGenerate =>
      _isAvailable && labelCtrl.text.trim().isNotEmpty && _pinValid;

  @override
  Future<String?> runGenerate() async {
    final pin = _protectWithPin ? _pinCtrl.text : null;
    final result = await widget.backend.generate(
      label: labelCtrl.text.trim(),
      algo: _algo,
      pin: pin,
      storage: _storage,
      persistentHandle: null,
      // Windows always lands on the silent variant; Linux ignores the
      // flag. Wired here so the FRB call shape stays uniform.
      silentTpm: _isWindows,
    );
    _result = TpmSshResult(
      keyId: result.keyId,
      label: result.label,
      authorizedKeysLine: result.authorizedKeysLine,
      silentTpm: _isWindows,
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
    final probe = _probe!;
    final disabled = !_isAvailable;
    final reason = _availabilityReason(s, probe);
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
        // Silent-warning banner on Windows — the silent variant signs
        // without firing any Hello / PIN prompt. The user needs to know
        // this before opting in.
        if (!disabled && _isWindows) ...[
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
                s.tpmSshSilentWarning,
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
          decoration: InputDecoration(labelText: s.tpmSshLabel),
        ),
        const SizedBox(height: AppSpacing.lg),
        RadioGroup<rust_tpm.DbTpmSshAlgorithm>(
          groupValue: _algo,
          onChanged: (rust_tpm.DbTpmSshAlgorithm? v) {
            if (disabled || v == null) return;
            setState(() => _algo = v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<rust_tpm.DbTpmSshAlgorithm>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_tpm.DbTpmSshAlgorithm.ecdsaP256,
                title: Text(
                  s.tpmSshAlgEcdsa,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
              RadioListTile<rust_tpm.DbTpmSshAlgorithm>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: rust_tpm.DbTpmSshAlgorithm.rsa2048,
                title: Text(
                  s.tpmSshAlgRsa,
                  style: AppFonts.mono(fontSize: AppFonts.sm),
                ),
              ),
            ],
          ),
        ),
        // PIN policy — Linux only. Windows silent variant has no PIN
        // concept; the Hello-gated wizard handles the PIN-on-every-sign
        // case via its own dialog.
        if (_isLinux) ...[
          const SizedBox(height: AppSpacing.lg),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              s.tpmSshPinProtect,
              style: AppFonts.inter(fontSize: AppFonts.sm),
            ),
            value: _protectWithPin,
            onChanged: disabled
                ? null
                : (v) => setState(() => _protectWithPin = v ?? false),
          ),
          if (_protectWithPin) ...[
            TextField(
              controller: _pinCtrl,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.tpmSshPinProtect),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _pinConfirmCtrl,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: s.tpmSshPinProtect),
            ),
            if (!_pinValid &&
                _pinCtrl.text.isNotEmpty &&
                _pinConfirmCtrl.text.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.tpmSshPinMismatch,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  color: AppTheme.red,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              s.tpmSshPinLockoutWarning,
              style: AppFonts.inter(
                fontSize: AppFonts.xs,
                color: AppTheme.orange,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Storage policy radio — Linux only. Windows CNG always uses
          // the PCP persistent store.
          RadioGroup<rust_tpm.DbTpmSshStorageMode>(
            groupValue: _storage,
            onChanged: (v) {
              if (disabled || v == null) return;
              setState(() => _storage = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<rust_tpm.DbTpmSshStorageMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: rust_tpm.DbTpmSshStorageMode.blob,
                  title: Text(
                    s.tpmSshStorageBlob,
                    style: AppFonts.inter(fontSize: AppFonts.sm),
                  ),
                ),
                RadioListTile<rust_tpm.DbTpmSshStorageMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: rust_tpm.DbTpmSshStorageMode.persistentHandle,
                  title: Text(
                    s.tpmSshStorageHandle,
                    style: AppFonts.inter(fontSize: AppFonts.sm),
                  ),
                  subtitle: Text(
                    s.tpmSshStorageHandleHelp,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

  String _availabilityReason(S s, rust_tpm.DbTpmSshProbeResult probe) {
    return switch (probe) {
      rust_tpm.DbTpmSshProbeResult.available => '',
      rust_tpm.DbTpmSshProbeResult.deviceNodeMissing =>
        s.tpmSshUnavailableFwDisabled,
      rust_tpm.DbTpmSshProbeResult.noPermission =>
        s.tpmSshUnavailableNoPermission,
      rust_tpm.DbTpmSshProbeResult.binaryMissing =>
        s.tpmSshUnavailableFwDisabled,
      rust_tpm.DbTpmSshProbeResult.probeFailed => s.tpmSshUnavailableFwDisabled,
      rust_tpm.DbTpmSshProbeResult.unsupported => s.tpmSshUnavailable,
    };
  }
}

/// Pick a `.tpm` file from disk and forward the bytes through the
/// FRB import path. Helper exposed for the key manager's "Import
/// .tpm" toolbar entry.
class TpmImportHelper {
  final TpmBackend backend;
  const TpmImportHelper({this.backend = const TpmFrbBackend()});

  /// Returns the new DB row id on success, `null` if the user
  /// cancelled the picker. Errors surface to the caller.
  Future<String?> pickAndImport(BuildContext context) async {
    final s = S.of(context);
    final picked = await FilePicker.pickFiles(
      dialogTitle: s.tpmSshImportTitle,
      allowMultiple: false,
      type: FileType.any,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.single;
    final label = file.name.replaceAll(RegExp(r'\.tpm$'), '');
    // Prefer the path variant when available — keeps the blob
    // bytes Rust-side under the FRB size cap. Mobile pickers
    // surface only in-memory bytes (no `path`), so the byte
    // variant remains the fallback there.
    if (file.path != null) {
      return backend.importBlobFromPath(path: file.path!, label: label);
    }
    if (file.bytes != null) {
      return backend.importBlob(blob: file.bytes!, label: label);
    }
    return null;
  }
}

/// TPM SSH row badge for `backend = 'tpm'` key-manager rows. A thin
/// [HardwareKeyBadge] caller — the blue memory-chip pill with a tap
/// popover surfacing the provider / persistent handle + silent / PIN
/// caveats.
class TpmBadge extends StatelessWidget {
  final String label;
  final String? provider;
  final int? persistentHandle;
  final bool pinRequired;
  final bool silent;
  const TpmBadge({
    super.key,
    required this.label,
    this.provider,
    this.persistentHandle,
    this.pinRequired = false,
    this.silent = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final prov = provider;
    final handle = persistentHandle;
    return HardwareKeyBadge(
      label: label,
      color: AppTheme.blue,
      icon: Icons.memory,
      info: HardwareKeyBadgeInfo(
        title: s.tpmSshBadge,
        lines: [
          HardwareKeyInfoLine(s.sshKeyHardwareBoundExplainer),
          if (prov != null && prov.isNotEmpty) HardwareKeyInfoLine(prov),
          if (handle != null)
            HardwareKeyInfoLine(
              '0x${handle.toRadixString(16).padLeft(8, '0')}',
            ),
          if (silent) HardwareKeyInfoLine.warn(s.tpmSshSilentWarning),
          if (pinRequired) HardwareKeyInfoLine.warn(s.tpmSshPinLockoutWarning),
        ],
      ),
    );
  }
}
