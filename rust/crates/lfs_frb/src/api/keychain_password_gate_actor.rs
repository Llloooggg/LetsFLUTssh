//! FRB adapter for `lfs_core::security::keychain_password_gate_actor`.
//!
//! The actor composes the T1+pw verify / set / clear / is_configured
//! pipeline directly against
//! [`lfs_os_security::secure_key_storage`] — no Dart-side bus
//! listener is in the unlock path. Each FRB function operates on the
//! app-support directory pinned at `config_store_init`
//! (`master_password::try_pinned_support_dir`) and forwards into the
//! actor; the Dart caller no longer threads a path in.

use lfs_core::security::keychain_password_gate_actor as actor;
use lfs_core::security::master_password;

fn pinned_support_dir() -> Result<&'static std::path::Path, String> {
    master_password::try_pinned_support_dir().map_err(|e| crate::api::frb_err::from_core(&e))
}

/// True when the T1+pw gate is configured on this install — disk
/// hash present AND keychain pepper present.
///
/// Returns `Ok(false)` on any non-fatal miss (file absent, pepper
/// absent, backend error). `Err` is reserved for unrecoverable
/// infra failures the caller can't recover from.
pub async fn keychain_password_gate_is_configured() -> Result<bool, String> {
    actor::is_configured(pinned_support_dir()?).await
}

/// Configure the gate with `password`. Generates fresh salt +
/// pepper, writes the disk hash atomically, then writes the
/// pepper directly to the OS keychain. On keychain-write failure
/// rolls back the disk hash. Also clears the persisted
/// rate-limit state file (best effort).
pub async fn keychain_password_gate_set_password(password: Vec<u8>) -> Result<(), String> {
    actor::set_password(pinned_support_dir()?, &password).await
}

/// Drop every artifact the gate writes — disk hash + keychain
/// pepper. Best-effort: a disk error or a keychain error
/// surfaces as `Err` so the caller can log, but each side runs
/// independently of the other.
pub async fn keychain_password_gate_clear() -> Result<(), String> {
    actor::clear(pinned_support_dir()?).await
}

/// Verify the T1+pw password against the on-disk hash + the keychain
/// pepper. Returns `Ok(true)` on match, `Ok(false)` on every
/// other outcome (file missing / corrupt blob / pepper missing /
/// HMAC mismatch). `Err` is reserved for filesystem read errors
/// the caller can't recover from.
pub async fn keychain_password_gate_verify(password: Vec<u8>) -> Result<bool, String> {
    actor::verify_password(pinned_support_dir()?, &password).await
}

/// Read the on-disk `{salt, hmac}` envelope from
/// `support_dir/security_pass_hash.bin` and return the decoded
/// pair. `None` collapses every "no usable HMAC" outcome
/// (missing file, malformed blob, non-UTF-8 content) into one
/// branch the Dart rate-limiter setup path consumes as "no
/// rate limiter for this install"; `Err` only for I/O failures
/// distinct from `NotFound`.
pub async fn keychain_password_gate_read_decoded(
) -> Result<Option<crate::api::keychain_password_gate::DbKeychainGateBlob>, String> {
    let decoded = actor::read_decoded_blob(pinned_support_dir()?).await?;
    Ok(
        decoded.map(|b| crate::api::keychain_password_gate::DbKeychainGateBlob {
            salt: b.salt,
            hmac: b.hmac,
        }),
    )
}

/// Read the gate envelope under the pinned support dir and register a
/// `persisted_rate_limit_actor` slot under a freshly-minted handle
/// id using the gate's HMAC as the rate-limit seed + the canonical
/// `rate_limit_state.bin` path. Returns the id, or `Ok(None)` when
/// the gate has never been configured (every "no recoverable HMAC"
/// outcome collapses to one branch the Dart caller maps to "no
/// rate limiter for this install").
///
/// The HMAC bytes never cross the FRB boundary — read + register
/// happen inside the same Rust process. Dart threads the returned
/// id through the existing `persisted_rate_limit_actor_*` ops.
pub async fn keychain_password_gate_build_persisted_rate_limiter() -> Result<Option<String>, String>
{
    actor::build_persisted_rate_limiter(pinned_support_dir()?).await
}

// The missing-state / round-trip behaviours are covered against the
// explicit `&Path` API in `lfs_core::security::keychain_password_gate_actor`
// and the Dart `keychain_password_gate_test.dart` integration suite;
// these FRB wrappers only resolve the pinned support dir and delegate.
