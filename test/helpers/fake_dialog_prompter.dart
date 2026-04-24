import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:letsflutssh/app/security_dialog_prompter.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
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

  /// Response for [showMasterPasswordUnlock]. Null = user cancelled or
  /// chose reset.
  Uint8List? masterPasswordResult;

  /// Simulated secret to pass through the real `verify` closure on a
  /// successful unlock. Production code's `verify` callbacks
  /// (L2 gate.verify + keyStorage.readKey, L3 vault.read) own the DB
  /// inject side-effect — the fake calls verify with this value so
  /// the inject actually runs. Null skips the verify call (simulating
  /// the user hitting Cancel before typing).
  String? tierSecretSimulatedInput;

  /// Override for the tier-secret dialog result. When null, the fake
  /// returns whatever the real `verify` closure produced for
  /// [tierSecretSimulatedInput] — the most faithful simulation since
  /// the verify closure carries the inject side effect. Set
  /// explicitly for tests that want to bypass verify (e.g. to pin a
  /// reset path without caring about the key).
  List<int>? tierSecretResult;

  /// When true, the fake invokes the `onReset` closure before
  /// returning null — so tests that drive the "user chose reset" path
  /// can observe the wipe side effects the real dialog triggers.
  bool fireOnReset = false;

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
  });

  @override
  Future<SecuritySetupResult> showFirstLaunchWizard(
    BuildContext ctx, {
    required SecureKeyStorage keyStorage,
  }) async {
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
  Future<Uint8List?> showMasterPasswordUnlock(
    MasterPasswordManager manager,
  ) async {
    masterPasswordCalls++;
    return masterPasswordResult;
  }

  @override
  Future<List<int>?> showTierSecretUnlock({
    required BuildContext ctx,
    required TierSecretUnlockLabels labels,
    required Future<List<int>?> Function(String) verify,
    PasswordRateLimiter? rateLimiter,
    Future<List<int>?> Function()? biometricUnlock,
    Future<void> Function()? onReset,
    bool autoTriggerBiometric = true,
  }) async {
    tierSecretCalls++;
    // Explicit override wins.
    if (tierSecretResult != null) return tierSecretResult;
    // No input simulated and no explicit result → user hit Cancel /
    // Reset. Optionally trigger onReset.
    if (tierSecretSimulatedInput == null) {
      if (fireOnReset && onReset != null) await onReset();
      return null;
    }
    // Run the real verify closure so its inject side effect fires.
    final result = await verify(tierSecretSimulatedInput!);
    if (result == null && fireOnReset && onReset != null) await onReset();
    return result;
  }
}
