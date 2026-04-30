import 'package:flutter/material.dart';
import 'package:letsflutssh/app/security_dialog_prompter.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/widgets/db_corrupt_dialog.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';
import 'package:letsflutssh/widgets/tier_reset_dialog.dart';
import 'package:letsflutssh/widgets/tier_secret_unlock_dialog.dart';

/// Scripted prompter for tests that need to drive the bootstrap /
/// first-launch / corruption paths end-to-end.
///
/// Every field is a canned answer the fake returns on the matching
/// method; counters let assertions pin exact call counts so a
/// refactor that accidentally double-fires a dialog (or drops one
/// entirely) surfaces as a failed expectation.
///
/// Example:
/// ```dart
/// final prompter = FakeSecurityDialogPrompter(
///   wizardResult: const SecuritySetupResult(tier: SecurityTier.paranoid),
/// );
/// final ctrl = SecurityInitController(..., dialogPrompter: prompter);
/// await ctrl.bootstrap();
/// expect(prompter.wizardCalls, 1);
/// ```
class FakeSecurityDialogPrompter implements SecurityDialogPrompter {
  /// Response for [showFirstLaunchWizard]. Defaults to plaintext so
  /// any un-customised wizard call flows through `_firstLaunchParanoid`-
  /// free branches.
  SecuritySetupResult wizardResult;

  /// Response for [showDbCorrupt]. Defaults to `exitApp` because the
  /// production null-nav fallback returns the same value — tests that
  /// want `resetAndSetupFresh` or `tryOtherTier` override explicitly.
  DbCorruptChoice corruptChoice;

  /// Response for [showTierReset]. Defaults to `exitApp` (production
  /// null-nav fallback).
  TierResetChoice tierResetChoice;

  /// Response for [showMasterPasswordUnlock]. `true` = success
  /// (controller awaits listener after dialog returns), `null` =
  /// user cancelled or chose reset.
  bool? masterPasswordResult;

  /// Simulated secret to pass through the real `verify` closure on a
  /// successful unlock. Production code's `verify` callbacks own the
  /// orchestrator dispatch + listener-cascade staging; the fake
  /// calls verify with this value so the side-effect actually runs.
  /// Null skips the verify call (simulating the user hitting Cancel
  /// before typing).
  String? tierSecretSimulatedInput;

  /// Override for the tier-secret dialog result. When null, the fake
  /// derives the result from whatever the real `verify` closure
  /// returned for [tierSecretSimulatedInput] — `staged` → `true`,
  /// `error` → `false`, anything else → `null`. Set explicitly for
  /// tests that want to bypass verify entirely (e.g. to pin a reset
  /// path without caring about the orchestrator dispatch).
  bool? tierSecretResult;

  /// When true, the fake invokes the `onReset` closure before
  /// returning null — so tests that drive the "user chose reset" path
  /// can observe the wipe side effects the real dialog triggers.
  bool fireOnReset = false;

  /// When true, the fake invokes the `biometricUnlock` closure
  /// instead of / before the manual-input path. The closure's return
  /// becomes the dialog result — matches the real dialog's autofire
  /// behaviour when biometric hardware is available.
  bool fireBiometricUnlock = false;

  int wizardCalls = 0;
  int corruptCalls = 0;
  int tierResetCalls = 0;
  int masterPasswordCalls = 0;
  int tierSecretCalls = 0;

  FakeSecurityDialogPrompter({
    this.wizardResult = const SecuritySetupResult(),
    this.corruptChoice = DbCorruptChoice.exitApp,
    this.tierResetChoice = TierResetChoice.exitApp,
    this.masterPasswordResult,
    this.tierSecretResult,
    this.tierSecretSimulatedInput,
    this.fireOnReset = false,
    this.fireBiometricUnlock = false,
  });

  @override
  Future<SecuritySetupResult> showFirstLaunchWizard(BuildContext ctx) async {
    wizardCalls++;
    return wizardResult;
  }

  @override
  Future<DbCorruptChoice> showDbCorrupt() async {
    corruptCalls++;
    return corruptChoice;
  }

  @override
  Future<TierResetChoice> showTierReset() async {
    tierResetCalls++;
    return tierResetChoice;
  }

  @override
  Future<bool?> showMasterPasswordUnlock(MasterPasswordManager manager) async {
    masterPasswordCalls++;
    return masterPasswordResult;
  }

  @override
  Future<bool?> showTierSecretUnlock({
    required BuildContext ctx,
    required TierSecretUnlockLabels labels,
    required Future<TierUnlockAttempt> Function(String) verify,
    PasswordRateLimiter? rateLimiter,
    Future<bool> Function()? biometricUnlock,
    Future<void> Function()? onReset,
    bool autoTriggerBiometric = true,
  }) async {
    tierSecretCalls++;
    // Biometric autofire runs first when configured, matching the
    // real dialog's first-frame behaviour.
    if (fireBiometricUnlock && biometricUnlock != null) {
      final bio = await biometricUnlock();
      if (bio) return true;
    }
    // Explicit override wins.
    if (tierSecretResult != null) return tierSecretResult;
    // No input simulated and no explicit result → user hit Cancel /
    // Reset. Optionally trigger onReset.
    if (tierSecretSimulatedInput == null) {
      if (fireOnReset && onReset != null) await onReset();
      return null;
    }
    // Run the real verify closure so its orchestrator + listener-
    // staging side-effects fire.
    final attempt = await verify(tierSecretSimulatedInput!);
    switch (attempt) {
      case TierUnlockAttempt.staged:
        return true;
      case TierUnlockAttempt.error:
        return false;
      case TierUnlockAttempt.wrongSecret:
      case TierUnlockAttempt.cancelled:
        if (fireOnReset && onReset != null) await onReset();
        return null;
    }
  }
}
