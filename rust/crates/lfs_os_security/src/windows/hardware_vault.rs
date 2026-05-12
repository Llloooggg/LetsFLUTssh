//! Windows hardware-tier vault — Tier 4 Rust port that retires the
//! C++ NCrypt MethodChannel plugin under `windows/runner/`.
//!
//! Mirrors the Apple Secure Enclave shape (`super::super::hardware_tier_vault::apple`):
//! a TPM-bound persistent key wraps the SQLCipher master key under
//! a `(pin_hmac, wrapped)` envelope on disk; unseal asks NCrypt to
//! decrypt the envelope under the same persistent key.
//!
//! ## CNG provider + key shape
//!
//! * Provider — `Microsoft Platform Crypto Provider` (`MS_PLATFORM_KEY_STORAGE_PROVIDER`).
//!   This is the TPM-backed CNG provider; key material lives inside
//!   the TPM and is not exportable. RSA-2048 key with the OAEP-SHA-256
//!   padding policy applied at use-time (NCrypt sets the padding
//!   per-call via `NCRYPT_PAD_OAEP_FLAG`).
//! * Primary persistent key name — `letsflutssh_hardware_vault_v1`.
//!   The `_v1` suffix anchors the format against future re-key arcs:
//!   a v2 lands as a separate persistent key so v1 holders aren't
//!   bricked mid-rollout.
//! * Wrap — RSA-OAEP-SHA-256 over the 32-byte AES-256 DB key.
//!   Output goes into the disk envelope alongside the auth-value
//!   (`pin_hmac`) the unseal path verifies in constant time before
//!   ever calling NCrypt.
//!
//! ## Biometric overlay
//!
//! A SECOND persistent key, `letsflutssh_hardware_vault_bio_v1`,
//! seals the user's master password under a Hello-gated NCrypt
//! key. Same algorithm (RSA-2048 OAEP-SHA-256) and same
//! `NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`
//! UI policy so every unwrap fires the Hello dialog. The overlay
//! key is intentionally separate from the primary so a biometric
//! enrolment change (new fingerprint set / PIN reset) invalidates
//! only the overlay — the primary vault keeps working under the
//! typed password.
//!
//! ## Wire format on disk
//!
//! * Primary — `support_dir/hardware_vault.bin`. 4-byte BE
//!   length-prefixed pairs: `[hmac_len][hmac bytes][wrapped_len][wrapped bytes]`.
//!   Same shape `super::super::hardware_tier_vault::write_len_prefixed`
//!   produces on the Apple path.
//! * Biometric overlay —
//!   `support_dir/hardware_vault_password_overlay_windows.bin`.
//!   Single length-prefixed frame: `[wrapped_len][wrapped bytes]`.
//!   No auth-value gate (the Hello prompt is the gate); the file
//!   only carries the wrapped password bytes.
//!
//! ## Failure mapping
//!
//! `NCryptOpenKey` → `NTE_BAD_KEYSET` is treated as
//! "vault revoked" (TPM cleared / persistent key removed): the
//! caller sees `Ok(None)` and the unlock cascade falls through to
//! the tier-reset dialog. `ERROR_INVALID_HANDLE` (raw 0x6) on any
//! NCrypt call triggers one retry against a freshly opened
//! provider + key — the previous handle may have been invalidated
//! by a sibling `clear_hardware_vault` racing with this operation.
//! Every other CNG failure surfaces as
//! [`HardwareVaultError::Backend`] with the formatted HRESULT for
//! triage logs.

use std::path::{Path, PathBuf};

use windows::core::{Error as WinError, PCWSTR};
use windows::Win32::Foundation::NTE_BAD_KEYSET;
use windows::Win32::Security::Cryptography::{
    NCryptCreatePersistedKey, NCryptDecrypt, NCryptDeleteKey, NCryptEncrypt, NCryptFinalizeKey,
    NCryptFreeObject, NCryptOpenKey, NCryptOpenStorageProvider, NCryptSetProperty,
    BCRYPT_OAEP_PADDING_INFO, BCRYPT_RSA_ALGORITHM, BCRYPT_SHA256_ALGORITHM, CERT_KEY_SPEC,
    MS_PLATFORM_KEY_STORAGE_PROVIDER, NCRYPT_EXPORT_POLICY_PROPERTY, NCRYPT_FLAGS, NCRYPT_HANDLE,
    NCRYPT_KEY_HANDLE, NCRYPT_LENGTH_PROPERTY, NCRYPT_OVERWRITE_KEY_FLAG, NCRYPT_PAD_OAEP_FLAG,
    NCRYPT_PROV_HANDLE, NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG, NCRYPT_UI_POLICY,
    NCRYPT_UI_POLICY_PROPERTY, NCRYPT_UI_PROTECT_KEY_FLAG,
};

use crate::hardware_tier_vault::{write_len_prefixed, HardwareVaultError};

/// Filename under `support_dir` for the primary vault envelope.
/// Matches the Apple wire-shape so the wipe-registry covers it
/// without a Windows-specific entry.
pub const VAULT_FILE: &str = "hardware_vault.bin";

/// Filename under `support_dir` for the biometric-overlay
/// envelope (wrapped master password sealed under the
/// Hello-gated overlay key). Exposed `pub` so the wipe-registry
/// coverage test can cross-reference the canonical name.
pub const BIO_PASSWORD_FILE: &str = "hardware_vault_password_overlay_windows.bin";

/// CNG persistent-key name as a UTF-16 null-terminated buffer.
/// The `_v1` suffix anchors the format against future re-key
/// migrations.
const VAULT_KEY_NAME: &[u16] = &[
    'l' as u16, 'e' as u16, 't' as u16, 's' as u16, 'f' as u16, 'l' as u16, 'u' as u16, 't' as u16,
    's' as u16, 's' as u16, 'h' as u16, '_' as u16, 'h' as u16, 'a' as u16, 'r' as u16, 'd' as u16,
    'w' as u16, 'a' as u16, 'r' as u16, 'e' as u16, '_' as u16, 'v' as u16, 'a' as u16, 'u' as u16,
    'l' as u16, 't' as u16, '_' as u16, 'v' as u16, '1' as u16, 0u16,
];

/// CNG persistent-key name for the biometric overlay. Separate
/// from [`VAULT_KEY_NAME`] so a Hello-enrolment change wipes only
/// the overlay (Windows refuses to surface a stale `NCRYPT_UI_POLICY`
/// key after PIN reset). UTF-16 null-terminated.
const BIO_VAULT_KEY_NAME: &[u16] = &[
    'l' as u16, 'e' as u16, 't' as u16, 's' as u16, 'f' as u16, 'l' as u16, 'u' as u16, 't' as u16,
    's' as u16, 's' as u16, 'h' as u16, '_' as u16, 'h' as u16, 'a' as u16, 'r' as u16, 'd' as u16,
    'w' as u16, 'a' as u16, 'r' as u16, 'e' as u16, '_' as u16, 'v' as u16, 'a' as u16, 'u' as u16,
    'l' as u16, 't' as u16, '_' as u16, 'b' as u16, 'i' as u16, 'o' as u16, '_' as u16, 'v' as u16,
    '1' as u16, 0u16,
];

const RSA_KEY_LENGTH_BITS: u32 = 2048;
const RSA_KEY_LENGTH_BYTES: usize = (RSA_KEY_LENGTH_BITS / 8) as usize;

/// Win32 `ERROR_INVALID_HANDLE`. Raised when an NCrypt entry point
/// is called against a handle the kernel has already invalidated —
/// canonical sibling-call after `NCryptDeleteKey` ran on the same
/// persistent name. Drives the one-shot retry path.
const WIN_ERROR_INVALID_HANDLE: u32 = 0x0000_0006;

fn vault_path(support_dir: &str) -> PathBuf {
    Path::new(support_dir).join(VAULT_FILE)
}

fn bio_password_path(support_dir: &str) -> PathBuf {
    Path::new(support_dir).join(BIO_PASSWORD_FILE)
}

fn fmt_win(label: &str, e: WinError) -> HardwareVaultError {
    HardwareVaultError::Backend(format!("{label}: 0x{:08x}", e.code().0 as u32))
}

fn is_invalid_handle(e: &WinError) -> bool {
    (e.code().0 as u32) == WIN_ERROR_INVALID_HANDLE
}

/// Drop every cached NCrypt handle this module holds. Today the
/// module is stateless — every entry point opens the provider +
/// key locally and releases via the Owned wrappers — so this is a
/// no-op marker. Wired into `clear` and `clear_biometric_password`
/// so a future revision that adds a `LazyLock<NCRYPT_PROV_HANDLE>`
/// cache has a single invalidation hook the tier-transition path
/// already calls. Documented invariant: any cached NCrypt state
/// added later MUST register a drop here.
pub fn reset_cached_handles() {
    // Stateless today — left as the canonical hook for future
    // caches. Sibling crate `ncrypt_ssh` is also stateless;
    // adding a cache there should bring its reset in here too.
}

/// True when the Microsoft Platform Crypto Provider can be opened —
/// the canonical "TPM 2.0 reachable on this host" probe. Falls
/// back to `false` on any error (no provider, GPO block, etc).
#[must_use]
pub fn is_available() -> bool {
    let mut provider = NCRYPT_PROV_HANDLE::default();
    let result =
        unsafe { NCryptOpenStorageProvider(&mut provider, MS_PLATFORM_KEY_STORAGE_PROVIDER, 0) };
    if result.is_ok() {
        // Wrapping in Owned so an early panic in the bool-cast
        // (impossible today but cheap insurance) still releases.
        let _ = OwnedNCryptProvHandle(provider);
        true
    } else {
        false
    }
}

/// True when `support_dir/hardware_vault.bin` exists. Pure
/// path-stat — does not invoke NCrypt.
#[must_use]
pub fn is_stored(support_dir: &str) -> bool {
    vault_path(support_dir).exists()
}

/// Wrap `db_key` under the persistent CNG key and write the
/// envelope to disk. `pin_hmac` is the caller-derived auth value
/// (HMAC-SHA256(salt, pin)) — empty for the passwordless flow.
///
/// If the persistent key is missing, creates it with
/// `NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`
/// so unseal fires the Hello / PIN UI automatically.
pub fn store(support_dir: &str, db_key: &[u8], pin_hmac: &[u8]) -> Result<(), HardwareVaultError> {
    let wrapped = with_invalid_handle_retry(|| {
        let provider = OwnedNCryptProvHandle(open_provider()?);
        let key = OwnedNCryptKeyHandle(open_or_create_key(provider.handle(), VAULT_KEY_NAME)?);
        encrypt_under_key(key.handle(), db_key)
    })?;

    let path = vault_path(support_dir);
    let mut body = Vec::new();
    write_len_prefixed(&mut body, pin_hmac)?;
    write_len_prefixed(&mut body, &wrapped)?;
    let blob = crate::hardware_tier_vault::prepend_envelope_header(
        crate::hardware_tier_vault::HW_VAULT_PLATFORM_WINDOWS,
        &body,
    );
    crate::hardware_tier_vault::os_atomic_write_0600(&path, &blob)
}

/// Read + unwrap. Returns `Ok(None)` for missing file, `pin_hmac`
/// mismatch (constant-time compared), or TPM-cleared revocation;
/// `Err` for unexpected NCrypt failures. Wrong PIN never reaches
/// NCrypt — the local-only HMAC gate matches the Apple path's
/// behaviour.
pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    let path = vault_path(support_dir);
    if !path.exists() {
        return Ok(None);
    }
    let raw = std::fs::read(&path).map_err(|e| HardwareVaultError::Io(format!("read: {e}")))?;
    let body = crate::hardware_tier_vault::parse_envelope_header(
        &raw,
        crate::hardware_tier_vault::HW_VAULT_PLATFORM_WINDOWS,
    )?;
    let (saved_hmac, wrapped) = parse_envelope(body)?;

    use subtle::ConstantTimeEq;
    if pin_hmac.ct_eq(saved_hmac).unwrap_u8() != 1 {
        return Ok(None);
    }

    let outcome = with_invalid_handle_retry(|| {
        let provider = OwnedNCryptProvHandle(open_provider()?);
        let key = match open_existing_key(provider.handle(), VAULT_KEY_NAME) {
            Ok(k) => OwnedNCryptKeyHandle(k),
            Err(e) => return Err(e),
        };
        decrypt_under_key(key.handle(), wrapped).map(Some)
    });

    match outcome {
        Ok(plaintext) => Ok(plaintext),
        Err(HardwareVaultError::Backend(ref msg))
            if msg.contains(&format!("{:08x}", NTE_BAD_KEYSET.0 as u32)) =>
        {
            // TPM cleared / persistent key revoked → vault is gone.
            // Dart routes through TierResetDialog.
            Ok(None)
        }
        Err(e) => Err(e),
    }
}

/// Best-effort delete: drops the on-disk envelope and the TPM
/// persistent key. Missing pieces are not errors.
pub fn clear(support_dir: &str) -> Result<(), HardwareVaultError> {
    // Drop the envelope first so a partial failure on the NCrypt
    // delete still leaves the user without a recoverable on-disk
    // state.
    let path = vault_path(support_dir);
    match std::fs::remove_file(&path) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(HardwareVaultError::Io(format!("remove: {e}"))),
    }

    // Best-effort NCrypt key delete. If the persistent key was
    // never created, `NCryptOpenKey` returns `NTE_BAD_KEYSET` —
    // swallow and continue.
    delete_persistent_key(VAULT_KEY_NAME);

    // Cache-invalidation hook. No-op today; load-bearing once a
    // module-level NCrypt cache lands.
    reset_cached_handles();

    Ok(())
}

// ── biometric password overlay ──────────────────────────────────
//
// A second NCrypt persistent key (`letsflutssh_hardware_vault_bio_v1`)
// gated by `NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`.
// The Hello prompt fires on every unwrap so the user can release
// the sealed master password with a biometric / PIN gesture alone.
// The seal-side call also fires Hello once at finalize time (Windows
// binds UI policy to *use* of the key, and the encrypt is a use).

/// Wrap `value` under the biometric-overlay key and persist to
/// disk. Fires the Hello ceremony on the create-and-encrypt path
/// the first time, and on every subsequent unwrap.
pub fn store_biometric_password(support_dir: &str, value: &[u8]) -> Result<(), HardwareVaultError> {
    let wrapped = with_invalid_handle_retry(|| {
        let provider = OwnedNCryptProvHandle(open_provider()?);
        let key = OwnedNCryptKeyHandle(open_or_create_key(provider.handle(), BIO_VAULT_KEY_NAME)?);
        encrypt_under_key(key.handle(), value)
    })?;

    let path = bio_password_path(support_dir);
    let mut body = Vec::new();
    write_len_prefixed(&mut body, &wrapped)?;
    let blob = crate::hardware_tier_vault::prepend_envelope_header(
        crate::hardware_tier_vault::HW_VAULT_PLATFORM_WINDOWS,
        &body,
    );
    crate::hardware_tier_vault::os_atomic_write_0600(&path, &blob)
}

/// Unwrap the biometric-overlay password — fires the Hello
/// ceremony at NCrypt-decrypt time. `Ok(None)` for missing file;
/// `Err` for backend / cancellation / no-Hello-configured.
pub fn read_biometric_password(support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    let path = bio_password_path(support_dir);
    if !path.exists() {
        return Ok(None);
    }
    let raw =
        std::fs::read(&path).map_err(|e| HardwareVaultError::Io(format!("read overlay: {e}")))?;
    let body = crate::hardware_tier_vault::parse_envelope_header(
        &raw,
        crate::hardware_tier_vault::HW_VAULT_PLATFORM_WINDOWS,
    )?;
    let wrapped = parse_bio_envelope(body)?;

    let outcome = with_invalid_handle_retry(|| {
        let provider = OwnedNCryptProvHandle(open_provider()?);
        let key = OwnedNCryptKeyHandle(open_existing_key(provider.handle(), BIO_VAULT_KEY_NAME)?);
        decrypt_under_key(key.handle(), wrapped).map(Some)
    });

    match outcome {
        Ok(plaintext) => Ok(plaintext),
        Err(HardwareVaultError::Backend(ref msg))
            if msg.contains(&format!("{:08x}", NTE_BAD_KEYSET.0 as u32)) =>
        {
            // Overlay key revoked (Hello re-enrolled / TPM cleared).
            // Treat as "no overlay present" so the unlock cascade
            // falls back to the typed master password path.
            Ok(None)
        }
        Err(e) => Err(e),
    }
}

/// Drop the overlay envelope and the overlay NCrypt key.
/// Missing pieces are not errors.
pub fn clear_biometric_password(support_dir: &str) -> Result<(), HardwareVaultError> {
    let path = bio_password_path(support_dir);
    match std::fs::remove_file(&path) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(HardwareVaultError::Io(format!("remove overlay: {e}"))),
    }

    delete_persistent_key(BIO_VAULT_KEY_NAME);

    // Same cache-invalidation hook as `clear`. Load-bearing once a
    // module-level NCrypt cache lands.
    reset_cached_handles();

    Ok(())
}

/// Pure path-stat — the overlay file's presence is the contract
/// for "biometric shortcut is wired up". The NCrypt key may have
/// been revoked under us (Hello re-enrolment); the unwrap path
/// surfaces that as `Ok(None)` and the unlock cascade re-routes.
#[must_use]
pub fn is_biometric_password_stored(support_dir: &str) -> bool {
    bio_password_path(support_dir).exists()
}

// ── internals ────────────────────────────────────────────────────

fn free_obj(handle: usize) {
    if handle != 0 {
        let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(handle)) };
    }
}

/// Run `op`, and if it surfaces `ERROR_INVALID_HANDLE` re-run it
/// once. The second run opens a fresh provider + key, sidestepping
/// any handle the kernel invalidated between the first open and
/// the first NCrypt call (canonical: a sibling `clear_hardware_vault`
/// fired `NCryptDeleteKey` against the same persistent name).
/// A second invalid-handle failure propagates as-is.
fn with_invalid_handle_retry<T, F>(mut op: F) -> Result<T, HardwareVaultError>
where
    F: FnMut() -> Result<T, HardwareVaultError>,
{
    match op() {
        Ok(v) => Ok(v),
        Err(HardwareVaultError::Backend(ref msg))
            if msg.contains(&format!("{WIN_ERROR_INVALID_HANDLE:08x}")) =>
        {
            // One retry only. The cache-invalidation hook drops
            // any stale module-level cache before the retry runs.
            reset_cached_handles();
            op()
        }
        Err(e) => Err(e),
    }
}

/// Drop a persistent NCrypt key by UTF-16 name. Best-effort —
/// missing key surfaces as `NTE_BAD_KEYSET` from `NCryptOpenKey`
/// and is silently swallowed.
fn delete_persistent_key(name: &[u16]) {
    if let Ok(provider_raw) = open_provider() {
        let provider = OwnedNCryptProvHandle(provider_raw);
        let mut key = NCRYPT_KEY_HANDLE::default();
        let open_status = unsafe {
            NCryptOpenKey(
                provider.handle(),
                &mut key,
                PCWSTR(name.as_ptr()),
                CERT_KEY_SPEC(0),
                NCRYPT_FLAGS(0),
            )
        };
        if open_status.is_ok() {
            // `NCryptDeleteKey` consumes the handle on success;
            // the Owned wrapper handles either path.
            let _ = unsafe { NCryptDeleteKey(key, 0) };
            let _ = OwnedNCryptKeyHandle(key);
        }
    }
}

/// RAII wrapper around an `NCRYPT_PROV_HANDLE`. Drop calls
/// `NCryptFreeObject` so every code path — Ok return, `?` early
/// exit, panic — releases the handle.
struct OwnedNCryptProvHandle(NCRYPT_PROV_HANDLE);

impl OwnedNCryptProvHandle {
    fn handle(&self) -> NCRYPT_PROV_HANDLE {
        self.0
    }
}

impl Drop for OwnedNCryptProvHandle {
    fn drop(&mut self) {
        free_obj(self.0 .0);
    }
}

/// RAII wrapper around an `NCRYPT_KEY_HANDLE`. Same shape as
/// `OwnedNCryptProvHandle`.
struct OwnedNCryptKeyHandle(NCRYPT_KEY_HANDLE);

impl OwnedNCryptKeyHandle {
    fn handle(&self) -> NCRYPT_KEY_HANDLE {
        self.0
    }
}

impl Drop for OwnedNCryptKeyHandle {
    fn drop(&mut self) {
        free_obj(self.0 .0);
    }
}

fn open_provider() -> Result<NCRYPT_PROV_HANDLE, HardwareVaultError> {
    let mut provider = NCRYPT_PROV_HANDLE::default();
    unsafe { NCryptOpenStorageProvider(&mut provider, MS_PLATFORM_KEY_STORAGE_PROVIDER, 0) }
        .map_err(|e| {
            if is_invalid_handle(&e) {
                // Surface as Backend so `with_invalid_handle_retry`
                // catches it and reruns.
                HardwareVaultError::Backend(format!(
                    "NCryptOpenStorageProvider: 0x{:08x}",
                    e.code().0 as u32
                ))
            } else {
                fmt_win("NCryptOpenStorageProvider", e)
            }
        })?;
    Ok(provider)
}

fn open_existing_key(
    provider: NCRYPT_PROV_HANDLE,
    name: &[u16],
) -> Result<NCRYPT_KEY_HANDLE, HardwareVaultError> {
    let mut key = NCRYPT_KEY_HANDLE::default();
    unsafe {
        NCryptOpenKey(
            provider,
            &mut key,
            PCWSTR(name.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| fmt_win("NCryptOpenKey", e))?;
    Ok(key)
}

fn open_or_create_key(
    provider: NCRYPT_PROV_HANDLE,
    name: &[u16],
) -> Result<NCRYPT_KEY_HANDLE, HardwareVaultError> {
    // Try existing first; create on NTE_BAD_KEYSET.
    match open_existing_key(provider, name) {
        Ok(k) => return Ok(k),
        Err(HardwareVaultError::Backend(msg))
            if msg.contains(&format!("{:08x}", NTE_BAD_KEYSET.0 as u32)) => {}
        Err(e) => return Err(e),
    }

    let mut key = NCRYPT_KEY_HANDLE::default();
    unsafe {
        NCryptCreatePersistedKey(
            provider,
            &mut key,
            BCRYPT_RSA_ALGORITHM,
            PCWSTR(name.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_OVERWRITE_KEY_FLAG,
        )
    }
    .map_err(|e| fmt_win("NCryptCreatePersistedKey", e))?;

    // 2048-bit RSA.
    let length_bytes = RSA_KEY_LENGTH_BITS.to_le_bytes();
    if let Err(e) = unsafe {
        NCryptSetProperty(
            NCRYPT_HANDLE(key.0),
            NCRYPT_LENGTH_PROPERTY,
            &length_bytes,
            NCRYPT_FLAGS(0),
        )
    } {
        free_obj(key.0);
        return Err(fmt_win("NCryptSetProperty(LENGTH)", e));
    }

    // UI policy: force the Hello / PIN prompt at decrypt time.
    // Same flags for primary + overlay so both surfaces fire the
    // Hello ceremony on every use; the primary additionally gates
    // the local HMAC-of-PIN check before any NCrypt call.
    let policy = NCRYPT_UI_POLICY {
        dwVersion: 1,
        dwFlags: NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG,
        pszCreationTitle: PCWSTR::null(),
        pszFriendlyName: PCWSTR::null(),
        pszDescription: PCWSTR::null(),
    };

    let policy_bytes = unsafe {
        std::slice::from_raw_parts(
            (&policy as *const NCRYPT_UI_POLICY) as *const u8,
            std::mem::size_of::<NCRYPT_UI_POLICY>(),
        )
    };
    if let Err(e) = unsafe {
        NCryptSetProperty(
            NCRYPT_HANDLE(key.0),
            NCRYPT_UI_POLICY_PROPERTY,
            policy_bytes,
            NCRYPT_FLAGS(0),
        )
    } {
        free_obj(key.0);
        return Err(fmt_win("NCryptSetProperty(UI_POLICY)", e));
    }

    // Pin export policy to 0 (NONE) so the private key is non-
    // exportable. The TPM-backed `MS_PLATFORM_KEY_STORAGE_PROVIDER`
    // already enforces non-exportability, but the software-KSP
    // fallback path defaults to exportable; setting the property
    // explicitly closes the gap defense-in-depth.
    let export_policy: u32 = 0;
    if let Err(e) = unsafe {
        NCryptSetProperty(
            NCRYPT_HANDLE(key.0),
            NCRYPT_EXPORT_POLICY_PROPERTY,
            &export_policy.to_le_bytes(),
            NCRYPT_FLAGS(0),
        )
    } {
        free_obj(key.0);
        return Err(fmt_win("NCryptSetProperty(EXPORT_POLICY)", e));
    }

    if let Err(e) = unsafe { NCryptFinalizeKey(key, NCRYPT_FLAGS(0)) } {
        free_obj(key.0);
        return Err(fmt_win("NCryptFinalizeKey", e));
    }

    Ok(key)
}

fn encrypt_under_key(
    key: NCRYPT_KEY_HANDLE,
    plaintext: &[u8],
) -> Result<Vec<u8>, HardwareVaultError> {
    let padding = oaep_padding_info();
    let padding_ptr = (&padding as *const BCRYPT_OAEP_PADDING_INFO) as *const std::ffi::c_void;

    let mut output_size: u32 = 0;
    unsafe {
        NCryptEncrypt(
            key,
            Some(plaintext),
            Some(padding_ptr),
            None,
            &mut output_size,
            NCRYPT_PAD_OAEP_FLAG,
        )
    }
    .map_err(|e| fmt_win("NCryptEncrypt(probe)", e))?;
    let mut buffer = vec![0u8; output_size as usize];
    let mut written: u32 = 0;
    unsafe {
        NCryptEncrypt(
            key,
            Some(plaintext),
            Some(padding_ptr),
            Some(&mut buffer),
            &mut written,
            NCRYPT_PAD_OAEP_FLAG,
        )
    }
    .map_err(|e| fmt_win("NCryptEncrypt", e))?;
    buffer.truncate(written as usize);
    Ok(buffer)
}

fn decrypt_under_key(
    key: NCRYPT_KEY_HANDLE,
    ciphertext: &[u8],
) -> Result<Vec<u8>, HardwareVaultError> {
    let padding = oaep_padding_info();
    let padding_ptr = (&padding as *const BCRYPT_OAEP_PADDING_INFO) as *const std::ffi::c_void;

    let mut buffer = vec![0u8; RSA_KEY_LENGTH_BYTES];
    let mut written: u32 = 0;
    unsafe {
        NCryptDecrypt(
            key,
            Some(ciphertext),
            Some(padding_ptr),
            Some(&mut buffer),
            &mut written,
            NCRYPT_PAD_OAEP_FLAG,
        )
    }
    .map_err(|e| fmt_win("NCryptDecrypt", e))?;
    buffer.truncate(written as usize);
    Ok(buffer)
}

fn oaep_padding_info() -> BCRYPT_OAEP_PADDING_INFO {
    BCRYPT_OAEP_PADDING_INFO {
        pszAlgId: BCRYPT_SHA256_ALGORITHM,
        pbLabel: std::ptr::null_mut(),
        cbLabel: 0,
    }
}

fn parse_envelope(raw: &[u8]) -> Result<(&[u8], &[u8]), HardwareVaultError> {
    // All length-prefix arithmetic uses `checked_add` so a hostile
    // envelope with `hmac_len = u32::MAX - 3` cannot wrap the
    // calculation around to a small `hmac_end`, slipping past the
    // upcoming bounds check and reading attacker-controlled bytes
    // out of the trailing slice. On 32-bit Windows targets the
    // raw `hmac_end + 4` add could otherwise wrap silently.
    if raw.len() < 4 {
        return Err(HardwareVaultError::Backend("envelope: truncated".into()));
    }
    let hmac_len = u32::from_be_bytes([raw[0], raw[1], raw[2], raw[3]]) as usize;
    let hmac_end = 4usize
        .checked_add(hmac_len)
        .ok_or_else(|| HardwareVaultError::Backend("envelope: hmac_len overflow".into()))?;
    let after_hmac_len = hmac_end
        .checked_add(4)
        .ok_or_else(|| HardwareVaultError::Backend("envelope: hmac_end overflow".into()))?;
    if raw.len() < after_hmac_len {
        return Err(HardwareVaultError::Backend(
            "envelope: truncated hmac".into(),
        ));
    }
    let wrapped_len = u32::from_be_bytes([
        raw[hmac_end],
        raw[hmac_end + 1],
        raw[hmac_end + 2],
        raw[hmac_end + 3],
    ]) as usize;
    let wrapped_start = after_hmac_len;
    let wrapped_end = wrapped_start
        .checked_add(wrapped_len)
        .ok_or_else(|| HardwareVaultError::Backend("envelope: wrapped_len overflow".into()))?;
    if raw.len() < wrapped_end {
        return Err(HardwareVaultError::Backend(
            "envelope: truncated wrapped".into(),
        ));
    }
    let pin_hmac = &raw[4..hmac_end];
    let wrapped = &raw[wrapped_start..wrapped_end];
    Ok((pin_hmac, wrapped))
}

/// Parse the biometric-overlay envelope — single length-prefixed
/// frame carrying the wrapped password bytes. Same `checked_add`
/// discipline as `parse_envelope` so a hostile length cannot wrap.
fn parse_bio_envelope(raw: &[u8]) -> Result<&[u8], HardwareVaultError> {
    if raw.len() < 4 {
        return Err(HardwareVaultError::Backend(
            "bio envelope: truncated".into(),
        ));
    }
    let wrapped_len = u32::from_be_bytes([raw[0], raw[1], raw[2], raw[3]]) as usize;
    let wrapped_end = 4usize
        .checked_add(wrapped_len)
        .ok_or_else(|| HardwareVaultError::Backend("bio envelope: len overflow".into()))?;
    if raw.len() < wrapped_end {
        return Err(HardwareVaultError::Backend(
            "bio envelope: truncated wrapped".into(),
        ));
    }
    Ok(&raw[4..wrapped_end])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bio_envelope_round_trip_extracts_wrapped_slice() {
        let wrapped = [0xAAu8; 16];
        let mut body = Vec::new();
        write_len_prefixed(&mut body, &wrapped).expect("write");
        let parsed = parse_bio_envelope(&body).expect("parse");
        assert_eq!(parsed, &wrapped);
    }

    #[test]
    fn bio_envelope_rejects_truncated_input() {
        let err = parse_bio_envelope(&[0u8, 0, 0]).unwrap_err();
        assert!(matches!(err, HardwareVaultError::Backend(_)));
    }

    #[test]
    fn bio_envelope_rejects_oversized_length_prefix() {
        // 0xFFFF_FFFF length prefix with no body — must reject
        // before the body slice is computed.
        let mut body = Vec::new();
        body.extend_from_slice(&[0xFF, 0xFF, 0xFF, 0xFF]);
        let err = parse_bio_envelope(&body).unwrap_err();
        assert!(matches!(err, HardwareVaultError::Backend(_)));
    }

    #[test]
    fn primary_envelope_round_trip_extracts_both_frames() {
        let hmac = [0x55u8; 4];
        let wrapped = [0xCDu8; 8];
        let mut body = Vec::new();
        write_len_prefixed(&mut body, &hmac).expect("write hmac");
        write_len_prefixed(&mut body, &wrapped).expect("write wrapped");
        let (saved_hmac, saved_wrapped) = parse_envelope(&body).expect("parse");
        assert_eq!(saved_hmac, &hmac);
        assert_eq!(saved_wrapped, &wrapped);
    }

    #[test]
    fn invalid_handle_helper_detects_raw_code() {
        // `ERROR_INVALID_HANDLE` (0x6) is the canonical retry
        // trigger — the `is_invalid_handle` helper must catch it
        // independent of the windows-rs `WinError` shape.
        let e = WinError::from_hresult(windows::core::HRESULT(WIN_ERROR_INVALID_HANDLE as i32));
        assert!(is_invalid_handle(&e));
    }

    #[test]
    fn reset_cached_handles_is_callable_from_safe_context() {
        // No-op marker today, but the hook MUST be safe to call
        // from any thread, multiple times, without state. Pin the
        // call-shape so a future cache addition cannot quietly
        // change the contract.
        reset_cached_handles();
        reset_cached_handles();
    }

    #[test]
    fn with_retry_runs_op_once_on_success() {
        let mut calls = 0;
        let result: Result<u32, HardwareVaultError> = with_invalid_handle_retry(|| {
            calls += 1;
            Ok(42)
        });
        assert_eq!(result.expect("ok"), 42);
        assert_eq!(calls, 1, "single call on success");
    }

    #[test]
    fn with_retry_runs_op_twice_on_invalid_handle_then_success() {
        let mut calls = 0;
        let result: Result<u32, HardwareVaultError> = with_invalid_handle_retry(|| {
            calls += 1;
            if calls == 1 {
                Err(HardwareVaultError::Backend(format!(
                    "NCryptOpenKey: 0x{WIN_ERROR_INVALID_HANDLE:08x}"
                )))
            } else {
                Ok(7)
            }
        });
        assert_eq!(result.expect("ok"), 7);
        assert_eq!(calls, 2, "retry path fires exactly once");
    }

    #[test]
    fn with_retry_surfaces_second_invalid_handle_failure() {
        let mut calls = 0;
        let result: Result<u32, HardwareVaultError> = with_invalid_handle_retry(|| {
            calls += 1;
            Err(HardwareVaultError::Backend(format!(
                "NCryptOpenKey: 0x{WIN_ERROR_INVALID_HANDLE:08x}"
            )))
        });
        assert!(matches!(result, Err(HardwareVaultError::Backend(_))));
        assert_eq!(calls, 2, "no third call after retry already failed");
    }

    #[test]
    fn with_retry_does_not_retry_on_other_errors() {
        // Anything that isn't `ERROR_INVALID_HANDLE` must propagate
        // straight through — extra retries on `NTE_BAD_KEYSET`
        // (TPM-cleared) or `NTE_NOT_SUPPORTED` would mask the real
        // root cause from the caller.
        let mut calls = 0;
        let result: Result<u32, HardwareVaultError> = with_invalid_handle_retry(|| {
            calls += 1;
            Err(HardwareVaultError::Backend(
                "NCryptOpenKey: 0x80090016".into(),
            ))
        });
        assert!(matches!(result, Err(HardwareVaultError::Backend(_))));
        assert_eq!(calls, 1, "no retry on non-invalid-handle error");
    }

    #[test]
    fn vault_path_joins_under_support_dir() {
        let p = vault_path("/tmp/lfs");
        assert!(p.ends_with(VAULT_FILE));
    }

    #[test]
    fn bio_password_path_joins_under_support_dir() {
        let p = bio_password_path("/tmp/lfs");
        assert!(p.ends_with(BIO_PASSWORD_FILE));
    }

    // ── filesystem-level overlay round-trip ──────────────────────
    //
    // The NCrypt round-trip (`store_biometric_password` →
    // `read_biometric_password` against the live Hello dialog) is
    // marked `#[ignore]` because CI has no Hello + TPM runner. Run
    // locally with `cargo test --target x86_64-pc-windows-msvc \
    //     -- --ignored windows::hardware_vault`.

    #[test]
    #[ignore]
    fn hello_overlay_round_trip_against_live_tpm() {
        // On a Windows host with Hello configured:
        //   1. store_biometric_password fires Hello + persists key.
        //   2. read_biometric_password fires Hello + returns bytes.
        //   3. clear_biometric_password fires no UI; both gone.
        let tmp = std::env::temp_dir();
        let dir = tmp.to_string_lossy().to_string();
        let secret = b"hunter2";
        store_biometric_password(&dir, secret).expect("store");
        let got = read_biometric_password(&dir).expect("read");
        assert_eq!(got.as_deref(), Some(&secret[..]));
        clear_biometric_password(&dir).expect("clear");
        assert!(!is_biometric_password_stored(&dir));
    }
}
