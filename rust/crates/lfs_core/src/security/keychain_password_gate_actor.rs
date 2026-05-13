//! Async actor commands for the T1+pw keychain-password gate.
//!
//! The verify pipeline composes existing Rust building blocks:
//! 1. Read the `security_pass_hash.bin` disk blob from the
//!    support dir.
//! 2. Decode the `{salt, hmac}` envelope via
//!    [`crate::security::keychain_password_gate::decode_disk_blob`].
//! 3. Fetch the keychain pepper directly via
//!    [`lfs_os_security::secure_key_storage::read`] — every
//!    target platform routes through the same Rust dispatch
//!    (libsecret on Linux, SecItem on Apple, CredRead on
//!    Windows, AndroidKeyStore JNI on Android).
//! 4. Compute `HMAC(pepper, salt, password)` and compare in
//!    constant time against the stored HMAC.
//!
//! Returns `Ok(true)` on a match, `Ok(false)` on every other
//! outcome (file missing / corrupt blob / pepper missing /
//! HMAC mismatch). `Err` is reserved for infrastructure failures
//! the caller can't recover from (filesystem read errors).

use std::path::Path;

use crate::id::random_uuid_v4;
use crate::security::keychain_password_gate::{
    compute_gate_hmac, decode_disk_blob, encode_disk_blob, random_salt_and_pepper, DiskBlob,
};
use crate::security::persisted_rate_limit_actor as rl_actor;

/// Storage key for the keychain pepper. Mirrors the Dart-era
/// `KeychainPasswordGate._pepperKey` const — both implementations
/// must agree on the slot or an T1+pw-configured install would lose
/// its pepper across the cutover.
const PEPPER_KEY: &str = "letsflutssh_l2_pepper";

/// File name (under the support dir) for the persisted rate-limit
/// state. Cleared by `set_password` so a fresh password rotation
/// doesn't trip the HMAC-mismatch tamper branch with the leftover
/// state file from the previous pepper. Mirrors
/// `KeychainPasswordGate._clearRateLimitState`.
const RATE_LIMIT_STATE_FILE: &str = "rate_limit_state.bin";

/// File name under the support directory that holds the T1+pw
/// gate's `{salt, hmac}` JSON envelope. Mirrors the Dart-era
/// `_hashFileName` const.
const HASH_FILE_NAME: &str = "security_pass_hash.bin";

/// Verify the T1+pw password against the on-disk hash + the
/// keychain pepper. Returns `Ok(true)` on match.
pub async fn verify_password(support_dir: &Path, password: &[u8]) -> Result<bool, String> {
    // Step 1: read the disk hash. Missing file = gate not
    // configured = no match (caller still records as a failure
    // for the rate limiter). `tokio::fs::read` so the FRB worker
    // is not blocked on the syscall.
    let hash_path = support_dir.join(HASH_FILE_NAME);
    // Park sync `read_bytes_secure` (O_NOFOLLOW open) on
    // spawn_blocking so the FRB worker is not stalled on the
    // syscall. The Tokio fs APIs do not expose `OpenOptions::custom_flags`
    // for symlink-safe opens directly; routing through the sync
    // helper inside spawn_blocking keeps the symlink defence.
    let hash_path_for_read = hash_path.clone();
    let raw = match tokio::task::spawn_blocking(move || {
        crate::path::read_bytes_secure(&hash_path_for_read)
    })
    .await
    .map_err(|e| format!("T1+pw verify: blocking task: {e}"))?
    {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(e) => return Err(format!("T1+pw verify: read hash file: {e}")),
    };

    // Step 2: decode the {salt, hmac} envelope.
    let blob_str = match std::str::from_utf8(&raw) {
        Ok(s) => s,
        Err(_) => return Ok(false),
    };
    let decoded = match decode_disk_blob(blob_str) {
        Ok(d) => d,
        Err(_) => return Ok(false),
    };

    // Step 3: fetch the keychain pepper. A backend error or
    // missing entry both collapse to Ok(false) — the rate limiter
    // counts the attempt and the caller routes through the T0
    // fallback. `Err` here is reserved for the disk read above.
    let pepper = match lfs_os_security::secure_key_storage::read(PEPPER_KEY).await {
        Ok(Some(bytes)) if !bytes.is_empty() => bytes,
        Ok(_) => return Ok(false),
        Err(_) => return Ok(false),
    };

    // Step 4: HMAC + constant-time compare. The pepper +
    // salt + password reconstruct the stored hmac when the
    // password is correct.
    let computed = compute_gate_hmac(&pepper, &decoded.salt, password);
    use subtle::ConstantTimeEq;
    Ok(computed.ct_eq(&decoded.hmac).into())
}

/// True when the gate is configured on this install — the disk
/// hash exists AND the keychain holds the pepper.
///
/// Returns `Ok(false)` on any non-fatal miss (file absent, pepper
/// absent, backend error). The T0 fallback path already treats
/// the gate as not-configured in any of those cases — surfacing
/// `Err` would only force the caller to map it back to the same
/// false branch.
pub async fn is_configured(support_dir: &Path) -> Result<bool, String> {
    if !support_dir.join(HASH_FILE_NAME).exists() {
        return Ok(false);
    }
    match lfs_os_security::secure_key_storage::read(PEPPER_KEY).await {
        Ok(Some(bytes)) => Ok(!bytes.is_empty()),
        Ok(None) => Ok(false),
        Err(_) => Ok(false),
    }
}

/// Read the on-disk `{salt, hmac}` envelope and return the
/// decoded values. Used by the rate-limiter setup path that
/// needs the stored HMAC as the per-install rate-limit key
/// without reaching for Dart-side `File.readAsBytes`.
///
/// Outcomes collapse into the `Option`:
/// - `Ok(None)` — file absent, blob malformed, or non-UTF-8.
///   The rate limiter treats every "no recoverable HMAC" as
///   "no rate limiter active for this install"; surfacing typed
///   errors here would force the caller to map them all back to
///   the same null branch.
/// - `Ok(Some(_))` — the parsed envelope.
/// - `Err(_)` — only for I/O failures distinct from `NotFound`,
///   so the caller can log the underlying syscall problem.
pub async fn read_decoded_blob(support_dir: &Path) -> Result<Option<DiskBlob>, String> {
    let hash_path = support_dir.join(HASH_FILE_NAME);
    let raw = match tokio::task::spawn_blocking(move || crate::path::read_bytes_secure(&hash_path))
        .await
        .map_err(|e| format!("read decoded blob: blocking task: {e}"))?
    {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("read decoded blob: read hash file: {e}")),
    };
    let blob_str = match std::str::from_utf8(&raw) {
        Ok(s) => s,
        Err(_) => return Ok(None),
    };
    Ok(decode_disk_blob(blob_str).ok())
}

/// Read the on-disk gate envelope under `support_dir` and register
/// a fresh slot in
/// [`crate::security::persisted_rate_limit_actor::instance`] keyed
/// to a freshly-minted handle id, using the decoded HMAC as the
/// rate-limit signing seed and the canonical
/// `rate_limit_state.bin` path under the same support dir. Returns
/// the handle, or `Ok(None)` when the gate has never been
/// configured (no disk hash or unparsable blob — every "no
/// recoverable HMAC" outcome collapses to one branch).
///
/// The HMAC bytes never leave Rust — caller receives only an
/// opaque id which it threads through the existing
/// `persisted_rate_limit_actor_*` FRB ops. Replaces the earlier
/// `read_decoded_blob → Dart → init_or_get` round-trip where the
/// secret crossed FRB twice.
pub async fn build_persisted_rate_limiter(support_dir: &Path) -> Result<Option<String>, String> {
    let decoded = match read_decoded_blob(support_dir).await? {
        Some(b) => b,
        None => return Ok(None),
    };
    let state_path = support_dir.join(RATE_LIMIT_STATE_FILE);
    // Create the parent dir on the same blocking pool the actor
    // would otherwise touch lazily on first write — keeps the
    // `init_or_get` synchronous call free of a directory miss
    // that would later surface as a swallowed write error.
    if let Some(parent) = state_path.parent() {
        let parent_owned = parent.to_path_buf();
        tokio::task::spawn_blocking(move || crate::path::create_dir_all_secure(&parent_owned))
            .await
            .map_err(|e| format!("build persisted rate limiter: blocking task: {e}"))?
            .map_err(|e| format!("build persisted rate limiter: create support dir: {e}"))?;
    }
    let id = random_uuid_v4();
    rl_actor::instance().init_or_get(&id, state_path, decoded.hmac);
    Ok(Some(id))
}

/// Configure the gate with `password`. Generates a fresh salt +
/// pepper, computes the HMAC, atomically writes the disk hash,
/// then writes the pepper directly to the OS keychain. On
/// keychain-write failure rolls back the disk hash so the next
/// `is_configured` returns false rather than leaving a half-
/// configured gate that perma-rejects the correct password.
///
/// Two invariants, both load-bearing for T1+pw:
/// 1. Atomic disk write — a `write_bytes_atomic` crash mid-flush
///    yields torn JSON; next launch's `verify` returns false on
///    decode and falls back to the T0 plaintext-tier unlock.
/// 2. Disk before keychain — old order (keychain-first) could
///    crash between steps and leave the keychain holding the
///    NEW pepper while disk holds the OLD salt+HMAC; on next
///    launch the correct password fails to verify and forces a
///    "forgot password" wipe. Disk-first means a crash between
///    steps leaves the OLD state fully verifiable under the OLD
///    pepper still in the keychain.
///
/// Also clears the persisted rate-limit state file (best effort
/// — a filesystem hiccup logs + swallows rather than blocking
/// the password write).
pub async fn set_password(support_dir: &Path, password: &[u8]) -> Result<(), String> {
    let (salt, pepper) = random_salt_and_pepper();
    let hmac = compute_gate_hmac(&pepper, &salt, password);
    let blob = encode_disk_blob(&salt, &hmac);

    let hash_path = support_dir.join(HASH_FILE_NAME);
    if let Some(parent) = hash_path.parent() {
        let parent_owned = parent.to_path_buf();
        tokio::task::spawn_blocking(move || crate::path::create_dir_all_secure(&parent_owned))
            .await
            .map_err(|e| format!("T1+pw set_password: blocking task: {e}"))?
            .map_err(|e| format!("T1+pw set_password: create support dir: {e}"))?;
    }
    // `write_bytes_atomic` is sync (random-suffix tmp + sync_data +
    // parent-dir fsync). Park on `spawn_blocking` so the FRB worker
    // is free during the rename window.
    {
        let hash_path_clone = hash_path.clone();
        let blob_bytes = blob.into_bytes();
        tokio::task::spawn_blocking(move || {
            crate::path::write_bytes_atomic(&hash_path_clone, &blob_bytes)
        })
        .await
        .map_err(|e| format!("T1+pw set_password: blocking task: {e}"))?
        .map_err(|e| format!("T1+pw set_password: atomic write: {e}"))?;
    }

    // Now hand the pepper to the keychain.
    if let Err(write_err) = lfs_os_security::secure_key_storage::write(PEPPER_KEY, &pepper).await {
        // Rollback: delete the disk hash so `is_configured`
        // returns false and the next open routes through the
        // wizard instead of perma-rejecting the correct password.
        if let Err(rollback_err) = tokio::fs::remove_file(&hash_path).await {
            return Err(format!(
                "T1+pw set_password: keychain write failed ({write_err}); \
                 rollback delete failed ({rollback_err}) — gate is \
                 half-configured, next launch will see is_configured=true \
                 but verify can never succeed",
            ));
        }
        return Err(format!(
            "T1+pw set_password: keychain write failed ({write_err}); \
             rolled back disk hash"
        ));
    }

    // Best-effort rate-limit-state wipe so the next limiter
    // starts with a zero counter under the new HMAC key.
    let state_path = support_dir.join(RATE_LIMIT_STATE_FILE);
    match tokio::fs::remove_file(&state_path).await {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => {
            // Non-fatal — log via the bus would tie the actor to
            // an UI-shaped event; swallow so the password write
            // itself stays durable. Dart side does the same swallow.
        }
    }

    Ok(())
}

/// Drop every artifact the gate writes — disk hash + keychain
/// pepper. Best-effort: a filesystem error on the disk side or a
/// keychain error on the keychain side surfaces as `Err` so the
/// caller can log, but each step runs independently of the
/// other (a disk-delete failure does not block the keychain
/// purge).
pub async fn clear(support_dir: &Path) -> Result<(), String> {
    let mut errors = Vec::new();

    let hash_path = support_dir.join(HASH_FILE_NAME);
    match tokio::fs::remove_file(&hash_path).await {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => errors.push(format!("disk hash delete: {e}")),
    }

    if let Err(e) = lfs_os_security::secure_key_storage::delete(PEPPER_KEY).await {
        errors.push(format!("keychain delete: {e}"));
    }

    if errors.is_empty() {
        Ok(())
    } else {
        Err(format!("T1+pw clear: {}", errors.join("; ")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::keychain_password_gate::{
        compute_gate_hmac, encode_disk_blob, random_salt_and_pepper,
    };
    use tempfile::TempDir;

    /// Set up a fresh T1+pw gate config on disk + return the pepper
    /// the test stand-in would inject — kept for shape parity
    /// with the prior actor tests even though the post-bus rewrite
    /// no longer surfaces the pepper through a registry.
    fn setup_gate(dir: &Path, password: &[u8]) -> Vec<u8> {
        let (salt, pepper) = random_salt_and_pepper();
        let hmac = compute_gate_hmac(&pepper, &salt, password);
        let blob = encode_disk_blob(&salt, &hmac);
        std::fs::write(dir.join(HASH_FILE_NAME), blob).unwrap();
        pepper
    }

    #[tokio::test]
    async fn verify_returns_false_when_hash_file_missing() {
        let dir = TempDir::new().unwrap();
        let result = verify_password(dir.path(), b"anything").await.unwrap();
        assert!(!result);
    }

    #[tokio::test]
    async fn verify_returns_false_for_corrupt_blob() {
        let dir = TempDir::new().unwrap();
        std::fs::write(dir.path().join(HASH_FILE_NAME), b"not-json").unwrap();
        let result = verify_password(dir.path(), b"anything").await.unwrap();
        assert!(!result);
    }

    /// Backend-pepper-missing path: a fresh hash file is on disk
    /// but `lfs_os_security::secure_key_storage::read(PEPPER_KEY)`
    /// returns `Ok(None)`. Result must collapse to `Ok(false)` so
    /// the rate limiter records the attempt; the function must not
    /// surface the keychain miss as `Err`.
    ///
    /// Test runs without bootstrapping a keychain — the call returns
    /// `Ok(None)` in the libsecret CI fallback and on hosts with no
    /// matching alias. Either way the asserted invariant holds.
    #[tokio::test]
    async fn verify_returns_false_when_pepper_absent() {
        let dir = TempDir::new().unwrap();
        let _pepper = setup_gate(dir.path(), b"hunter2");
        let result = verify_password(dir.path(), b"hunter2").await.unwrap();
        assert!(!result);
    }

    /// `is_configured` short-circuits to `false` on a fresh dir
    /// (no hash file).
    #[tokio::test]
    async fn is_configured_false_when_no_hash_file() {
        let dir = TempDir::new().unwrap();
        let result = is_configured(dir.path()).await.unwrap();
        assert!(!result);
    }

    /// `build_persisted_rate_limiter` collapses an unconfigured
    /// gate to `Ok(None)` so the Dart caller treats it as "no
    /// rate limiter for this install" without needing to inspect
    /// errors.
    #[tokio::test]
    async fn build_persisted_rate_limiter_returns_none_when_gate_absent() {
        let dir = TempDir::new().unwrap();
        let res = build_persisted_rate_limiter(dir.path()).await.unwrap();
        assert!(res.is_none());
    }

    /// On a configured gate the function mints a fresh id +
    /// registers a slot in the `persisted_rate_limit_actor` so
    /// the FRB status ops resolve against the registered limiter.
    /// The HMAC bytes stay Rust-side — the test only observes the
    /// id round-trip + a zero-baseline status snapshot.
    #[tokio::test]
    async fn build_persisted_rate_limiter_registers_slot_for_configured_gate() {
        let dir = TempDir::new().unwrap();
        let _pepper = setup_gate(dir.path(), b"hunter2");
        let id = build_persisted_rate_limiter(dir.path())
            .await
            .unwrap()
            .expect("configured gate yields an id");
        let snap = rl_actor::instance().status(&id);
        assert_eq!(snap.failure_count, 0);
        assert_eq!(snap.cooldown_remaining_ms, 0);
        rl_actor::instance().clear(&id);
    }
}
