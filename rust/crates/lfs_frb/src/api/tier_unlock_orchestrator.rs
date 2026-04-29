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

/// KeychainWithPassword tier (L2) — verify the typed user
/// password through the on-disk gate, then read the DB
/// encryption key from the OS keychain. Emits cascade events
/// along the way; returns the key bytes on success or `None`
/// on wrong password / missing keychain entry / cancelled
/// prompt.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, biometric option); after the user submits the
/// password the caller invokes this orchestrator to drive the
/// verify + key-read + cascade emission in one FRB hop.
pub async fn tier_unlock_keychain_with_password(password: String) -> Option<Vec<u8>> {
    tier_unlock_orchestrator::unlock_keychain_with_password(password).await
}

/// Paranoid tier — derive the DB key from the typed master
/// password via Argon2id; emit cascade events along the way;
/// return the key bytes on success or `None` on a wrong
/// password / corrupted KDF record.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, "forgot password" reset path); after the user
/// submits the password the caller invokes this orchestrator
/// to drive the verify + cascade emission in one FRB hop.
///
/// Reads the support dir from the pinned singleton — caller
/// must have invoked `master_password_init` at app startup.
pub async fn tier_unlock_paranoid(password: String) -> Option<Vec<u8>> {
    tier_unlock_orchestrator::unlock_paranoid(password).await
}

/// Hardware tier (L3) — fan out a hardware-vault-unlock prompt
/// to the Dart subscriber + emit cascade events. `pin` is the
/// typed user secret for the password modifier; pass `None`
/// for the passwordless variant.
///
/// The Dart subscriber owns the platform call:
/// `HardwareTierVault.read(pin)` fans out to `tpm2-tools` on
/// Linux or the platform method channel on Apple / Android /
/// Windows. This orchestrator emits the cascade (UnlockRequested
/// → UnlockSucceeded / UnlockFailed) and returns the unsealed
/// key bytes for the Dart caller to hand to drift.
pub async fn tier_unlock_hardware(pin: Option<String>) -> Option<Vec<u8>> {
    tier_unlock_orchestrator::unlock_hardware(pin).await
}

/// Resolve a pending hardware-vault unlock with success bytes.
/// `Ok(Some(bytes))` on a successful unseal; the orchestrator
/// dispatches `UnlockSucceeded` against the tier machine.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_resolve(prompt_id: String, bytes: Vec<u8>) -> bool {
    use lfs_core::security::hardware_vault_unlock_prompt;
    let payload = if bytes.is_empty() { None } else { Some(bytes) };
    hardware_vault_unlock_prompt::instance().resolve(&prompt_id, Ok(payload))
}

/// Resolve a pending hardware-vault unlock with the
/// "wrong PIN / user cancel / hardware reported failure"
/// signal. `Ok(None)`. Orchestrator dispatches `UnlockFailed
/// { WrongSecret }`.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_resolve_wrong(prompt_id: String) -> bool {
    use lfs_core::security::hardware_vault_unlock_prompt;
    hardware_vault_unlock_prompt::instance().resolve(&prompt_id, Ok(None))
}

/// Resolve a pending hardware-vault unlock with a plugin
/// error message. Orchestrator dispatches `UnlockFailed
/// { PluginUnavailable { code: message } }`.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_resolve_error(prompt_id: String, message: String) -> bool {
    use lfs_core::security::hardware_vault_unlock_prompt;
    hardware_vault_unlock_prompt::instance().resolve(&prompt_id, Err(message))
}

/// Cancel a pending hardware-vault unlock without resolving —
/// used by the Dart subscriber when the unlock dialog is torn
/// down before the platform call returns. Idempotent on a
/// missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_cancel(prompt_id: String) {
    use lfs_core::security::hardware_vault_unlock_prompt;
    hardware_vault_unlock_prompt::instance().cancel(&prompt_id);
}
