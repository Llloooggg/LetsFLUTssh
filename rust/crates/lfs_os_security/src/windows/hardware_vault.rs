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
//! * Persistent key name — `letsflutssh_hardware_vault_v1`. The
//!   `_v1` suffix anchors the format against future re-key arcs:
//!   a v2 lands as a separate persistent key so v1 holders aren't
//!   bricked mid-rollout.
//! * Wrap — RSA-OAEP-SHA-256 over the 32-byte AES-256 DB key.
//!   Output goes into the disk envelope alongside the auth-value
//!   (`pin_hmac`) the unseal path verifies in constant time before
//!   ever calling NCrypt.
//!
//! ## Wire format on disk
//!
//! `support_dir/hardware_vault.bin` — 4-byte BE length-prefixed
//! pairs: `[hmac_len][hmac bytes][wrapped_len][wrapped bytes]`.
//! Same shape `super::super::hardware_tier_vault::write_len_prefixed`
//! produces on the Apple path.
//!
//! ## Failure mapping
//!
//! `NCryptOpenKey` → `NTE_BAD_KEYSET` is treated as
//! "vault revoked" (TPM cleared / persistent key removed): the
//! caller sees `Ok(None)` and the unlock cascade falls through to
//! the tier-reset dialog. Every other CNG failure surfaces as
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

/// Filename under `support_dir`. Matches the Apple wire-shape so
/// the wipe-registry covers it without a Windows-specific entry.
const VAULT_FILE: &str = "hardware_vault.bin";

/// CNG persistent-key name as a UTF-16 null-terminated buffer.
/// The `_v1` suffix anchors the format against future re-key
/// migrations.
const VAULT_KEY_NAME: &[u16] = &[
    'l' as u16, 'e' as u16, 't' as u16, 's' as u16, 'f' as u16, 'l' as u16, 'u' as u16, 't' as u16,
    's' as u16, 's' as u16, 'h' as u16, '_' as u16, 'h' as u16, 'a' as u16, 'r' as u16, 'd' as u16,
    'w' as u16, 'a' as u16, 'r' as u16, 'e' as u16, '_' as u16, 'v' as u16, 'a' as u16, 'u' as u16,
    'l' as u16, 't' as u16, '_' as u16, 'v' as u16, '1' as u16, 0u16,
];

const RSA_KEY_LENGTH_BITS: u32 = 2048;
const RSA_KEY_LENGTH_BYTES: usize = (RSA_KEY_LENGTH_BITS / 8) as usize;

fn vault_path(support_dir: &str) -> PathBuf {
    Path::new(support_dir).join(VAULT_FILE)
}

fn fmt_win(label: &str, e: WinError) -> HardwareVaultError {
    HardwareVaultError::Backend(format!("{label}: 0x{:08x}", e.code().0 as u32))
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
        let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(provider.0)) };
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
    let provider = open_provider()?;
    let key = match open_or_create_key(provider) {
        Ok(k) => k,
        Err(e) => {
            free_obj(provider.0);
            return Err(e);
        }
    };

    let result = encrypt_under_key(key, db_key);
    free_obj(key.0);
    free_obj(provider.0);
    let wrapped = result?;

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

    let provider = open_provider()?;
    let key = match open_existing_key(provider) {
        Ok(k) => k,
        Err(e) => {
            free_obj(provider.0);
            // TPM cleared / persistent key revoked → vault is gone.
            // Dart routes through TierResetDialog.
            return match e {
                HardwareVaultError::Backend(ref msg)
                    if msg.contains(&format!("{:08x}", NTE_BAD_KEYSET.0 as u32)) =>
                {
                    Ok(None)
                }
                other => Err(other),
            };
        }
    };

    let result = decrypt_under_key(key, wrapped);
    free_obj(key.0);
    free_obj(provider.0);
    result.map(Some)
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
    if let Ok(provider) = open_provider() {
        let mut key = NCRYPT_KEY_HANDLE::default();
        let open_status = unsafe {
            NCryptOpenKey(
                provider,
                &mut key,
                PCWSTR(VAULT_KEY_NAME.as_ptr()),
                CERT_KEY_SPEC(0),
                NCRYPT_FLAGS(0),
            )
        };
        if open_status.is_ok() {
            let _ = unsafe { NCryptDeleteKey(key, 0) };
            free_obj(key.0);
        }
        free_obj(provider.0);
    }
    Ok(())
}

// ── biometric password overlay (parity stubs) ───────────────────
//
// Apple / Android expose a separate biometric-only-protected
// password slot. Windows Hello already gates the primary vault
// via `NCRYPT_UI_PROTECT_KEY_FLAG`, so a separate biometric
// overlay is redundant on this platform; the parity entry points
// return `PlatformUnsupported` for now. If a future flow needs a
// distinct biometric-only secret, add a second persistent key
// keyed `_bio_v1`.

pub fn store_biometric_password(
    _support_dir: &str,
    _value: &[u8],
) -> Result<(), HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

pub fn read_biometric_password(_support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    Ok(None)
}

pub fn clear_biometric_password(_support_dir: &str) -> Result<(), HardwareVaultError> {
    Ok(())
}

#[must_use]
pub fn is_biometric_password_stored(_support_dir: &str) -> bool {
    false
}

// ── internals ────────────────────────────────────────────────────

fn free_obj(handle: usize) {
    if handle != 0 {
        let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(handle)) };
    }
}

fn open_provider() -> Result<NCRYPT_PROV_HANDLE, HardwareVaultError> {
    let mut provider = NCRYPT_PROV_HANDLE::default();
    unsafe { NCryptOpenStorageProvider(&mut provider, MS_PLATFORM_KEY_STORAGE_PROVIDER, 0) }
        .map_err(|e| fmt_win("NCryptOpenStorageProvider", e))?;
    Ok(provider)
}

fn open_existing_key(
    provider: NCRYPT_PROV_HANDLE,
) -> Result<NCRYPT_KEY_HANDLE, HardwareVaultError> {
    let mut key = NCRYPT_KEY_HANDLE::default();
    unsafe {
        NCryptOpenKey(
            provider,
            &mut key,
            PCWSTR(VAULT_KEY_NAME.as_ptr()),
            CERT_KEY_SPEC(0),
            NCRYPT_FLAGS(0),
        )
    }
    .map_err(|e| fmt_win("NCryptOpenKey", e))?;
    Ok(key)
}

fn open_or_create_key(
    provider: NCRYPT_PROV_HANDLE,
) -> Result<NCRYPT_KEY_HANDLE, HardwareVaultError> {
    // Try existing first; create on NTE_BAD_KEYSET.
    match open_existing_key(provider) {
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
            PCWSTR(VAULT_KEY_NAME.as_ptr()),
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
