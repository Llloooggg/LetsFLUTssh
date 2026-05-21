/// Pure decision helpers for `Pkcs11ImportDialog`. Extracted so the
/// wizard's state-machine invariants (which steps the user can reach,
/// whether the PIN step skips, which keys are selectable) can be
/// exercised without booting a widget tree.
///
/// The widget owns the controllers and FRB calls; the helpers here
/// only describe transitions and selectability.
library;

/// Linear wizard step ladder. The dialog walks these in order with a
/// single conditional skip ([pkcs11ShouldSkipPinStep]) when the
/// selected token has a built-in PIN pad — the in-app PIN field would
/// be ignored by the reader and asking for one harms the security UX.
enum Pkcs11WizardStep { module, token, pin, key, save }

/// Resolve the next step after [current] given the token-level PIN-pad
/// flag. The "Next" affordance from the module / token / pin steps
/// drives through this; the key step branches to `save` directly via
/// the Submit handler.
///
/// `protectedAuthPath = true` means the token has its own PIN pad
/// (`CKF_PROTECTED_AUTHENTICATION_PATH`); the in-app PIN field is
/// useless and we hop straight to the key picker.
Pkcs11WizardStep pkcs11NextStep(
  Pkcs11WizardStep current, {
  required bool protectedAuthPath,
}) {
  switch (current) {
    case Pkcs11WizardStep.module:
      return Pkcs11WizardStep.token;
    case Pkcs11WizardStep.token:
      return protectedAuthPath ? Pkcs11WizardStep.key : Pkcs11WizardStep.pin;
    case Pkcs11WizardStep.pin:
      return Pkcs11WizardStep.key;
    case Pkcs11WizardStep.key:
      return Pkcs11WizardStep.save;
    case Pkcs11WizardStep.save:
      return Pkcs11WizardStep.save;
  }
}

/// Resolve the previous step after [current] given the token-level
/// PIN-pad flag. Mirror of [pkcs11NextStep] so the Back affordance
/// retraces the same skip — without the mirror, a Back from `key` on
/// a PIN-pad token would drop into a hidden `pin` step.
Pkcs11WizardStep pkcs11PrevStep(
  Pkcs11WizardStep current, {
  required bool protectedAuthPath,
}) {
  switch (current) {
    case Pkcs11WizardStep.module:
      return Pkcs11WizardStep.module;
    case Pkcs11WizardStep.token:
      return Pkcs11WizardStep.module;
    case Pkcs11WizardStep.pin:
      return Pkcs11WizardStep.token;
    case Pkcs11WizardStep.key:
      return protectedAuthPath ? Pkcs11WizardStep.token : Pkcs11WizardStep.pin;
    case Pkcs11WizardStep.save:
      return Pkcs11WizardStep.key;
  }
}

/// True when the PIN step must be skipped on the transition out of the
/// token step. Wrapper kept for tests + call-site readability — the
/// flag rule itself is one expression but reaches the dialog in two
/// places (forward / back) and both must agree.
bool pkcs11ShouldSkipPinStep({required bool protectedAuthPath}) =>
    protectedAuthPath;

/// True when the row for an enumerated key should accept taps. The
/// Rust side flags GOST objects with a non-empty `disabledReason` —
/// SSH has no GOST wire suite, so showing the row keeps the user
/// oriented ("the token has these keys") but disables selection.
///
/// Empty `sshKeyType` doubles as a belt-and-braces gate: even if the
/// Rust side ever returns a non-empty `disabledReason` paired with a
/// usable type, we still refuse — every signable arm of the picker
/// must name a concrete short tag.
bool pkcs11KeyRowEnabled({
  required String sshKeyType,
  required String disabledReason,
}) {
  if (sshKeyType.isEmpty) return false;
  if (disabledReason.isNotEmpty) return false;
  return true;
}

/// Map a `pkcs11_list_keys` short tag to the algorithm short name +
/// detail (key size / curve) the row renders. Returns the empty pair
/// for unknown tags so an unrecognised future tag does not crash the
/// listing — the caller falls back to the raw `keyType` string.
({String algo, String detail}) pkcs11AlgoDetail(String sshKeyType) {
  switch (sshKeyType) {
    case 'rsa':
      return (algo: 'RSA', detail: '');
    case 'ecdsa-p256':
      return (algo: 'ECDSA', detail: 'P-256');
    case 'ecdsa-p384':
      return (algo: 'ECDSA', detail: 'P-384');
    case 'ecdsa-p521':
      return (algo: 'ECDSA', detail: 'P-521');
    case 'ed25519':
      return (algo: 'Ed25519', detail: '');
    default:
      return (algo: '', detail: '');
  }
}
