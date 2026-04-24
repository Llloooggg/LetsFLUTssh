import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/security/master_password.dart';
import '../core/security/secure_key_storage.dart';
import '../widgets/db_corrupt_dialog.dart';
import '../widgets/security_setup_dialog.dart';
import '../widgets/tier_reset_dialog.dart';
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
/// `TierSecretUnlockDialog.show` (used for L2 unlock + first-launch L2
/// confirmation) has a more complex closure-based signature and is still
/// driven through its own null-context fallback; covering it needs
/// either a follow-up method here or a dedicated fixture.
abstract class SecurityDialogPrompter {
  /// First-launch tier wizard. Production wraps
  /// [SecuritySetupDialog.show]; tests return a canned [SecuritySetupResult]
  /// so the downstream `_applyFirstLaunchWizardResult` fan-out is
  /// exercisable without touching the widget tree.
  Future<SecuritySetupResult> showFirstLaunchWizard(
    BuildContext ctx, {
    required SecureKeyStorage keyStorage,
  });

  /// Corruption-recovery dialog. Production wraps [showDbCorruptDialog].
  /// Returns [DbCorruptChoice.exitApp] on null-navigator in production —
  /// tests override to drive the retry / reset / exit branches.
  Future<DbCorruptChoice> showDbCorrupt();

  /// Legacy-state-detected dialog. Production wraps [showTierResetDialog].
  Future<TierResetChoice> showTierReset();

  /// Paranoid master-password unlock dialog. Production wraps
  /// [showUnlockDialog]. Returns null on null-navigator / cancel / user
  /// chose reset.
  Future<Uint8List?> showMasterPasswordUnlock(MasterPasswordManager manager);
}

/// Production prompter — delegates to the real widget factories. The
/// constructor takes no arguments because the dialog helpers resolve
/// `navigatorKey.currentContext` internally; the class exists only so
/// tests can swap in a stub with the same shape.
class ProductionSecurityDialogPrompter implements SecurityDialogPrompter {
  const ProductionSecurityDialogPrompter();

  @override
  Future<SecuritySetupResult> showFirstLaunchWizard(
    BuildContext ctx, {
    required SecureKeyStorage keyStorage,
  }) => SecuritySetupDialog.show(ctx, keyStorage: keyStorage);

  @override
  Future<DbCorruptChoice> showDbCorrupt() => showDbCorruptDialog();

  @override
  Future<TierResetChoice> showTierReset() => showTierResetDialog();

  @override
  Future<Uint8List?> showMasterPasswordUnlock(MasterPasswordManager manager) =>
      showUnlockDialog(manager);
}
