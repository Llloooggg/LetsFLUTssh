import 'package:flutter/material.dart';

import '../core/security/master_password.dart';
import '../core/security/password_rate_limiter.dart';
import '../core/security/tier_unlock_attempt.dart';
import '../widgets/db_corrupt_dialog.dart';
import '../widgets/security_setup_dialog.dart';
import '../widgets/tier_reset_dialog.dart';
import '../widgets/tier_secret_unlock_dialog.dart';
import 'security_dialogs.dart';

/// Seam for every blocking security dialog `SecurityInitController`
/// surfaces during bootstrap, first-launch, unlock, and corruption
/// recovery.
///
/// Production goes through [_ProductionSecurityDialogPrompter], which
/// forwards every call to the real dialog factory (`SecuritySetupDialog
/// .show` and the helpers in `security_dialogs.dart`). The contract is
/// identical to the raw function pointers — tests substitute a stub that
/// returns a canned result so the unlock + first-launch + reset paths
/// can be driven end-to-end under `testWidgets` / `tester.runAsync`
/// without needing to paint the dialog, tap a button, and await the
/// result.
///
/// The interface is intentionally narrow — it only captures the calls
/// whose default implementation would block on a real user interaction.
/// `TierSecretUnlockDialog.show` (used for T1+pw unlock + first-launch T1+pw
/// confirmation) has a more complex closure-based signature and is still
/// driven through its own null-context fallback; covering it needs
/// either a follow-up method here or a dedicated fixture.
abstract class SecurityDialogPrompter {
  /// First-launch tier wizard. Production wraps
  /// [SecuritySetupDialog.show]; tests return a canned [SecuritySetupResult]
  /// so the downstream `_applyFirstLaunchWizardResult` fan-out is
  /// exercisable without touching the widget tree.
  Future<SecuritySetupResult> showFirstLaunchWizard(BuildContext ctx);

  /// Corruption-recovery dialog. Production wraps [showDbCorruptDialog].
  /// Returns [DbCorruptChoice.exitApp] on null-navigator in production —
  /// tests override to drive the retry / reset / exit branches.
  Future<DbCorruptChoice> showDbCorrupt();

  /// Legacy-state-detected dialog. Production wraps [showTierResetDialog].
  Future<TierResetChoice> showTierReset();

  /// Paranoid master-password unlock dialog. Production wraps
  /// [showUnlockDialog]. Returns `true` when the user submitted the
  /// correct password (the orchestrator staged the derived key in
  /// the SecretStore + emitted the unlock cascade — caller awaits
  /// the `TierUnlockedListener`), `null` on cancel / forgot-
  /// password reset.
  Future<bool?> showMasterPasswordUnlock(MasterPasswordManager manager);

  /// Tier-secret unlock dialog (T1+pw short password / T2 hardware PIN).
  /// Production wraps [TierSecretUnlockDialog.show] — the widget owns
  /// the retry loop + rate-limit cooldown + biometric retry.
  ///
  /// Verify callback returns a [TierUnlockAttempt] which the dialog
  /// uses to drive UI state (retry on `wrongSecret`, close with
  /// success on `staged`, close with error on `error`). Pop value is
  /// `true` for staged-or-biometric success (caller awaits the post-
  /// unlock listener cascade), `false` for an unrecoverable verify
  /// error, `null` for dismiss / reset.
  Future<bool?> showTierSecretUnlock({
    required BuildContext ctx,
    required TierSecretUnlockLabels labels,
    required Future<TierUnlockAttempt> Function(String) verify,
    PasswordRateLimiter? rateLimiter,
    Future<bool> Function()? biometricUnlock,
    Future<void> Function()? onReset,
    bool autoTriggerBiometric = true,
  });
}

/// Production prompter — delegates to the real widget factories. The
/// constructor takes no arguments because the dialog helpers resolve
/// `navigatorKey.currentContext` internally; the class exists only so
/// tests can swap in a stub with the same shape.
class ProductionSecurityDialogPrompter implements SecurityDialogPrompter {
  const ProductionSecurityDialogPrompter();

  @override
  Future<SecuritySetupResult> showFirstLaunchWizard(BuildContext ctx) =>
      SecuritySetupDialog.show(ctx);

  @override
  Future<DbCorruptChoice> showDbCorrupt() => showDbCorruptDialog();

  @override
  Future<TierResetChoice> showTierReset() => showTierResetDialog();

  @override
  Future<bool?> showMasterPasswordUnlock(MasterPasswordManager manager) =>
      showUnlockDialog(manager);

  @override
  Future<bool?> showTierSecretUnlock({
    required BuildContext ctx,
    required TierSecretUnlockLabels labels,
    required Future<TierUnlockAttempt> Function(String) verify,
    PasswordRateLimiter? rateLimiter,
    Future<bool> Function()? biometricUnlock,
    Future<void> Function()? onReset,
    bool autoTriggerBiometric = true,
  }) => TierSecretUnlockDialog.show(
    ctx,
    labels: labels,
    verify: verify,
    rateLimiter: rateLimiter,
    biometric: biometricUnlock == null
        ? null
        : TierSecretUnlockBiometric(
            unlock: biometricUnlock,
            autoTrigger: autoTriggerBiometric,
          ),
    onReset: onReset,
  );
}
