import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/hardware_tier_vault.dart' as rust_vault;
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_dialog.dart';
import 'styled_form_field.dart';

/// Outcome surfaced by [HardwarePasswordSetupWizard.show].
enum HardwarePasswordWizardOutcome {
  /// Vault re-sealed under the user's new password and the marker
  /// cleared. Caller resumes the regular Hardware-tier unlock path —
  /// the new password is what the next unlock dialog accepts.
  resealed,

  /// User chose to wipe and start over. Caller fires its wipe-and-
  /// restart cascade (`WipeAllService.wipeAll` + first-launch wizard).
  wipeRequested,
}

/// Re-seal call signature. Lets tests substitute a deterministic stub
/// for the FRB shim — production wraps `hardwareTierVaultResealWithPassword`
/// + `hardwareTierVaultClearPasswordSetMarker`.
typedef HardwareResealCall =
    Future<void> Function({
      required String supportDir,
      required String newPassword,
    });

/// Two-step bootstrap wizard shown when the v6 → v7 migration left a
/// Hardware-tier install with the wrapped key sealed under the empty
/// PIN-HMAC. Step 1 explains the situation and offers a wipe-out
/// escape hatch; step 2 collects a new master password and asks Rust
/// to re-seal the existing DB key under it.
///
/// The widget owns no persistent state — its `_disposed` flag is the
/// only lifecycle bit. Bytes flow through one `String` field and one
/// FRB hop; once `Navigator.pop` runs the field controllers are
/// disposed and the typed password is GC-eligible.
class HardwarePasswordSetupWizard extends StatefulWidget {
  /// Directory the FRB shims read the marker / vault / salt out of.
  /// Caller hands its resolved `getApplicationSupportDirectory()`
  /// path so the wizard does not re-probe — bootstrap already did.
  final String supportDir;

  /// Production hook. The default routes through the real FRB shims;
  /// tests override with a deterministic stub.
  final HardwareResealCall reseal;

  /// Default production reseal — calls `reseal_with_password` then
  /// `clear_password_set_marker`. Tests override to drive failure /
  /// success branches without the platform vault.
  static Future<void> _productionReseal({
    required String supportDir,
    required String newPassword,
  }) async {
    await rust_vault.hardwareTierVaultResealWithPassword(
      supportDir: supportDir,
      newPassword: newPassword,
    );
    await rust_vault.hardwareTierVaultClearPasswordSetMarker(
      supportDir: supportDir,
    );
  }

  const HardwarePasswordSetupWizard({
    super.key,
    required this.supportDir,
    this.reseal = _productionReseal,
  });

  /// Surface the wizard above the current navigator. Resolves to
  /// `null` only when the navigator is unmounted between the show
  /// call and the user's choice; in production bootstrap that path
  /// re-renders the wizard on the next frame.
  static Future<HardwarePasswordWizardOutcome?> show(
    BuildContext context, {
    required String supportDir,
    HardwareResealCall? reseal,
  }) {
    return showDialog<HardwarePasswordWizardOutcome>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => HardwarePasswordSetupWizard(
        supportDir: supportDir,
        reseal: reseal ?? _productionReseal,
      ),
    );
  }

  @override
  State<HardwarePasswordSetupWizard> createState() =>
      _HardwarePasswordSetupWizardState();
}

class _HardwarePasswordSetupWizardState
    extends State<HardwarePasswordSetupWizard> {
  /// True on step-1 (explanatory). Flips to false when the user picks
  /// `t2MigrationContinue`; flips back never — step-2 either resolves
  /// the wizard or surfaces a retryable error.
  bool _onIntro = true;

  /// Two password fields — typed once, confirmed once. Disposed on
  /// the widget's `dispose`; the typed bytes never leave this State.
  final TextEditingController _passwordCtl = TextEditingController();
  final TextEditingController _confirmCtl = TextEditingController();

  /// True while the FRB reseal call is in flight. Disables the submit
  /// button + form fields so a double-tap can't fire a second reseal
  /// before the first resolves.
  bool _busy = false;

  /// Localized error surfaced under the form when reseal fails;
  /// `null` clears the row. Distinct from the `passwordsDoNotMatch`
  /// validator which fires on form submit.
  String? _resealError;

  @override
  void dispose() {
    _passwordCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return PopScope(
      canPop: false,
      child: AppDialog(
        title: _onIntro
            ? l10n.t2MigrationPromptTitle
            : l10n.t2MigrationSetPasswordTitle,
        maxWidth: 480,
        dismissible: false,
        content: _onIntro ? _buildIntro(l10n) : _buildPasswordStep(l10n),
        actions: _onIntro ? _introActions(l10n) : _passwordActions(l10n),
      ),
    );
  }

  Widget _buildIntro(S l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.t2MigrationPromptBody,
          style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.md),
        ),
      ],
    );
  }

  Widget _buildPasswordStep(S l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.t2MigrationSetPasswordBody,
          style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.md),
        ),
        const SizedBox(height: AppSpacing.md),
        StyledFormField(
          label: l10n.masterPasswordLabel,
          controller: _passwordCtl,
          obscure: true,
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        StyledFormField(
          label: l10n.confirmPassword,
          controller: _confirmCtl,
          obscure: true,
        ),
        if (_resealError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _resealError!,
            style: TextStyle(color: AppTheme.red, fontSize: AppFonts.sm),
          ),
        ],
      ],
    );
  }

  List<Widget> _introActions(S l10n) => [
    AppButton.destructive(
      label: l10n.t2MigrationWipeAndRestart,
      onTap: _busy ? null : _onWipeRequested,
    ),
    AppButton.primary(
      label: l10n.t2MigrationContinue,
      onTap: _busy ? null : _onAdvanceToPasswordStep,
    ),
  ];

  List<Widget> _passwordActions(S l10n) => [
    AppButton.destructive(
      label: l10n.t2MigrationWipeAndRestart,
      onTap: _busy ? null : _onWipeRequested,
    ),
    AppButton.primary(
      label: l10n.t2MigrationContinue,
      onTap: _busy ? null : _onSubmitPassword,
    ),
  ];

  void _onAdvanceToPasswordStep() {
    setState(() {
      _onIntro = false;
      _resealError = null;
    });
  }

  void _onWipeRequested() {
    Navigator.of(context).pop(HardwarePasswordWizardOutcome.wipeRequested);
  }

  Future<void> _onSubmitPassword() async {
    final pw = _passwordCtl.text;
    final confirm = _confirmCtl.text;
    final l10n = S.of(context);
    if (pw.isEmpty) {
      // The FRB shim also short-circuits an empty payload — checking
      // up front saves the round-trip and lets the user see the
      // mismatch message synchronously.
      setState(() => _resealError = l10n.t2MigrationResealFailed);
      return;
    }
    if (pw != confirm) {
      setState(() => _resealError = l10n.passwordsDoNotMatch);
      return;
    }
    setState(() {
      _busy = true;
      _resealError = null;
    });
    try {
      await widget.reseal(supportDir: widget.supportDir, newPassword: pw);
    } catch (e) {
      AppLogger.instance.log(
        'Hardware-tier reseal failed: $e',
        name: 'HardwareReseal',
        error: e,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _resealError = l10n.t2MigrationResealFailed;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(HardwarePasswordWizardOutcome.resealed);
  }
}
