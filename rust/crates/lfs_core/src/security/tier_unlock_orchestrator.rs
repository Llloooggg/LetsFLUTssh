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

use crate::bus::Event;
use crate::security::keychain_op_prompt::{self, KeychainOpKind};
use crate::security::tier_machine::{instance_dispatch, TierEvent, UnlockFailureReason};
use crate::security::SecurityTier;

/// Storage key for the L1 / L2 DB encryption key in the OS
/// keychain. Mirrors the Dart-era
/// `SecureKeyStorage._keyName` const — both implementations
/// must agree on the slot or an existing install would lose
/// access to its encrypted DB after the unlock cascade flips
/// to the orchestrator.
const ENCRYPTION_KEY_SLOT: &str = "letsflutssh_encryption_key";

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

/// Keychain tier (L1) — read the DB encryption key from the OS
/// keychain via the `keychain_op_prompt` registry, dispatch the
/// cascade events along the way, return the key bytes (or
/// `None` on missing-entry / plugin-error).
///
/// 1. Set tier to Keychain + dispatch `UnlockRequested`.
/// 2. Publish `KeychainOpPromptRequest { key:
///    ENCRYPTION_KEY_SLOT, op: Read }`; the Dart subscriber
///    calls `flutter_secure_storage.read` and resolves.
/// 3. On a hit, dispatch `UnlockSucceeded`; on miss, dispatch
///    `UnlockFailed { PluginUnavailable }` so the caller can
///    branch into the plaintext-fallback path.
///
/// Plaintext discipline: the key bytes cross FRB once on the
/// return value (the Dart caller hands them straight to drift
/// for the DB-open step). Same crossing as the Dart-era
/// `SecureKeyStorage.readKey()` flow this replaces.
pub async fn unlock_keychain() -> Option<Vec<u8>> {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);

    let prompt_id = generate_prompt_id();
    let receiver = keychain_op_prompt::instance().register(prompt_id.clone());
    crate::app::instance()
        .bus
        .publish(Event::KeychainOpPromptRequest {
            prompt_id: prompt_id.clone(),
            key: ENCRYPTION_KEY_SLOT.to_string(),
            op_wire_name: KeychainOpKind::Read.wire_name().to_string(),
            value_b64: None,
        });

    match receiver.await {
        Ok(Ok(Some(bytes))) if !bytes.is_empty() => {
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            Some(bytes)
        }
        Ok(_) => {
            // Missing entry / plugin returned None.
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "missing_keychain_entry".into(),
                    },
                },
            );
            None
        }
        Err(_) => {
            // Receiver dropped — Dart subscriber detached.
            keychain_op_prompt::instance().cancel(&prompt_id);
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "keychain_prompt_cancelled".into(),
                    },
                },
            );
            None
        }
    }
}

/// UUIDv4-shaped prompt id. Mirrors the same id-shape every
/// other prompt registry caller uses.
fn generate_prompt_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
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
