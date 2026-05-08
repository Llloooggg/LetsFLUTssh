//! FRB adapter for `lfs_core::security::keychain_password_gate_actor`.
//!
//! The actor composes the T1+pw verify / set / clear / is_configured
//! pipeline directly against
//! [`lfs_os_security::secure_key_storage`] — no Dart-side bus
//! listener is in the unlock path. Each FRB function takes the
//! support-dir path the Dart caller already resolved via
//! `getApplicationSupportDirectory()` and forwards into the actor.

use std::path::Path;

use lfs_core::security::keychain_password_gate_actor as actor;

/// True when the T1+pw gate is configured on this install — disk
/// hash present AND keychain pepper present.
///
/// Returns `Ok(false)` on any non-fatal miss (file absent, pepper
/// absent, backend error). `Err` is reserved for unrecoverable
/// infra failures the caller can't recover from.
pub async fn keychain_password_gate_is_configured(support_dir: String) -> Result<bool, String> {
    actor::is_configured(Path::new(&support_dir)).await
}

/// Configure the gate with `password`. Generates fresh salt +
/// pepper, writes the disk hash atomically, then writes the
/// pepper directly to the OS keychain. On keychain-write failure
/// rolls back the disk hash. Also clears the persisted
/// rate-limit state file (best effort).
pub async fn keychain_password_gate_set_password(
    support_dir: String,
    password: Vec<u8>,
) -> Result<(), String> {
    actor::set_password(Path::new(&support_dir), &password).await
}

/// Drop every artifact the gate writes — disk hash + keychain
/// pepper. Best-effort: a disk error or a keychain error
/// surfaces as `Err` so the caller can log, but each side runs
/// independently of the other.
pub async fn keychain_password_gate_clear(support_dir: String) -> Result<(), String> {
    actor::clear(Path::new(&support_dir)).await
}

/// Verify the T1+pw password against the on-disk hash + the keychain
/// pepper. Returns `Ok(true)` on match, `Ok(false)` on every
/// other outcome (file missing / corrupt blob / pepper missing /
/// HMAC mismatch). `Err` is reserved for filesystem read errors
/// the caller can't recover from.
pub async fn keychain_password_gate_verify(
    support_dir: String,
    password: Vec<u8>,
) -> Result<bool, String> {
    actor::verify_password(Path::new(&support_dir), &password).await
}
