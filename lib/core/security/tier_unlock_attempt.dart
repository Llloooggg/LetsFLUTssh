import '../../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;

/// Dart-side outcome of a single dialog/verify cycle through one
/// of the per-tier unlock orchestrators (`tier_unlock_keychain_with_password`,
/// `tier_unlock_hardware`, `tier_unlock_paranoid`).
///
/// Mirrors [rust_orch.DbUnlockOutcome] but flattens the
/// `PluginError` / `Corruption` payloads into a single `error`
/// branch — the dialog UI doesn't differentiate between them
/// (both close the dialog and trigger the plaintext fallback in
/// the controller). The `cancelled` branch covers the inner
/// hardware-vault PIN sub-dialog dismiss; outer dialog stays
/// open for retry.
///
/// Plaintext discipline: this enum carries no key bytes. A
/// `staged` outcome means the orchestrator put the resolved key
/// in the SecretStore under
/// `tier_unlock_orchestrator::TIER_UNLOCK_KEY_ID`; the
/// [TierUnlockedListener] takes them via `secrets_take` on the
/// matching `BusEvent::TierStateChanged.unlocked` event and
/// hands them to drift. The dialog's verify callback returns
/// this enum; the dialog interprets it for UI state without ever
/// touching the bytes.
enum TierUnlockAttempt {
  /// Key staged in the SecretStore, cascade emitted, dialog
  /// should close with the success signal so the caller can
  /// await the post-unlock listener cascade.
  staged,

  /// Wrong password / PIN. Dialog stays open, decrements the
  /// rate limiter, surfaces the wrong-secret label.
  wrongSecret,

  /// Inner sub-dialog cancelled (e.g. hardware vault PIN
  /// sub-dialog dismissed without submitting). Outer dialog
  /// stays open — the user can re-attempt via the same flow.
  cancelled,

  /// Unrecoverable plugin / hardware / corruption error. Dialog
  /// should close with the failure signal so the caller falls
  /// back to plaintext / corruption recovery.
  error,
}

/// Map a Rust-side [rust_orch.DbUnlockOutcome] into the
/// Dart-side dialog outcome. Centralised so every dialog's
/// verify callback uses the same translation.
TierUnlockAttempt mapUnlockOutcome(rust_orch.DbUnlockOutcome o) {
  return switch (o) {
    rust_orch.DbUnlockOutcome_Staged() => TierUnlockAttempt.staged,
    rust_orch.DbUnlockOutcome_WrongSecret() => TierUnlockAttempt.wrongSecret,
    rust_orch.DbUnlockOutcome_Cancelled() => TierUnlockAttempt.cancelled,
    rust_orch.DbUnlockOutcome_PluginError() => TierUnlockAttempt.error,
    rust_orch.DbUnlockOutcome_Corruption() => TierUnlockAttempt.error,
  };
}
