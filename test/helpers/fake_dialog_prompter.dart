import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:letsflutssh/app/security_dialog_prompter.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/widgets/db_corrupt_dialog.dart';
import 'package:letsflutssh/widgets/security_setup_dialog.dart';
import 'package:letsflutssh/widgets/tier_reset_dialog.dart';

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

  int wizardCalls = 0;
  int corruptCalls = 0;
  int tierResetCalls = 0;
  int masterPasswordCalls = 0;

  FakeSecurityDialogPrompter({
    this.wizardResult = const SecuritySetupResult(),
    this.corruptChoice = DbCorruptChoice.exitApp,
    this.tierResetChoice = TierResetChoice.exitApp,
    this.masterPasswordResult,
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
}
