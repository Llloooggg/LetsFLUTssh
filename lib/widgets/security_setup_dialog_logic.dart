/// Pure decision helpers extracted from `_SecuritySetupDialogState`.
/// Each function takes the dialog state as an explicit parameter
/// (no widget, no `BuildContext`, no Riverpod) so the wizard's
/// invariants can be exercised exhaustively against every
/// (tier × modifiers × capability) combination without booting a
/// widget tree.
library;

import '../core/security/security_bootstrap.dart' show WizardTier;

/// True when the biometric-modifier toggle should respond to taps.
///
/// Invariants enforced:
/// * `canOfferBiometric=false` → toggle locked (host has no
///   biometric API or no enrolment).
/// * Password modifier off → biometric is a UX shortcut for
///   re-typing the password; nothing to shortcut without one.
/// * Paranoid tier forbids biometric by design (see ARCHITECTURE
///   §3.6 → biometric ladder).
/// * Plaintext tier has no secret to gate.
bool wizardBiometricToggleEnabled({
  required WizardTier selected,
  required bool password,
  required bool canOfferBiometric,
}) {
  if (!canOfferBiometric) return false;
  if (!password) return false;
  if (selected == WizardTier.paranoid) return false;
  if (selected == WizardTier.plaintext) return false;
  return true;
}

/// True when the password-modifier toggle should respond to taps.
/// Paranoid and Hardware carry a mandatory password (toggle is
/// fixed on — Hardware's typed password is the primary gate,
/// biometric is the optional shortcut on top); plaintext has
/// nothing to gate (toggle is fixed off). Keychain is the only
/// tier where the user picks.
bool wizardPasswordToggleEnabled(WizardTier selected) {
  if (selected == WizardTier.paranoid) return false;
  if (selected == WizardTier.hardware) return false;
  if (selected == WizardTier.plaintext) return false;
  return true;
}

/// True when the wizard's secret-input field block (master password
/// for Paranoid, short bank-style password for T1/T2) must be filled
/// before [wizardCanSubmit] passes. Plaintext and passwordless
/// Keychain do not ask; Hardware always asks because T2 is
/// password-gated by contract.
bool wizardNeedsSecretInput({
  required WizardTier selected,
  required bool password,
}) {
  if (selected == WizardTier.paranoid) return true;
  if (selected == WizardTier.hardware) return true;
  if (selected == WizardTier.keychain && password) return true;
  return false;
}

/// True when the Continue button should be enabled. The only hard
/// front-gate today is the explicit acknowledgement on plaintext —
/// password / passphrase mismatch is checked in `_submit` because
/// that validation depends on both controllers being in sync, which
/// is fiddlier to wire to button state.
bool wizardCanSubmit({
  required WizardTier selected,
  required bool plaintextAcknowledged,
}) {
  if (selected == WizardTier.plaintext && !plaintextAcknowledged) return false;
  return true;
}

/// Resolve the "biometric requires password" invariant. The
/// dialog's UI permits the user to toggle biometric on while
/// password is off (the password row is below biometric in the
/// modifier panel and a click order can race the dependency rule);
/// `_submit` calls this helper to coerce `biometric=false` whenever
/// `password=false` so the [SecuritySetupResult] payload that
/// downstream apply consumes is internally consistent.
bool resolveBiometricInvariant({
  required bool password,
  required bool biometric,
}) {
  return password && biometric;
}
