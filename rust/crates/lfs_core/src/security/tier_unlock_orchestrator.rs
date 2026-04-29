//! Per-tier unlock orchestrators that drive the
//! [`crate::security::tier_machine`] state machine through the
//! cascade `Locked → Unlocking → Unlocked`. Today the Dart
//! `SecurityInitController` (1167 LOC) owns the equivalent
//! Dart-side orchestration; this module is the staging ground
//! for the per-tier handlers that move into Rust under the
//! retire arc.
//!
//! The DB-open step itself (drift opens `letsflutssh.db` with
//! the resolved master key) stays Dart-side because drift is a
//! Dart ORM and can't be driven from Rust. The orchestrator's
//! contract is therefore "resolve the master key, stage it in
//! the SecretStore under a canonical id, advance the tier
//! machine, return the SecretStore id". The Dart subscriber
//! reads the staged key from the SecretStore once and feeds it
//! to drift.
//!
//! Per-tier orchestrators land one-by-one. Plaintext is the
//! simplest (no secret); each subsequent tier adds a layer of
//! Dart-plugin coordination via the existing typed prompt
//! registries (`credential_prompt`, `keychain_op_prompt`,
//! `biometric_probe_prompt`, etc.).

use crate::security::tier_machine::{instance_dispatch, TierEvent};
use crate::security::SecurityTier;

/// Plaintext tier — no secret, no plugin call, no user prompt.
/// Idempotent: re-entry while already `Unlocked` is a no-op
/// because both dispatches are state-guarded.
///
/// 1. Set the active tier to Plaintext + dispatch
///    `UnlockRequested` (state goes to `Unlocking`).
/// 2. Dispatch `UnlockSucceeded` (state goes to `Unlocked`,
///    publishes `BusEvent::TierStateChanged { wire_name:
///    "unlocked" }`).
///
/// The Dart subscriber sees the Unlocked event and runs the
/// drift-open step with an empty key (`AppDatabase` opens the
/// file as plaintext).
pub fn unlock_plaintext() {
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockRequested);
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockSucceeded);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::tier_machine::{instance, TierState};

    #[test]
    fn unlock_plaintext_self_advances_to_unlocked() {
        // Drive the singleton through the cascade. Other tests
        // in this binary touch the same singleton so we don't
        // assert from any starting state — only that the final
        // state is Unlocked under the Plaintext tier.
        unlock_plaintext();
        let m = instance();
        let g = m.lock().expect("tier machine mutex");
        assert_eq!(g.state(), TierState::Unlocked);
        assert_eq!(g.tier(), SecurityTier::Plaintext);
    }
}
