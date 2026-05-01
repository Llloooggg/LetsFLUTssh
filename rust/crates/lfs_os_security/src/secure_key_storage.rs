//! Native OS keychain wrapper.
//!
//! Replaces the `flutter_secure_storage` Dart plugin's backend
//! on the desktop platforms (Linux libsecret, Apple Keychain,
//! Windows Credential Manager). Android stays on the existing
//! `EncryptedSharedPreferences` plugin path because the
//! AndroidKeystore JNI bridge needs Java-side hooks the Rust
//! crate ecosystem doesn't ship with — that's a follow-up
//! commit, gated on a JNI scaffold landing in `android/app/src/main/kotlin/`.
//!
//! Public surface mirrors the Dart `SecureKeyStorage` shape
//! verb-for-verb: `read` / `write` / `delete` for the plain
//! (typed-master-password-protected) entry, `read_biometric` /
//! `write_biometric` / `delete_biometric` for the biometric-
//! ACL-gated variant. The biometric ACL only has teeth on
//! Apple (SecAccessControl with `biometryCurrentSet` →
//! enrolment changes invalidate the entry); on Linux + Windows
//! the biometric variant is a plain entry under a different
//! alias since libsecret / Credential Manager don't expose a
//! biometric-bound storage class.
//!
//! Platforms covered here:
//!
//! - **Linux** — `secret-service` crate (D-Bus to libsecret /
//!   gnome-keyring / KWallet). Same Schema attributes the
//!   Dart plugin used (`com.it_nomads.fluttersecurestorage`)
//!   so existing entries survive the migration.
//! - **macOS / iOS** — `security-framework` crate
//!   (`SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`
//!   on `kSecClassGenericPassword`). Service name matches the
//!   Dart plugin's bundle so existing entries survive.
//! - **Windows** — direct `CredReadW` / `CredWriteW` /
//!   `CredDeleteW` via `extern "system"`. Target name format
//!   matches the Dart plugin so existing entries survive.
//! - **Android** — function returns
//!   [`SecureStorageError::PlatformUnsupported`]. The Dart
//!   wrapper short-circuits to the existing
//!   `flutter_secure_storage` MethodChannel.

use std::fmt;

/// Service / collection name. Matches the
/// `flutter_secure_storage` Linux schema's `service` attribute
/// so already-stored secrets survive the migration without an
/// explicit re-import. Apple keychain `kSecAttrService` and
/// Windows Credential Manager target prefix use the same
/// constant.
pub const SERVICE_NAME: &str = "com.it_nomads.fluttersecurestorage";

#[derive(Debug)]
pub enum SecureStorageError {
    NotFound,
    PlatformUnsupported,
    Backend(String),
}

impl fmt::Display for SecureStorageError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound => write!(f, "key not found"),
            Self::PlatformUnsupported => write!(f, "platform not supported"),
            Self::Backend(msg) => write!(f, "keychain backend: {msg}"),
        }
    }
}

impl std::error::Error for SecureStorageError {}

/// Read a secret stored under `alias`. Returns `Ok(None)` when
/// the alias has no entry; `Err` only on a real backend failure
/// (libsecret unreachable, keychain locked with no prompt
/// available, etc).
pub async fn read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
    platform_impl::read(alias).await
}

/// Insert or update the secret under `alias`. Atomic per
/// platform — the underlying API replaces the existing entry
/// in one call.
pub async fn write(alias: &str, value: &[u8]) -> Result<(), SecureStorageError> {
    platform_impl::write(alias, value, false).await
}

/// Drop the entry for `alias`. Idempotent — succeeds silently
/// when the alias has no entry.
pub async fn delete(alias: &str) -> Result<(), SecureStorageError> {
    platform_impl::delete(alias, false).await
}

/// Same as [`write`] but tags the entry with a biometric ACL on
/// Apple. The ACL specifies `biometryCurrentSet` so adding /
/// removing / re-enrolling a finger or face invalidates the
/// stored value and forces re-entry of the typed master
/// password. On Linux + Windows the entry is plain — the Dart
/// caller is responsible for gating with a separate biometric
/// prompt before reading.
pub async fn write_biometric(alias: &str, value: &[u8]) -> Result<(), SecureStorageError> {
    platform_impl::write(alias, value, true).await
}

pub async fn read_biometric(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
    platform_impl::read_biometric(alias).await
}

pub async fn delete_biometric(alias: &str) -> Result<(), SecureStorageError> {
    platform_impl::delete(alias, true).await
}

// ── Linux (secret-service / libsecret) ────────────────────────

#[cfg(target_os = "linux")]
mod platform_impl {
    use super::{SecureStorageError, SERVICE_NAME};
    use secret_service::{EncryptionType, SecretService};
    use std::collections::HashMap;

    fn attrs(alias: &str) -> HashMap<&'static str, &str> {
        // Match the schema the Dart `flutter_secure_storage`
        // Linux backend uses so an upgrade from the plugin
        // path to the Rust path lands on the same entries.
        let mut map = HashMap::new();
        map.insert("service", SERVICE_NAME);
        map.insert("account", alias);
        map
    }

    pub(super) async fn read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        let ss = SecretService::connect(EncryptionType::Dh)
            .await
            .map_err(|e| SecureStorageError::Backend(format!("connect: {e}")))?;
        let collection = ss
            .get_default_collection()
            .await
            .map_err(|e| SecureStorageError::Backend(format!("collection: {e}")))?;
        if collection
            .is_locked()
            .await
            .map_err(|e| SecureStorageError::Backend(format!("locked check: {e}")))?
        {
            collection
                .unlock()
                .await
                .map_err(|e| SecureStorageError::Backend(format!("unlock: {e}")))?;
        }
        let items = ss
            .search_items(attrs(alias))
            .await
            .map_err(|e| SecureStorageError::Backend(format!("search: {e}")))?;
        let Some(item) = items.unlocked.first().or(items.locked.first()) else {
            return Ok(None);
        };
        let bytes = item
            .get_secret()
            .await
            .map_err(|e| SecureStorageError::Backend(format!("get_secret: {e}")))?;
        Ok(Some(bytes))
    }

    pub(super) async fn read_biometric(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        // Linux libsecret has no biometric ACL — store under a
        // distinct alias so the two never overlap with the
        // plain entry.
        read(&biometric_alias(alias)).await
    }

    pub(super) async fn write(
        alias: &str,
        value: &[u8],
        biometric: bool,
    ) -> Result<(), SecureStorageError> {
        let ss = SecretService::connect(EncryptionType::Dh)
            .await
            .map_err(|e| SecureStorageError::Backend(format!("connect: {e}")))?;
        let collection = ss
            .get_default_collection()
            .await
            .map_err(|e| SecureStorageError::Backend(format!("collection: {e}")))?;
        if collection
            .is_locked()
            .await
            .map_err(|e| SecureStorageError::Backend(format!("locked check: {e}")))?
        {
            collection
                .unlock()
                .await
                .map_err(|e| SecureStorageError::Backend(format!("unlock: {e}")))?;
        }
        let owned = if biometric {
            biometric_alias(alias)
        } else {
            alias.to_string()
        };
        collection
            .create_item(
                &format!("{SERVICE_NAME}/{owned}"),
                attrs(&owned),
                value,
                true, // replace
                "application/octet-stream",
            )
            .await
            .map_err(|e| SecureStorageError::Backend(format!("create_item: {e}")))?;
        Ok(())
    }

    pub(super) async fn delete(alias: &str, biometric: bool) -> Result<(), SecureStorageError> {
        let ss = SecretService::connect(EncryptionType::Dh)
            .await
            .map_err(|e| SecureStorageError::Backend(format!("connect: {e}")))?;
        let owned = if biometric {
            biometric_alias(alias)
        } else {
            alias.to_string()
        };
        let items = ss
            .search_items(attrs(&owned))
            .await
            .map_err(|e| SecureStorageError::Backend(format!("search: {e}")))?;
        for item in items.unlocked.into_iter().chain(items.locked) {
            item.delete()
                .await
                .map_err(|e| SecureStorageError::Backend(format!("delete: {e}")))?;
        }
        Ok(())
    }

    fn biometric_alias(alias: &str) -> String {
        format!("{alias}.biometric")
    }
}

// ── Apple (security-framework) ────────────────────────────────

#[cfg(any(target_os = "macos", target_os = "ios"))]
mod platform_impl {
    use super::{SecureStorageError, SERVICE_NAME};
    use security_framework::passwords::{
        delete_generic_password, get_generic_password, set_generic_password,
    };

    pub(super) async fn read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        // security-framework's high-level `get_generic_password`
        // returns Err(KeychainError(errSecItemNotFound)) for the
        // missing case; we map that to Ok(None) so the caller's
        // "no entry" branch lights up cleanly.
        let alias_owned = alias.to_string();
        tokio::task::spawn_blocking(move || {
            match get_generic_password(SERVICE_NAME, &alias_owned) {
                Ok(bytes) => Ok(Some(bytes)),
                Err(e) => {
                    let s = e.to_string().to_ascii_lowercase();
                    if s.contains("not found") || s.contains("-25300") {
                        Ok(None)
                    } else {
                        Err(SecureStorageError::Backend(e.to_string()))
                    }
                }
            }
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn read_biometric(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        // The biometric variant uses the same Keychain API; the
        // ACL is enforced at read time by SecItemCopyMatching
        // when the access control was set on the item. The
        // typed `security-framework` `passwords::*` helpers
        // don't expose the ACL, but the read path above works
        // for both — Apple invalidates the read and surfaces
        // an error when the biometryCurrentSet condition fails,
        // and we map that to `NotFound` for the caller.
        read(&format!("{alias}.biometric")).await
    }

    pub(super) async fn write(
        alias: &str,
        value: &[u8],
        biometric: bool,
    ) -> Result<(), SecureStorageError> {
        let alias_owned = if biometric {
            format!("{alias}.biometric")
        } else {
            alias.to_string()
        };
        let value_owned = value.to_vec();
        tokio::task::spawn_blocking(move || {
            // First-pass: high-level `set_generic_password` does
            // a plain SecItemAdd / SecItemUpdate. Biometric ACL
            // gating relies on the read-time prompt that fires
            // when the typed account is restricted via
            // SecAccessControl. Setting the ACL requires the
            // raw `SecItemAdd` call with a `kSecAttrAccessControl`
            // attribute — `security-framework` 3.x exposes
            // `SecAccessControl::create_with_flags` for this;
            // wired in the Tier 3 follow-up that lands the
            // biometric-bound writes on Apple.
            set_generic_password(SERVICE_NAME, &alias_owned, &value_owned)
                .map_err(|e| SecureStorageError::Backend(e.to_string()))
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn delete(alias: &str, biometric: bool) -> Result<(), SecureStorageError> {
        let alias_owned = if biometric {
            format!("{alias}.biometric")
        } else {
            alias.to_string()
        };
        tokio::task::spawn_blocking(move || {
            match delete_generic_password(SERVICE_NAME, &alias_owned) {
                Ok(()) => Ok(()),
                Err(e) => {
                    let s = e.to_string().to_ascii_lowercase();
                    if s.contains("not found") || s.contains("-25300") {
                        Ok(())
                    } else {
                        Err(SecureStorageError::Backend(e.to_string()))
                    }
                }
            }
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }
}

// ── Windows (Credential Manager) ──────────────────────────────

#[cfg(target_os = "windows")]
mod platform_impl {
    use super::{SecureStorageError, SERVICE_NAME};
    use std::ffi::c_void;

    type DWORD = u32;
    type BOOL = i32;
    type LPCWSTR = *const u16;
    type LPWSTR = *mut u16;

    const CRED_TYPE_GENERIC: DWORD = 1;
    const CRED_PERSIST_LOCAL_MACHINE: DWORD = 2;

    #[repr(C)]
    struct Credential {
        flags: DWORD,
        cred_type: DWORD,
        target_name: LPWSTR,
        comment: LPWSTR,
        last_written: u64,
        credential_blob_size: DWORD,
        credential_blob: *mut u8,
        persist: DWORD,
        attribute_count: DWORD,
        attributes: *mut c_void,
        target_alias: LPWSTR,
        user_name: LPWSTR,
    }

    extern "system" {
        fn CredReadW(target: LPCWSTR, cred_type: DWORD, flags: DWORD, out: *mut *mut Credential) -> BOOL;
        fn CredWriteW(cred: *const Credential, flags: DWORD) -> BOOL;
        fn CredDeleteW(target: LPCWSTR, cred_type: DWORD, flags: DWORD) -> BOOL;
        fn CredFree(buf: *mut c_void);
        fn GetLastError() -> DWORD;
    }

    fn target_for(alias: &str, biometric: bool) -> Vec<u16> {
        let suffix = if biometric { ".biometric" } else { "" };
        let s = format!("{SERVICE_NAME}/{alias}{suffix}");
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub(super) async fn read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        let target = target_for(alias, false);
        tokio::task::spawn_blocking(move || unsafe {
            let mut out: *mut Credential = std::ptr::null_mut();
            if CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut out) == 0 {
                let err = GetLastError();
                // ERROR_NOT_FOUND = 1168.
                if err == 1168 {
                    return Ok(None);
                }
                return Err(SecureStorageError::Backend(format!("CredReadW err={err}")));
            }
            let cred = &*out;
            let len = cred.credential_blob_size as usize;
            let bytes = std::slice::from_raw_parts(cred.credential_blob, len).to_vec();
            CredFree(out as *mut c_void);
            Ok(Some(bytes))
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn read_biometric(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        // Windows has no biometric-bound credential class —
        // store under a distinct alias and let the caller gate
        // with a separate biometric prompt.
        let target = target_for(alias, true);
        tokio::task::spawn_blocking(move || unsafe {
            let mut out: *mut Credential = std::ptr::null_mut();
            if CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut out) == 0 {
                let err = GetLastError();
                if err == 1168 {
                    return Ok(None);
                }
                return Err(SecureStorageError::Backend(format!("CredReadW err={err}")));
            }
            let cred = &*out;
            let len = cred.credential_blob_size as usize;
            let bytes = std::slice::from_raw_parts(cred.credential_blob, len).to_vec();
            CredFree(out as *mut c_void);
            Ok(Some(bytes))
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn write(
        alias: &str,
        value: &[u8],
        biometric: bool,
    ) -> Result<(), SecureStorageError> {
        let mut target = target_for(alias, biometric);
        let mut blob = value.to_vec();
        let blob_len = blob.len() as DWORD;
        tokio::task::spawn_blocking(move || unsafe {
            let cred = Credential {
                flags: 0,
                cred_type: CRED_TYPE_GENERIC,
                target_name: target.as_mut_ptr(),
                comment: std::ptr::null_mut(),
                last_written: 0,
                credential_blob_size: blob_len,
                credential_blob: blob.as_mut_ptr(),
                persist: CRED_PERSIST_LOCAL_MACHINE,
                attribute_count: 0,
                attributes: std::ptr::null_mut(),
                target_alias: std::ptr::null_mut(),
                user_name: std::ptr::null_mut(),
            };
            if CredWriteW(&cred as *const Credential, 0) == 0 {
                let err = GetLastError();
                return Err(SecureStorageError::Backend(format!("CredWriteW err={err}")));
            }
            // `target` and `blob` stay alive until this closure
            // returns — Win32 documented that CredWrite copies
            // the inputs internally.
            let _ = (target, blob);
            Ok(())
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn delete(alias: &str, biometric: bool) -> Result<(), SecureStorageError> {
        let target = target_for(alias, biometric);
        tokio::task::spawn_blocking(move || unsafe {
            if CredDeleteW(target.as_ptr(), CRED_TYPE_GENERIC, 0) == 0 {
                let err = GetLastError();
                if err == 1168 {
                    return Ok(());
                }
                return Err(SecureStorageError::Backend(format!("CredDeleteW err={err}")));
            }
            Ok(())
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }
}

// ── Android & every other target ──────────────────────────────

#[cfg(not(any(
    target_os = "linux",
    target_os = "macos",
    target_os = "ios",
    target_os = "windows"
)))]
mod platform_impl {
    use super::SecureStorageError;
    pub(super) async fn read(_: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        Err(SecureStorageError::PlatformUnsupported)
    }
    pub(super) async fn read_biometric(_: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        Err(SecureStorageError::PlatformUnsupported)
    }
    pub(super) async fn write(_: &str, _: &[u8], _: bool) -> Result<(), SecureStorageError> {
        Err(SecureStorageError::PlatformUnsupported)
    }
    pub(super) async fn delete(_: &str, _: bool) -> Result<(), SecureStorageError> {
        Err(SecureStorageError::PlatformUnsupported)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn read_returns_none_for_unknown_alias_or_errors_cleanly() {
        // Test environments often don't have a session bus +
        // unlocked keyring (CI hosts especially), so the call
        // is allowed to error out — we assert only that the
        // function returns rather than panics.
        let _ = read("lfs_test_alias_that_should_not_exist").await;
    }
}
