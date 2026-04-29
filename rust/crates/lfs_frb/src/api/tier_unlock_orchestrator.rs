//! FRB adapter for `lfs_core::security::tier_unlock_orchestrator`.
//!
//! Per-tier unlock orchestrators that drive the tier-machine
//! through `Locked → Unlocking → Unlocked` in a single FRB hop.
//! Replaces the per-step `tier_machine_set_tier` + `dispatch` +
//! `try_advance` chain the Dart `SecurityInitController` used
//! to walk three calls deep for the no-secret tiers.
//!
//! Sync — every orchestrator is a chain of mutex-guarded
//! transition-table lookups + bus publishes, sub-microsecond.

use lfs_core::security::tier_unlock_orchestrator;

/// Plaintext tier — no secret, no plugin call, no user prompt.
/// Dispatches `UnlockRequested` then `UnlockSucceeded` against
/// the singleton tier machine; subscribers see two
/// `BusEvent::TierStateChanged` events (`unlocking` →
/// `unlocked`) on the `tier` topic. The Dart caller still owns
/// the drift-open step (drift is a Dart ORM); the orchestrator
/// just fast-paths the cascade visibility.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_plaintext() {
    tier_unlock_orchestrator::unlock_plaintext();
}

/// Keychain tier (L1) — read the DB encryption key from the OS
/// keychain via the prompt registry; emit cascade events along
/// the way; return the key bytes on success or `None` on
/// missing entry / plugin error.
///
/// Async — round-trips through the bus to the Dart subscriber
/// for the `flutter_secure_storage.read` call. The receiver
/// completes as soon as the subscriber resolves the prompt;
/// the FRB worker frees during the wait so the unlock dialog
/// stays responsive.
pub async fn tier_unlock_keychain() -> Option<Vec<u8>> {
    tier_unlock_orchestrator::unlock_keychain().await
}
