//! T2 hardware-tier vault — Linux TPM2 path orchestrator + shared
//! blob-format helpers.
//!
//! Apple / Android live behind `lfs_os_security::hardware_tier_vault`
//! (objc2 / JNI FFI). Linux's TPM CLI shell-out lives one crate up in
//! `lfs_os_security::linux::tpm`; the [`linux`] submodule below
//! orchestrates the full store / read / clear flow Rust-internal so
//! the DB key never crosses the FRB boundary on this path either.
//!
//! Wire format (JSON object, UTF-8 bytes on disk):
//! ```json
//! { "salt": "<base64>", "sealed": "<base64>" }
//! ```
//!
//! `encode_linux_blob` / `decode_linux_blob` cover the wire shape;
//! [`linux::store`] / [`linux::read`] / [`linux::clear`] cover the
//! end-to-end orchestration.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::Value;

use crate::crypto::hmac_sha256;

/// Decoded blob payload — the salt + TPM-sealed DB-key bytes the
/// vault read from `hardware_vault.bin`.
#[derive(Debug, Clone)]
pub struct LinuxBlob {
    pub salt: Vec<u8>,
    pub sealed: Vec<u8>,
}

/// Encode the salt + sealed-blob pair as the JSON envelope written
/// to `hardware_vault.bin` on Linux. Caller writes the returned
/// string's UTF-8 bytes atomically — the file lives next to the
/// other 0600-hardened secret files under app-support.
#[must_use]
pub fn encode_linux_blob(salt: &[u8], sealed: &[u8]) -> String {
    // Hand-build the literal so the field order is stable
    // ({"salt": …, "sealed": …}) — explicit shape protects the
    // wire-format docs from a future serde-default flip.
    format!(
        "{{\"salt\":\"{}\",\"sealed\":\"{}\"}}",
        STANDARD.encode(salt),
        STANDARD.encode(sealed)
    )
}

/// Parse the on-disk JSON envelope. Returns `Err` for malformed
/// JSON, missing fields, non-string values, invalid base64, or
/// empty decoded bytes (a legitimate seal is never zero-length).
/// The Dart-side `read` treats any decode failure as a "vault is
/// empty / corrupt" outcome and routes the user back to the
/// password unlock dialog.
pub fn decode_linux_blob(blob: &str) -> Result<LinuxBlob, String> {
    let value: Value = serde_json::from_str(blob).map_err(|e| format!("blob: parse JSON: {e}"))?;
    let obj = value
        .as_object()
        .ok_or_else(|| String::from("blob: not a JSON object"))?;
    let salt_b64 = obj
        .get("salt")
        .and_then(|v| v.as_str())
        .ok_or_else(|| String::from("blob: missing salt field"))?;
    let sealed_b64 = obj
        .get("sealed")
        .and_then(|v| v.as_str())
        .ok_or_else(|| String::from("blob: missing sealed field"))?;
    let salt = STANDARD
        .decode(salt_b64.as_bytes())
        .map_err(|e| format!("blob: salt decode: {e}"))?;
    let sealed = STANDARD
        .decode(sealed_b64.as_bytes())
        .map_err(|e| format!("blob: sealed decode: {e}"))?;
    if salt.is_empty() || sealed.is_empty() {
        return Err(String::from("blob: empty salt or sealed"));
    }
    Ok(LinuxBlob { salt, sealed })
}

/// Hardware-tier vault auth-value source.
///
/// * `Password(pw)` — `HMAC(salt, pw)` over typed bytes. The
///   canonical Hardware-tier unlock path.
/// * `Biometric(hash)` — `HMAC(salt, hash)` over a fprintd-derived
///   hash. The wizard invariant still expects the user has set a
///   master password too — biometric is the optional shortcut
///   that releases the same password from an OS-gated slot, never
///   a replacement.
///
/// The Hardware tier always carries a user-typed secret; the
/// passwordless arm that used to live here is gone. A caller
/// asking for "no secret" against the Hardware tier is a bug —
/// surface the empty payload as `None` so the unlock path routes
/// through the dialog rather than sealing under an empty
/// auth-value.
#[derive(Debug, Clone, Copy)]
pub enum AuthIntent<'a> {
    Password(&'a str),
    Biometric(&'a [u8]),
}

/// Resolve the hardware-tier vault auth value for an `AuthIntent`.
/// Returns `None` for an empty payload (empty typed password /
/// empty biometric hash) — callers surface `None` as "modifier
/// resolution failed → treat as cancelled unlock" so we never
/// silently fall back to an empty auth.
#[must_use]
pub fn resolve_auth_value(
    intent: AuthIntent<'_>,
    salt: &[u8],
) -> Option<zeroize::Zeroizing<Vec<u8>>> {
    match intent {
        AuthIntent::Password("") | AuthIntent::Biometric([]) => None,
        AuthIntent::Password(pw) => Some(hmac_sha256(salt, pw.as_bytes())),
        AuthIntent::Biometric(hash) => Some(hmac_sha256(salt, hash)),
    }
}

/// v6 → v7 config migration marker — written when the `ConfigV6ToV7`
/// migration flips a Hardware config from `modifiers.password=false`
/// to `modifiers.password=true`. The wrapped key on disk still
/// carries the empty PIN-HMAC seal from the pre-flip install; the
/// follow-up bootstrap wizard re-seals against the user's typed
/// password before the regular unlock path runs.
///
/// The marker survives until the wizard explicitly clears it via
/// [`clear_v6_v7_password_set_marker`]. A bootstrap call to
/// [`hardware_password_set_wizard_required`] keys off the marker's
/// presence — the unlock orchestrator would otherwise rate-limit
/// itself against a vault that no live password can unseal.
pub const V6_V7_PASSWORD_SET_MARKER_FILE: &str = ".hardware_v7_password_set_pending";

/// Resolve the marker path for the v6 → v7 password-set wizard.
#[must_use]
pub fn v6_v7_password_set_marker_path(support_dir: &std::path::Path) -> std::path::PathBuf {
    support_dir.join(V6_V7_PASSWORD_SET_MARKER_FILE)
}

/// Write the v6 → v7 password-set marker. Idempotent — a pre-
/// existing marker is left untouched (the migration is
/// re-entrant against a partially-applied previous run).
pub fn write_v6_v7_password_set_marker(support_dir: &std::path::Path) -> std::io::Result<()> {
    let path = v6_v7_password_set_marker_path(support_dir);
    if path.exists() {
        return Ok(());
    }
    crate::path::write_bytes_atomic(&path, b"").map_err(|e| std::io::Error::other(e.to_string()))
}

/// Clear the v6 → v7 password-set marker. Idempotent — a missing
/// target file is treated as success so the wizard can call this
/// without branching on pre-existence.
pub fn clear_v6_v7_password_set_marker(support_dir: &std::path::Path) -> std::io::Result<()> {
    let path = v6_v7_password_set_marker_path(support_dir);
    match std::fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

/// True when the v6 → v7 password-set wizard needs to run before
/// the regular Hardware-tier unlock path. Bootstrap consults this
/// ahead of [`crate::security::tier_unlock_orchestrator::unlock_hardware`]
/// so a stale empty-PIN seal never enters the rate-limited
/// unlock loop.
#[must_use]
pub fn hardware_password_set_wizard_required(support_dir: &std::path::Path) -> bool {
    v6_v7_password_set_marker_path(support_dir).exists()
}

/// Sibling-file salt I/O for the Apple / Windows / Android paths.
///
/// `hardware_vault_salt.bin` carries the per-install 32-byte salt
/// the auth value derives against. Linux co-locates the salt
/// inside the vault envelope so the helpers here are no-ops on
/// that target — callers gate by `cfg(target_os = "linux")`.
///
/// The three operations live one place so a future format bump
/// (path move, header prefix, secondary check-byte) does not have
/// to chase Dart + each platform's vault impl in parallel.
pub mod salt {
    use std::path::Path;

    use rand::RngCore;

    #[cfg(not(target_os = "linux"))]
    use crate::path::write_bytes_atomic;

    /// File name the Apple / Windows / Android vault impls read +
    /// write next to the wrapped key. Mirrors the wipe-registry
    /// entry under `lfs_core::security::wipe::MANAGED_FILES`.
    pub const FILE_NAME: &str = "hardware_vault_salt.bin";

    /// Canonical salt length stamped by every writer + checked by
    /// every reader; a wrong-length file on disk routes the caller
    /// through the corrupt-state cascade rather than HMACing
    /// against a truncated value.
    pub const LEN: usize = 32;

    fn salt_path(support_dir: &Path) -> std::path::PathBuf {
        support_dir.join(FILE_NAME)
    }

    /// Generate a fresh 32-byte salt via `OsRng` and (on Apple /
    /// Windows / Android) persist it atomically to
    /// `hardware_vault_salt.bin` (tmp + fsync + rename, 0600). On
    /// Linux the salt rides inside the vault envelope itself, so
    /// the persist step is a no-op there — caller hands the
    /// returned bytes to the Linux orchestrator which embeds
    /// them in the JSON envelope.
    ///
    /// Caller is responsible for the salt-then-vault ordering on
    /// non-Linux targets — a crash between this write and the
    /// platform store leaves the next launch with a sibling salt
    /// but no wrapped key, which the vault `is_stored` probe
    /// surfaces as "not configured" and the next attempt
    /// re-provisions cleanly.
    pub fn provision(support_dir: &Path) -> std::io::Result<Vec<u8>> {
        let mut salt = vec![0u8; LEN];
        rand::rngs::OsRng.fill_bytes(&mut salt);
        #[cfg(not(target_os = "linux"))]
        {
            write_bytes_atomic(&salt_path(support_dir), &salt)
                .map_err(|e| std::io::Error::other(e.to_string()))?;
        }
        #[cfg(target_os = "linux")]
        {
            let _ = support_dir;
        }
        Ok(salt)
    }

    /// Read the on-disk salt. Returns `Ok(None)` when the file
    /// does not exist (clean install) or has the wrong length
    /// (truncated / tampered) — both routes call sites map to
    /// "no usable salt" and surface the unlock-cancelled path.
    /// `Err` only for I/O failures distinct from `NotFound`.
    pub fn read(support_dir: &Path) -> std::io::Result<Option<Vec<u8>>> {
        let path = salt_path(support_dir);
        match std::fs::read(&path) {
            Ok(bytes) if bytes.len() == LEN => Ok(Some(bytes)),
            Ok(_) => Ok(None),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Delete the salt file. Idempotent on a missing target so
    /// the tier-reset cascade can call this without branching on
    /// pre-existence.
    pub fn delete(support_dir: &Path) -> std::io::Result<()> {
        match std::fs::remove_file(salt_path(support_dir)) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e),
        }
    }
}

/// Linux TPM2 store / read / clear orchestrator. Mirrors the Apple
/// / Android shape in `lfs_os_security::hardware_tier_vault` so
/// every platform's hardware-tier vault has a Rust-internal
/// orchestrator and the DB key never lands on the Dart heap on the
/// store / read paths.
#[cfg(target_os = "linux")]
pub mod linux {
    use std::path::{Path, PathBuf};

    use crate::path::write_bytes_atomic;
    use lfs_os_security::linux::tpm::{self, TpmConfig};

    /// Filename inside `support_dir` carrying the encoded blob.
    /// Matches the wipe-registry entry in
    /// `lfs_core::security::wipe::MANAGED_FILES`.
    const VAULT_FILE: &str = "hardware_vault.bin";

    /// Errors the Linux orchestrator surfaces.
    #[derive(Debug)]
    pub enum LinuxVaultError {
        /// `tpm2-tools` not reachable, `/dev/tpmrm0` missing, or the
        /// TPM rejected the seal call.
        TpmUnavailable(String),
        /// fprintd D-Bus service is not registered, has no default
        /// reader, or no fingers are enrolled. Only the
        /// biometric-overlay path surfaces this — the primary vault
        /// does not consult fprintd.
        FprintdUnavailable,
        /// `tpm2_create` / `tpm2_unseal` ran but returned an error.
        Backend(String),
        /// File-IO surface — read / write / atomic-rename failed.
        Io(String),
        /// On-disk blob malformed (missing JSON fields, bad base64,
        /// etc.). Caller routes to "vault corrupt" recovery.
        Corrupt(String),
    }

    impl std::fmt::Display for LinuxVaultError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::TpmUnavailable(s) => write!(f, "tpm unavailable: {s}"),
                Self::FprintdUnavailable => {
                    write!(f, "fprintd unavailable / no enrolled fingers")
                }
                Self::Backend(s) => write!(f, "tpm backend: {s}"),
                Self::Io(s) => write!(f, "io: {s}"),
                Self::Corrupt(s) => write!(f, "corrupt: {s}"),
            }
        }
    }

    impl std::error::Error for LinuxVaultError {}

    fn vault_path(support_dir: &str) -> PathBuf {
        Path::new(support_dir).join(VAULT_FILE)
    }

    /// True when `tpm2-tools` + `/dev/tpmrm0` are both reachable.
    /// Mirrors `lfs_os_security::hardware_tier_vault::is_available`
    /// for non-Apple targets so the cfg-arm dispatch in the FRB
    /// shim can route Linux through here.
    #[must_use]
    pub fn is_available() -> bool {
        matches!(
            tpm::probe(&TpmConfig::default()),
            tpm::TpmProbeResult::Available
        )
    }

    /// True when `support_dir/hardware_vault.bin` exists. Pure
    /// path-stat; does not invoke the TPM.
    #[must_use]
    pub fn is_stored(support_dir: &str) -> bool {
        vault_path(support_dir).exists()
    }

    /// Seal `db_key` under TPM-2.0 keyed by the caller-derived
    /// `pin_hmac` (`HMAC(salt, pin)` over the freshly-generated
    /// `salt` — same pre-derivation Apple / Android callers do
    /// today). Writes `{salt, sealed}` JSON envelope to
    /// `support_dir/hardware_vault.bin` atomically. `pin_hmac` MAY
    /// be empty for the passwordless flow — caller and unseal
    /// must agree.
    ///
    /// Linux co-locates the salt inside the envelope rather than
    /// using a sibling `hardware_vault_salt.bin` file (Apple /
    /// Android pattern). Caller still owns the salt — see
    /// [`read_blob_salt`] for the unlock-side reverse.
    pub fn store(
        support_dir: &str,
        db_key: &[u8],
        salt: &[u8],
        pin_hmac: &[u8],
    ) -> Result<(), LinuxVaultError> {
        if !is_available() {
            return Err(LinuxVaultError::TpmUnavailable("tpm probe failed".into()));
        }
        let sealed = tpm::seal(&TpmConfig::default(), db_key, pin_hmac)
            .map_err(|e| LinuxVaultError::Backend(e.to_string()))?;
        let body = super::encode_linux_blob(salt, &sealed);
        let blob = lfs_os_security::hardware_tier_vault::prepend_envelope_header(
            lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
            body.as_bytes(),
        );
        let path = vault_path(support_dir);
        if let Some(parent) = path.parent() {
            crate::path::create_dir_all_secure(parent)
                .map_err(|e| LinuxVaultError::Io(format!("mkdirp: {e}")))?;
        }
        write_bytes_atomic(&path, &blob).map_err(|e| LinuxVaultError::Io(format!("write: {e}")))?;
        Ok(())
    }

    /// Read `support_dir/hardware_vault.bin`, decode the salt +
    /// sealed pair, and unseal under the caller-derived `pin_hmac`.
    /// Caller MUST first read the on-disk salt via
    /// [`read_blob_salt`] and derive `pin_hmac = HMAC(salt, pin)`
    /// against it; the function does NOT re-derive.
    ///
    /// Returns:
    /// * `Ok(Some(bytes))` — successful unseal, plaintext key bytes.
    /// * `Ok(None)` — vault file absent, or wrong PIN / re-enrolment
    ///   forced TPM-key invalidation. Caller routes to "needs
    ///   password unlock".
    /// * `Err(_)` — file present but corrupt, or TPM unreachable.
    pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, LinuxVaultError> {
        let path = vault_path(support_dir);
        if !path.exists() {
            return Ok(None);
        }
        let raw = std::fs::read(&path).map_err(|e| LinuxVaultError::Io(format!("read: {e}")))?;
        let body = lfs_os_security::hardware_tier_vault::parse_envelope_header(
            &raw,
            lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
        )
        .map_err(|_| LinuxVaultError::Corrupt("envelope header mismatch".into()))?;
        let text = std::str::from_utf8(body)
            .map_err(|e| LinuxVaultError::Corrupt(format!("utf8: {e}")))?;
        let decoded = super::decode_linux_blob(text).map_err(LinuxVaultError::Corrupt)?;
        match tpm::unseal(&TpmConfig::default(), &decoded.sealed, pin_hmac) {
            Ok(bytes) => Ok(Some(bytes)),
            // Wrong auth or TPM-key invalidation surfaces as a
            // generic backend error from `tpm2-tools`. Map to
            // `Ok(None)` so the unlock UI routes back to password
            // entry, matching the Apple `read` contract for "wrong
            // PIN".
            Err(_) => Ok(None),
        }
    }

    /// Read just the salt half of the on-disk envelope so the
    /// unlock dialog can derive `pin_hmac = HMAC(salt, pin)`
    /// before calling [`read`]. Returns `Ok(None)` for missing /
    /// malformed files.
    pub fn read_blob_salt(support_dir: &str) -> Result<Option<Vec<u8>>, LinuxVaultError> {
        let path = vault_path(support_dir);
        if !path.exists() {
            return Ok(None);
        }
        let raw = std::fs::read(&path).map_err(|e| LinuxVaultError::Io(format!("read: {e}")))?;
        let body = lfs_os_security::hardware_tier_vault::parse_envelope_header(
            &raw,
            lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
        )
        .map_err(|_| LinuxVaultError::Corrupt("envelope header mismatch".into()))?;
        let text = std::str::from_utf8(body)
            .map_err(|e| LinuxVaultError::Corrupt(format!("utf8: {e}")))?;
        let decoded = super::decode_linux_blob(text).map_err(LinuxVaultError::Corrupt)?;
        Ok(Some(decoded.salt))
    }

    /// Drop `support_dir/hardware_vault.bin`. Best-effort —
    /// missing-file is `Ok(())`, file-system errors propagate.
    pub fn clear(support_dir: &str) -> Result<(), LinuxVaultError> {
        let path = vault_path(support_dir);
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(LinuxVaultError::Io(format!("remove: {e}"))),
        }
    }

    // ── biometric password overlay ──────────────────────────────
    //
    // The overlay seals the user's typed master password under
    // TPM2 with the fprintd enrolment hash as the auth value. It
    // is intentionally separate from the primary vault so any
    // change to the biometric enrolment (a new finger enrolled,
    // an old finger dropped) flips the hash and the overlay
    // unseal fails; the primary vault keeps working under the
    // typed password, so the user only loses the biometric
    // shortcut, not their data.
    //
    // The auth value is derived in
    // `lfs_core::platform::linux::fprintd::get_enrolment_hash` —
    // SHA-256 of the sorted-`:`-joined enrolled-finger list, the
    // exact shape `biometric_key_vault::linux` already uses for
    // its TPM-sealed DB key (mirrors Apple's
    // `kSecAccessControlBiometryCurrentSet` invalidation
    // semantics). Re-enrolment flips the hash, the TPM rejects
    // the unseal, and the file is treated as "overlay revoked".

    /// Filename inside `support_dir` carrying the overlay blob.
    /// Matches the wipe-registry entry in
    /// `lfs_core::security::wipe::MANAGED_FILES`.
    pub const BIO_PASSWORD_FILE: &str = "hardware_vault_password_overlay_linux.bin";

    fn bio_password_path(support_dir: &str) -> PathBuf {
        Path::new(support_dir).join(BIO_PASSWORD_FILE)
    }

    /// True when `support_dir/hardware_vault_password_overlay_linux.bin`
    /// exists. Pure path-stat; does not invoke the TPM or fprintd.
    /// The unseal may still fail (fprintd unenrolled, TPM cleared);
    /// `read_biometric_password` surfaces that as `Ok(None)`.
    #[must_use]
    pub fn is_biometric_password_stored(support_dir: &str) -> bool {
        bio_password_path(support_dir).exists()
    }

    /// Seal `password_bytes` under TPM2 keyed by the current fprintd
    /// enrolment hash, then write the length-prefixed envelope to
    /// `support_dir/hardware_vault_password_overlay_linux.bin`.
    /// Requires `tpm2-tools` + `/dev/tpmrm0` available AND fprintd
    /// reachable with at least one enrolled finger; either missing
    /// surfaces as `Err(TpmUnavailable)` / `Err(FprintdUnavailable)`
    /// so the caller can route the user to the README install
    /// snippet rather than silently writing a half-formed vault.
    pub async fn store_biometric_password(
        support_dir: &str,
        password_bytes: &[u8],
    ) -> Result<(), LinuxVaultError> {
        if !is_available() {
            return Err(LinuxVaultError::TpmUnavailable("tpm probe failed".into()));
        }
        let Some(auth_hash) = crate::platform::linux::fprintd::get_enrolment_hash().await else {
            return Err(LinuxVaultError::FprintdUnavailable);
        };
        let password_owned = password_bytes.to_vec();
        let support_dir_owned = support_dir.to_string();
        tokio::task::spawn_blocking(move || -> Result<(), LinuxVaultError> {
            let sealed = lfs_os_security::linux::tpm::seal(
                &lfs_os_security::linux::tpm::TpmConfig::default(),
                &password_owned,
                &auth_hash,
            )
            .map_err(|e| LinuxVaultError::Backend(e.to_string()))?;
            let mut body = Vec::with_capacity(4 + sealed.len());
            let sealed_len = u32::try_from(sealed.len()).map_err(|_| {
                LinuxVaultError::Backend(format!(
                    "overlay sealed length exceeds u32: {}",
                    sealed.len()
                ))
            })?;
            body.extend_from_slice(&sealed_len.to_be_bytes());
            body.extend_from_slice(&sealed);
            let blob = lfs_os_security::hardware_tier_vault::prepend_envelope_header(
                lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
                &body,
            );
            let path = bio_password_path(&support_dir_owned);
            if let Some(parent) = path.parent() {
                crate::path::create_dir_all_secure(parent)
                    .map_err(|e| LinuxVaultError::Io(format!("mkdirp: {e}")))?;
            }
            write_bytes_atomic(&path, &blob)
                .map_err(|e| LinuxVaultError::Io(format!("write overlay: {e}")))?;
            Ok(())
        })
        .await
        .map_err(|e| LinuxVaultError::Io(format!("overlay blocking task: {e}")))??;
        Ok(())
    }

    /// Read + unseal the overlay envelope. Returns:
    /// * `Ok(Some(bytes))` — fprintd matched the sealed enrolment
    ///   hash and the TPM yielded the original password bytes.
    /// * `Ok(None)` — overlay file missing, fprintd has no enrolled
    ///   fingers, or the TPM rejected the unseal (re-enrolment
    ///   forced auth-value mismatch). Caller routes to the typed
    ///   password dialog — the primary vault is unaffected.
    /// * `Err(_)` — TPM unreachable or on-disk envelope malformed.
    pub async fn read_biometric_password(
        support_dir: &str,
    ) -> Result<Option<Vec<u8>>, LinuxVaultError> {
        let path = bio_password_path(support_dir);
        if !path.exists() {
            return Ok(None);
        }
        if !is_available() {
            return Err(LinuxVaultError::TpmUnavailable("tpm probe failed".into()));
        }
        let Some(auth_hash) = crate::platform::linux::fprintd::get_enrolment_hash().await else {
            return Ok(None);
        };
        let path_owned = path.clone();
        let unsealed =
            tokio::task::spawn_blocking(move || -> Result<Option<Vec<u8>>, LinuxVaultError> {
                let raw = std::fs::read(&path_owned)
                    .map_err(|e| LinuxVaultError::Io(format!("read overlay: {e}")))?;
                let body = lfs_os_security::hardware_tier_vault::parse_envelope_header(
                    &raw,
                    lfs_os_security::hardware_tier_vault::HW_VAULT_PLATFORM_LINUX,
                )
                .map_err(|_| LinuxVaultError::Corrupt("overlay header mismatch".into()))?;
                let sealed = parse_bio_overlay_body(body)?;
                match lfs_os_security::linux::tpm::unseal(
                    &lfs_os_security::linux::tpm::TpmConfig::default(),
                    sealed,
                    &auth_hash,
                ) {
                    Ok(plain) => Ok(Some(plain)),
                    // Wrong auth (re-enrolment changed the hash) or
                    // TPM-key invalidation surfaces as a generic
                    // backend error from `tpm2-tools`; map to
                    // `Ok(None)` so the unlock UI routes back to the
                    // typed password path.
                    Err(_) => Ok(None),
                }
            })
            .await
            .map_err(|e| LinuxVaultError::Io(format!("overlay blocking task: {e}")))??;
        Ok(unsealed)
    }

    /// Drop the overlay envelope. Missing-file is `Ok(())`; the
    /// TPM has no persistent key for this path so there is no
    /// hardware-side state to revoke separately — re-enrolling
    /// fingerprints already invalidates the auth value, and a
    /// fresh `store_biometric_password` overwrites the file.
    pub fn clear_biometric_password(support_dir: &str) -> Result<(), LinuxVaultError> {
        let path = bio_password_path(support_dir);
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(LinuxVaultError::Io(format!("remove overlay: {e}"))),
        }
    }

    /// Parse the single length-prefixed sealed frame inside the
    /// overlay envelope body. Same `checked_add` discipline as the
    /// Windows `parse_bio_envelope` so a hostile length prefix
    /// cannot wrap the size calculation.
    fn parse_bio_overlay_body(raw: &[u8]) -> Result<&[u8], LinuxVaultError> {
        if raw.len() < 4 {
            return Err(LinuxVaultError::Corrupt("overlay: truncated".into()));
        }
        let sealed_len = u32::from_be_bytes([raw[0], raw[1], raw[2], raw[3]]) as usize;
        let sealed_end = 4usize
            .checked_add(sealed_len)
            .ok_or_else(|| LinuxVaultError::Corrupt("overlay: sealed_len overflow".into()))?;
        if raw.len() < sealed_end {
            return Err(LinuxVaultError::Corrupt("overlay: truncated sealed".into()));
        }
        Ok(&raw[4..sealed_end])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_decode_round_trips() {
        let salt = vec![0x33u8; 32];
        let sealed = vec![0x44u8; 96];
        let blob = encode_linux_blob(&salt, &sealed);
        let decoded = decode_linux_blob(&blob).unwrap();
        assert_eq!(decoded.salt, salt);
        assert_eq!(decoded.sealed, sealed);
    }

    #[test]
    fn decode_rejects_malformed_json() {
        assert!(decode_linux_blob("not-json").is_err());
        assert!(decode_linux_blob("[]").is_err());
    }

    #[test]
    fn decode_rejects_missing_fields() {
        assert!(decode_linux_blob("{}").is_err());
        assert!(decode_linux_blob(r#"{"salt":"YQ=="}"#).is_err());
        assert!(decode_linux_blob(r#"{"sealed":"YQ=="}"#).is_err());
    }

    #[test]
    fn decode_rejects_non_string_fields() {
        assert!(decode_linux_blob(r#"{"salt":1,"sealed":"YQ=="}"#).is_err());
        assert!(decode_linux_blob(r#"{"salt":"YQ==","sealed":[]}"#).is_err());
    }

    #[test]
    fn decode_rejects_invalid_base64() {
        let blob = r#"{"salt":"!!!","sealed":"YQ=="}"#;
        assert!(decode_linux_blob(blob).is_err());
    }

    #[test]
    fn decode_rejects_empty_decoded_bytes() {
        // A legitimate seal is never zero-length; a tampered file
        // with empty fields must not parse as a valid blob.
        assert!(decode_linux_blob(r#"{"salt":"","sealed":""}"#).is_err());
    }

    #[test]
    fn resolve_password_branch_hmacs_typed_secret() {
        let salt = vec![0x02u8; 32];
        let with_pw = resolve_auth_value(AuthIntent::Password("hunter2"), &salt);
        let manual = hmac_sha256(&salt, b"hunter2");
        assert_eq!(with_pw.map(|z| z.to_vec()), Some(manual.to_vec()));
    }

    #[test]
    fn resolve_password_branch_rejects_empty_secret() {
        let salt = vec![0x03u8; 32];
        assert_eq!(resolve_auth_value(AuthIntent::Password(""), &salt), None);
    }

    #[test]
    fn resolve_biometric_branch_hmacs_fprintd_hash() {
        let salt = vec![0x04u8; 32];
        let hash = vec![0xAB; 32];
        let v = resolve_auth_value(AuthIntent::Biometric(&hash), &salt);
        let manual = hmac_sha256(&salt, &hash);
        assert_eq!(v.map(|z| z.to_vec()), Some(manual.to_vec()));
    }

    #[test]
    fn resolve_biometric_branch_rejects_empty_hash() {
        let salt = vec![0x05u8; 32];
        assert_eq!(resolve_auth_value(AuthIntent::Biometric(&[]), &salt), None);
    }

    #[test]
    fn v6_v7_marker_probe_reports_absent_then_present() {
        // Mismatch detection regression — a v7 config carries
        // `password=true` but the wrapped key was sealed under an
        // empty PIN-HMAC by the pre-flip install. The
        // ConfigV6ToV7 migration writes this marker so bootstrap
        // can route the password-set wizard ahead of the unlock
        // path. A missing marker → no wizard required.
        let dir = tempfile::TempDir::new().unwrap();
        assert!(!hardware_password_set_wizard_required(dir.path()));
        write_v6_v7_password_set_marker(dir.path()).unwrap();
        assert!(hardware_password_set_wizard_required(dir.path()));
        clear_v6_v7_password_set_marker(dir.path()).unwrap();
        assert!(!hardware_password_set_wizard_required(dir.path()));
    }

    #[test]
    fn v6_v7_marker_write_is_idempotent() {
        // A migration that re-runs over an already-flipped config
        // must not blow up on the second pass — the marker write
        // is re-entrant.
        let dir = tempfile::TempDir::new().unwrap();
        write_v6_v7_password_set_marker(dir.path()).unwrap();
        write_v6_v7_password_set_marker(dir.path()).unwrap();
        assert!(hardware_password_set_wizard_required(dir.path()));
    }

    #[test]
    fn v6_v7_marker_clear_on_missing_target_is_ok() {
        // The wizard's clear call lands without branching on
        // pre-existence — a missing target is treated as success.
        let dir = tempfile::TempDir::new().unwrap();
        clear_v6_v7_password_set_marker(dir.path()).unwrap();
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn linux_overlay_is_stored_returns_false_for_fresh_dir() {
        // A fresh support_dir has no overlay file; the probe must
        // not panic on a missing path and reports `false`.
        let dir = tempfile::TempDir::new().unwrap();
        assert!(!super::linux::is_biometric_password_stored(
            dir.path().to_str().unwrap()
        ));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn linux_overlay_clear_on_missing_file_is_ok() {
        // The wizard / tier-reset cascade calls clear without
        // branching on pre-existence — missing target = success.
        let dir = tempfile::TempDir::new().unwrap();
        super::linux::clear_biometric_password(dir.path().to_str().unwrap()).expect("clear noop");
    }

    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn linux_overlay_store_errors_when_tpm_unavailable() {
        use lfs_os_security::linux::tpm::{probe, TpmConfig, TpmProbeResult};
        // Skip on hosts that actually have a working TPM — those
        // exercise the success path through the per-platform
        // validation matrix instead.
        if matches!(probe(&TpmConfig::default()), TpmProbeResult::Available) {
            return;
        }
        let dir = tempfile::TempDir::new().unwrap();
        let result =
            super::linux::store_biometric_password(dir.path().to_str().unwrap(), b"hunter2").await;
        assert!(matches!(
            result,
            Err(super::linux::LinuxVaultError::TpmUnavailable(_))
        ));
    }

    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn linux_overlay_read_returns_none_when_file_absent() {
        // No overlay file → caller falls back to the typed password
        // path. Does not consult the TPM or fprintd.
        let dir = tempfile::TempDir::new().unwrap();
        let result = super::linux::read_biometric_password(dir.path().to_str().unwrap()).await;
        assert!(matches!(result, Ok(None)));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn linux_overlay_file_name_matches_wipe_registry() {
        // The wipe-registry tripwire (`every_known_artefact_is_in_managed_files`)
        // cross-references this constant. A rename here without a
        // matching MANAGED_FILES entry would leave an orphan file
        // behind on every wipe.
        assert_eq!(
            super::linux::BIO_PASSWORD_FILE,
            "hardware_vault_password_overlay_linux.bin"
        );
    }

    /// fprintd hash determinism — same enrolment state must yield
    /// the same auth value byte-for-byte across processes. Without
    /// this invariant the seal at install time and the unseal at
    /// unlock time would derive different keys and the user would
    /// be locked out of the overlay on the very next launch. The
    /// formula lives in `lfs_core::platform::linux::fprintd::get_enrolment_hash`
    /// (SHA-256 of sorted-`:`-joined finger names); we re-derive it
    /// here without consulting fprintd so the test is hermetic.
    #[cfg(target_os = "linux")]
    #[test]
    fn fprintd_hash_formula_is_deterministic() {
        use sha2::{Digest, Sha256};
        fn derive(fingers: &[&str]) -> [u8; 32] {
            let mut sorted: Vec<String> = fingers.iter().map(|s| (*s).to_string()).collect();
            sorted.sort();
            let joined = sorted.join(":");
            let mut hasher = Sha256::new();
            hasher.update(joined.as_bytes());
            let digest = hasher.finalize();
            let mut out = [0u8; 32];
            out.copy_from_slice(&digest);
            out
        }
        let a = derive(&["right-index", "left-thumb"]);
        let b = derive(&["left-thumb", "right-index"]);
        assert_eq!(a, b, "sort order must not affect the hash");
        let c = derive(&["right-index"]);
        assert_ne!(
            a, c,
            "dropping an enrolled finger must flip the hash so the overlay invalidates"
        );
    }
}
