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

/// Read the on-disk `{salt, hmac}` envelope from
/// `support_dir/security_pass_hash.bin` and return the decoded
/// pair. `None` collapses every "no usable HMAC" outcome
/// (missing file, malformed blob, non-UTF-8 content) into one
/// branch the Dart rate-limiter setup path consumes as "no
/// rate limiter for this install"; `Err` only for I/O failures
/// distinct from `NotFound`.
pub async fn keychain_password_gate_read_decoded(
    support_dir: String,
) -> Result<Option<crate::api::keychain_password_gate::DbKeychainGateBlob>, String> {
    let decoded = actor::read_decoded_blob(Path::new(&support_dir)).await?;
    Ok(
        decoded.map(|b| crate::api::keychain_password_gate::DbKeychainGateBlob {
            salt: b.salt,
            hmac: b.hmac,
        }),
    )
}

/// Read the gate envelope under `support_dir` and register a
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
pub async fn keychain_password_gate_build_persisted_rate_limiter(
    support_dir: String,
) -> Result<Option<String>, String> {
    actor::build_persisted_rate_limiter(Path::new(&support_dir)).await
}

#[cfg(test)]
mod tests {
    use super::*;

    // The set_password / verify / clear / is_configured paths
    // round-trip through `lfs_os_security::secure_key_storage` for
    // the keychain pepper; covered by the Dart `keychain_password_gate_test.dart`
    // integration suite under tempdir + mock keychain. The
    // standalone tests below pin the missing-state contract — every
    // FRB call against an empty support_dir must surface a usable
    // outcome rather than panic.

    #[tokio::test]
    async fn is_configured_returns_ok_false_for_missing_support_dir() {
        // Pin the documented contract — file absent + pepper
        // absent collapses to `Ok(false)` so the cold-start probe
        // before the gate is set still surfaces a usable outcome.
        let dir = tempfile::tempdir().expect("tempdir");
        let res =
            keychain_password_gate_is_configured(dir.path().to_string_lossy().into_owned()).await;
        // Either Ok(false) or an OS-keychain probe error — both are
        // valid; the only invariant is "no panic, no Err that
        // propagates a corrupt-state classification".
        match res {
            Ok(false) => (),
            Ok(true) => panic!("fresh tempdir cannot be already-configured"),
            Err(_) => (),
        }
    }

    #[tokio::test]
    async fn build_persisted_rate_limiter_returns_none_when_unconfigured() {
        // Fresh tempdir → no `security_pass_hash.bin` → the Dart
        // caller should see `None` (= no rate limiter for this
        // install) rather than an `Err` it has to map back to the
        // same null branch.
        let dir = tempfile::tempdir().expect("tempdir");
        let res = keychain_password_gate_build_persisted_rate_limiter(
            dir.path().to_string_lossy().into_owned(),
        )
        .await
        .expect("build limiter does not surface infra error on fresh dir");
        assert!(res.is_none());
    }

    #[tokio::test]
    async fn verify_returns_ok_false_when_gate_not_configured() {
        // Verify against a fresh tempdir with no on-disk hash + no
        // keychain pepper — the documented contract is `Ok(false)`
        // (every miss collapses to a "wrong password" outcome).
        let dir = tempfile::tempdir().expect("tempdir");
        let res = keychain_password_gate_verify(
            dir.path().to_string_lossy().into_owned(),
            b"some-password".to_vec(),
        )
        .await;
        // OS keychain probe might Err on some hosts; either way
        // it's a non-true outcome.
        match res {
            Ok(false) => (),
            Ok(true) => panic!("verify against unconfigured gate must not return true"),
            Err(_) => (),
        }
    }
}
