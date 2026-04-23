import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/security/master_password.dart';
import '../l10n/app_localizations.dart';
import '../widgets/db_corrupt_dialog.dart';
import '../widgets/tier_reset_dialog.dart';
import '../widgets/unlock_dialog.dart';
import 'navigator_key.dart';

/// Stateless security-dialog wrappers that all share the
/// `navigatorKey.currentContext` → mounted-check → show pattern.
///
/// Pulled out of `_LetsFLUTsshAppState` so the state class no
/// longer carries these 3-4 line helpers inline. Each function is
/// a thin wrapper over the corresponding dialog's `show()` factory
/// that resolves the navigator context synchronously (so
/// `use_build_context_synchronously` stays happy) and falls back
/// to a sensible "nothing happened" value when the context is
/// missing — which only occurs during teardown / cold-boot races
/// where the dialog cannot be meaningfully shown anyway.

/// Show the "tier reset required" dialog. Returns `exitApp` when
/// the navigator is not mounted.
Future<TierResetChoice> showTierResetDialog() {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return Future.value(TierResetChoice.exitApp);
  return TierResetDialog.show(ctx);
}

/// Show the "DB corruption — choose recovery path" dialog. Returns
/// `exitApp` when the navigator is not mounted.
Future<DbCorruptChoice> showDbCorruptDialog() {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return Future.value(DbCorruptChoice.exitApp);
  return DbCorruptDialog.show(ctx);
}

/// Show the master-password unlock dialog. Returns null when the
/// navigator is not mounted or the user cancels.
///
/// Separated from its caller so [BuildContext] is obtained
/// synchronously within this function, not across an async gap —
/// otherwise `use_build_context_synchronously` would trip at every
/// call site.
Future<Uint8List?> showUnlockDialog(MasterPasswordManager manager) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return Future.value(null);
  return UnlockDialog.show(ctx, manager: manager);
}

/// Localized reason string passed to the OS biometric prompt.
/// Falls back to the English literal when the navigator is not
/// mounted (no `S.of(ctx)` without a mounted context).
String localizedBiometricReason() {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return 'Unlock LetsFLUTssh';
  return S.of(ctx).biometricUnlockPrompt;
}
