import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../core/app_dialog.dart';
import '../core/app_icon_button.dart';
import '../core/app_selection_area.dart';
import '../core/toast.dart';

/// The four-stage ladder every hardware-key SSH wizard walks: probe the
/// chip when the dialog opens, let the user pick a label + algorithm,
/// fire the OS key-gen (which surfaces the biometric / PIN prompt), then
/// show the `authorized_keys` line to paste server-side.
enum HardwareKeyStep { probing, configure, generating, complete }

/// Shared scaffold for the Secure Enclave / Windows Hello / Android
/// Keystore / TPM SSH key wizards. Owns the [HardwareKeyStep] state
/// machine, the label field, the generate-error slot, the probing /
/// generating spinners, the completion view (`authorized_keys` line +
/// copy), and the Cancel / Generate / Close action ladder — the half of
/// each wizard that was identical four ways.
///
/// A concrete wizard mixes this in on its `State` and supplies only the
/// backend-specific pieces through the hooks below: the title, the probe
/// (+ its failure fallback), the configure-step body, the [canGenerate]
/// gate, the generate call, and the completion body. The configure body
/// keeps its own fields (probe result, algorithm, toggles) on the
/// concrete state and calls `setState` directly — the mixin shares the
/// `State`, so those fields and [labelCtrl] / [generateError] / [step]
/// live in one object.
mixin HardwareKeyWizardMixin<T extends StatefulWidget> on State<T> {
  /// Current position in the wizard ladder. Drives both the body and
  /// the action buttons.
  HardwareKeyStep step = HardwareKeyStep.probing;

  /// Label field shared by every backend. Disposed by the mixin; a
  /// concrete wizard with extra controllers (TPM's PIN fields) overrides
  /// `dispose`, frees its own, then calls `super.dispose()`.
  final TextEditingController labelCtrl = TextEditingController();

  /// Last generate failure, rendered under the configure form. Cleared
  /// when a fresh generate starts.
  String? generateError;

  String? _authorizedKeysLine;

  // ── hooks the concrete wizard implements ──

  /// Localized dialog title.
  String wizardTitle(S s);

  /// `AppLogger` tag + log-line prefix for this backend (`Enclave`,
  /// `Hello`, `Keystore`, `TpmSsh`).
  String get wizardLogName;

  /// Label to seed the field with — the key-manager stub re-generate
  /// flow passes the migrated stub's name; `null` / empty starts blank.
  String? get wizardInitialLabel;

  /// Run the FRB probe and store the per-backend availability onto the
  /// concrete state (plain assignment, no `setState` — the mixin wraps
  /// the call in one). Throwing routes to [onProbeFailure].
  Future<void> runProbe();

  /// Store the per-backend "probe failed" fallback availability so the
  /// configure step can render disabled-with-reason. Plain assignment —
  /// the mixin calls this inside its own `setState`.
  void onProbeFailure(Object error);

  /// The configure-step body: label field, algorithm radios, toggles,
  /// and the disabled-reason banner. Backend-specific.
  Widget buildConfigure(S s);

  /// Whether Generate is enabled — backend availability + a non-empty
  /// label + any backend-specific validity (PIN match, …).
  bool get canGenerate;

  /// Run the OS key-gen. Return the `authorized_keys` line on success
  /// (drives the move to [HardwareKeyStep.complete]); return `null` when
  /// the backend handled its own non-completing transition (e.g. the
  /// Keystore StrongBox-fallback prompt). Throw to surface the error and
  /// drop back to configure.
  Future<String?> runGenerate();

  /// The completion-step body. Most wizards return [authorizedKeysBox]
  /// verbatim; Keystore / Hello wrap it with a tier / software-gated
  /// note.
  Widget buildComplete(S s);

  /// Generating-spinner caption. Defaults to the generic "generating…"
  /// string; Keystore / TPM override with their own.
  String generatingLabel(S s) => s.sshKeyGenerateInProgress;

  /// Optional widget shown under the generating spinner (Hello's
  /// "approve the prompt" description).
  Widget? generatingExtra(S s) => null;

  @override
  void initState() {
    super.initState();
    final seed = wizardInitialLabel;
    if (seed != null && seed.isNotEmpty) labelCtrl.text = seed;
    _kickProbe();
  }

  @override
  void dispose() {
    labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _kickProbe() async {
    try {
      await runProbe();
      if (!mounted) return;
      setState(() => step = HardwareKeyStep.configure);
    } catch (e, st) {
      AppLogger.instance.log(
        '$wizardLogName probe failed: $e',
        name: wizardLogName,
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        onProbeFailure(e);
        step = HardwareKeyStep.configure;
      });
    }
  }

  /// Drive the generate flow: flip to the generating spinner, run the
  /// backend hook, then either complete or surface the error. Concrete
  /// wizards wire this to the Generate button.
  Future<void> runGenerateFlow() async {
    if (!canGenerate) return;
    setState(() {
      step = HardwareKeyStep.generating;
      generateError = null;
    });
    try {
      final line = await runGenerate();
      if (!mounted || line == null) return;
      setState(() {
        _authorizedKeysLine = line;
        step = HardwareKeyStep.complete;
      });
    } catch (e, st) {
      AppLogger.instance.log(
        '$wizardLogName generate failed: $e',
        name: wizardLogName,
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        generateError = e.toString();
        step = HardwareKeyStep.configure;
      });
    }
  }

  /// Pop the dialog with the concrete wizard's typed result.
  void finishWith(Object result) => Navigator.of(context).pop(result);

  void cancelWizard() => Navigator.of(context).pop();

  /// Re-enter the configure step without clearing the label — used by
  /// the Keystore StrongBox-fallback retry path.
  void backToConfigure() {
    if (!mounted) return;
    setState(() => step = HardwareKeyStep.configure);
  }

  Future<void> _copyAuthorizedKeysLine() async {
    final line = _authorizedKeysLine ?? '';
    if (line.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: line));
    if (!mounted) return;
    Toast.show(
      context,
      message: S.of(context).copiedToClipboard,
      level: ToastLevel.success,
    );
  }

  /// The `authorized_keys`-line panel shared by every completion step:
  /// the paste hint, then the monospace line with a copy affordance.
  /// Concrete `buildComplete` implementations compose around this.
  Widget authorizedKeysBox(S s) {
    final line = _authorizedKeysLine ?? '';
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

  /// Assemble the dialog. Concrete wizards return this straight from
  /// `build`, passing the per-step Close handler (which pops with the
  /// typed result).
  Widget buildWizard(S s, {required VoidCallback onDone}) {
    return AppDialog(
      title: wizardTitle(s),
      content: SizedBox(width: 520, child: _buildBody(s)),
      actions: _buildActions(s, onDone),
    );
  }

  Widget _buildBody(S s) {
    switch (step) {
      case HardwareKeyStep.probing:
        return const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case HardwareKeyStep.configure:
        return buildConfigure(s);
      case HardwareKeyStep.generating:
        final extra = generatingExtra(s);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: AppSpacing.md),
              Text(
                generatingLabel(s),
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.sm),
                extra,
              ],
            ],
          ),
        );
      case HardwareKeyStep.complete:
        return buildComplete(s);
    }
  }

  List<Widget> _buildActions(S s, VoidCallback onDone) {
    switch (step) {
      case HardwareKeyStep.probing:
      case HardwareKeyStep.generating:
        return [AppButton.cancel(onTap: cancelWizard)];
      case HardwareKeyStep.configure:
        return [
          AppButton.cancel(onTap: cancelWizard),
          AppButton.primary(
            label: s.sshKeyGenerateCta,
            onTap: canGenerate ? runGenerateFlow : null,
          ),
        ];
      case HardwareKeyStep.complete:
        return [AppButton.primary(label: s.close, onTap: onDone)];
    }
  }
}
