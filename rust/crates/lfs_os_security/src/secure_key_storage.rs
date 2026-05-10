//! Native OS keychain wrapper — covers all five platforms with
//! direct calls into the platform-canonical secure-storage API.
//! Sole secure-storage entry point in the workspace (no
//! MethodChannel, no Dart-side plugin in the call chain).
//!
//! Public surface — verb-for-verb the same shape Dart consumes:
//! `read` / `write` / `delete` for the plain
//! (typed-master-password-protected) entry, `read_biometric` /
//! `write_biometric` / `delete_biometric` for the biometric-
//! ACL-gated variant. The biometric ACL only has teeth on
//! Apple (SecAccessControl with `biometryCurrentSet` →
//! enrolment changes invalidate the entry) and Android (the
//! AndroidKeyStore key carries `setUserAuthenticationRequired(true)`,
//! so the unwrap cipher op fails outside a recent biometric
//! prompt window); on Linux + Windows the biometric variant
//! is a plain entry under a different alias since libsecret
//! / Credential Manager don't expose a biometric-bound
//! storage class.
//!
//! Platforms covered here:
//!
//! - **Linux** — `secret-service` crate (D-Bus to libsecret /
//!   gnome-keyring / KWallet). Schema `service` attribute is
//!   pinned to [`SERVICE_NAME`] (external-compat constant — see
//!   its docstring).
//! - **macOS / iOS** — `security-framework` crate
//!   (`SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`
//!   on `kSecClassGenericPassword`). Service name = [`SERVICE_NAME`].
//! - **Windows** — direct `CredReadW` / `CredWriteW` /
//!   `CredDeleteW` via `extern "system"`. Target name prefix =
//!   [`SERVICE_NAME`].
//! - **Android** — direct JNI to `java.security.KeyStore`
//!   provider `"AndroidKeyStore"` via [`crate::android::keystore`].
//!   Wrapping AES-256-GCM key in AndroidKeyStore + wrapped
//!   value bytes in a 0600 file under `getFilesDir()`. Alias
//!   prefix is the external-compat constant in
//!   [`crate::android::keystore::KEY_ALIAS_PREFIX`].
//!   **Verification status**: code compiles via the rust-cross-check
//!   matrix (`aarch64-linux-android`); runtime correctness needs
//!   a real-device hardware-verification pass.

use std::fmt;

/// External-compat constant — **never rename**. Used as the
/// libsecret schema `service` attribute, Apple keychain
/// `kSecAttrService`, and the Windows Credential Manager target
/// prefix. Renaming orphans every secret already on the user's
/// device with no automated re-import path.
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

/// Linux-only: reachability ping for `org.freedesktop.secrets`. True
/// when the daemon is registered on the session bus and answers a
/// trivial peer-ping; false on transport failure / `ServiceUnknown` /
/// no daemon installed. Same signal `libsecret` itself runs before
/// every API call — probing up front lets the Dart-side wizard
/// classify "no daemon" without spamming stderr on failure.
///
/// On every other platform the function is a stub returning `true`
/// — non-Linux hosts have a different keychain backend
/// (`security-framework`, Credential Manager, AndroidKeyStore) that
/// the Dart caller probes via a live write/read/delete round-trip
/// instead.
#[cfg(target_os = "linux")]
pub async fn secret_service_reachable() -> bool {
    use secret_service::{EncryptionType, SecretService};
    SecretService::connect(EncryptionType::Dh).await.is_ok()
}

#[cfg(not(target_os = "linux"))]
pub async fn secret_service_reachable() -> bool {
    true
}

// ── Linux (secret-service / libsecret) ────────────────────────

#[cfg(target_os = "linux")]
mod platform_impl {
    use super::{SecureStorageError, SERVICE_NAME};
    use secret_service::{EncryptionType, SecretService};
    use std::collections::HashMap;

    fn attrs(alias: &str) -> HashMap<&'static str, &str> {
        // `service` + `account` schema is the external-compat
        // shape pinned by `SERVICE_NAME` — see its docstring.
        // Bumping either key orphans every entry the user
        // already has on disk.
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
        // Prefer unlocked items only — falling back to a locked
        // entry would trigger an implicit `org.freedesktop.secret.
        // Item.GetSecret` unlock prompt under the user's nose,
        // outside any LetsFLUTssh dialog. The default collection
        // unlock above already covers the legitimate case; if the
        // search still surfaces locked items they belong to a
        // separate (typically session) collection that the user
        // hasn't opted in to. Treat those as "no entry" so the
        // caller routes through the password prompt instead.
        let Some(item) = items.unlocked.first() else {
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

// ── Apple (security-framework + raw SecItemAdd for ACL) ──────

#[cfg(any(target_os = "macos", target_os = "ios"))]
mod platform_impl {
    use super::{SecureStorageError, SERVICE_NAME};
    use core_foundation::base::{CFType, TCFType};
    use core_foundation::data::CFData;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::number::CFNumber;
    use core_foundation::string::CFString;
    use core_foundation_sys::base::CFOptionFlags;
    use core_foundation_sys::string::CFStringRef;
    use security_framework::access_control::{ProtectionMode, SecAccessControl};
    use security_framework::passwords::{
        delete_generic_password, get_generic_password, set_generic_password,
    };
    use security_framework_sys::access_control::kSecAccessControlBiometryCurrentSet;
    use security_framework_sys::base::errSecItemNotFound;
    use security_framework_sys::item::{
        kSecAttrAccessControl, kSecAttrAccessible, kSecAttrAccount, kSecAttrService, kSecClass,
        kSecClassGenericPassword, kSecMatchLimit, kSecReturnData, kSecValueData,
    };
    use security_framework_sys::keychain_item::{SecItemAdd, SecItemCopyMatching, SecItemDelete};

    // `kSecMatchLimitOne` isn't bound by security-framework-sys
    // 2.17 (only `kSecMatchLimit` + `kSecMatchLimitAll` ship).
    // Same for `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
    // — Security.framework exports the symbols, security-framework-sys
    // already links the framework, so linkage resolves at run time.
    extern "C" {
        static kSecMatchLimitOne: CFStringRef;
        static kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFStringRef;
    }

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
        // SecItemCopyMatching honours the ACL recorded on the
        // matched entry — Apple prompts the user for biometry
        // before returning the bytes, then surfaces
        // errSecAuthFailed if the user cancelled or the
        // enrolment changed since the write. We map both into
        // "no entry" so the Dart caller routes through the
        // master-password prompt instead of surfacing a raw
        // OSStatus to the UI.
        let alias_owned = biometric_alias(alias);
        tokio::task::spawn_blocking(move || raw_read(&alias_owned))
            .await
            .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn write(
        alias: &str,
        value: &[u8],
        biometric: bool,
    ) -> Result<(), SecureStorageError> {
        let alias_owned = if biometric {
            biometric_alias(alias)
        } else {
            alias.to_string()
        };
        let value_owned = value.to_vec();
        tokio::task::spawn_blocking(move || {
            if biometric {
                // Biometric path uses raw SecItemAdd with a
                // SecAccessControl that ties the entry to the
                // *current* biometric enrolment — adding /
                // removing / re-enrolling a finger or face
                // invalidates the stored value. Same invariant
                // the Dart-era
                // `AccessControlFlag.biometryCurrentSet` had.
                raw_write_with_biometric_acl(&alias_owned, &value_owned)
            } else {
                // Non-biometric path: SecItemAdd directly with
                // `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
                // The high-level `set_generic_password` helper
                // hands SecItemAdd no `kSecAttrAccessible`, which
                // defaults to `AccessibleWhenUnlocked` — that
                // includes "this-device-only? No" (Apple may sync
                // the entry to iCloud Keychain) which the threat
                // model excludes. Pinning to
                // `…ThisDeviceOnly` keeps the entry to this
                // physical device's keychain.
                raw_write_first_unlock_this_device(&alias_owned, &value_owned)
            }
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }

    pub(super) async fn delete(alias: &str, biometric: bool) -> Result<(), SecureStorageError> {
        let alias_owned = if biometric {
            biometric_alias(alias)
        } else {
            alias.to_string()
        };
        tokio::task::spawn_blocking(move || {
            // The high-level `delete_generic_password` works for
            // both the ACL-bound and plain entries — SecItemDelete
            // doesn't require unlock to drop the row.
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

    fn biometric_alias(alias: &str) -> String {
        // A distinct account suffix keeps the ACL-bound entry
        // separate from the plain one — SecItem keys on
        // `(class, service, account)`, so two entries with the
        // same alias can't coexist.
        format!("{alias}.biometric")
    }

    /// Build a `SecAccessControl` with `BIOMETRY_CURRENT_SET` and
    /// `WHEN_PASSCODE_SET_THIS_DEVICE_ONLY` — the strictest pair
    /// the existing Dart options used. Biometric enrolment
    /// changes invalidate; the device must have a passcode set;
    /// the entry never syncs to other devices.
    fn build_access_control() -> Result<SecAccessControl, SecureStorageError> {
        // `CFOptionFlags` (u64) — pass the bare constant. The
        // `kSecAccessControlBiometryCurrentSet` value (1 << 3)
        // ties the entry to the *current* biometric enrolment;
        // any add/remove/re-enrolment of a finger or face
        // invalidates the stored value.
        let flags: CFOptionFlags = kSecAccessControlBiometryCurrentSet;
        SecAccessControl::create_with_protection(
            Some(ProtectionMode::AccessibleWhenPasscodeSetThisDeviceOnly),
            flags,
        )
        .map_err(|e| SecureStorageError::Backend(format!("SecAccessControl: {e}")))
    }

    /// SAFETY: every `kSec*` symbol referenced via
    /// `wrap_under_get_rule` is a static dictionary key constant
    /// exported by Security.framework; the framework owns those
    /// CFStrings for the process lifetime, so the borrowed-key
    /// pattern is correct. CFDictionary + value owners are
    /// constructed on the stack and live across the SecItemAdd
    /// call.
    /// Non-biometric SecItemAdd with explicit
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Replaces
    /// the high-level `set_generic_password` helper which defaults
    /// to the broader `kSecAttrAccessibleWhenUnlocked` (no
    /// "this-device-only" suffix → Apple may sync to iCloud
    /// Keychain).
    fn raw_write_first_unlock_this_device(
        alias: &str,
        data: &[u8],
    ) -> Result<(), SecureStorageError> {
        // SAFETY: every `wrap_under_get_rule` below takes a static
        // `CFStringRef` exported by Security.framework / our extern
        // binding; the foreign const lives for the program's lifetime
        // and `wrap_under_get_rule` honours the get-rule (no extra
        // CFRetain), so reference counts stay balanced. The
        // `SecItemAdd` call passes a CFDictionary built on the stack
        // whose keys + values are `CFString` / `CFData` Rust wrappers
        // that hold the underlying CF refs across the call; the
        // dictionary outlives `as_concrete_TypeRef()`.
        let class = unsafe { CFString::wrap_under_get_rule(kSecClassGenericPassword) };
        let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
        let service_key = unsafe { CFString::wrap_under_get_rule(kSecAttrService) };
        let account_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccount) };
        let value_key = unsafe { CFString::wrap_under_get_rule(kSecValueData) };
        let access_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccessible) };
        let access_value = unsafe {
            CFString::wrap_under_get_rule(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        };

        let svc = CFString::new(SERVICE_NAME);
        let acc = CFString::new(alias);
        let val = CFData::from_buffer(data);

        let pairs: Vec<(CFString, CFType)> = vec![
            (class_key, class.into_CFType()),
            (service_key, svc.into_CFType()),
            (account_key, acc.into_CFType()),
            (value_key, val.into_CFType()),
            (access_key, access_value.into_CFType()),
        ];
        let dict = CFDictionary::from_CFType_pairs(&pairs);

        // Best-effort delete first so SecItemAdd doesn't bounce
        // on `errSecDuplicateItem` for an existing entry under
        // the same alias.
        let _ = raw_delete(alias);

        let status = unsafe { SecItemAdd(dict.as_concrete_TypeRef(), std::ptr::null_mut()) };
        if status != 0 {
            return Err(SecureStorageError::Backend(format!(
                "SecItemAdd (FirstUnlockThisDeviceOnly) failed: OSStatus {status}"
            )));
        }
        Ok(())
    }

    fn raw_write_with_biometric_acl(alias: &str, data: &[u8]) -> Result<(), SecureStorageError> {
        let acl = build_access_control()?;

        // SAFETY: see `raw_write_first_unlock_this_device` above —
        // identical CFString get-rule + CFDictionary lifetime
        // contract; the only difference is the `kSecAttrAccessControl`
        // pair carrying the biometric `acl` instead of the
        // accessibility-only attribute.
        let class = unsafe { CFString::wrap_under_get_rule(kSecClassGenericPassword) };
        let service_key = unsafe { CFString::wrap_under_get_rule(kSecAttrService) };
        let account_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccount) };
        let value_key = unsafe { CFString::wrap_under_get_rule(kSecValueData) };
        let acl_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccessControl) };
        let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };

        let svc = CFString::new(SERVICE_NAME);
        let acc = CFString::new(alias);
        let val = CFData::from_buffer(data);

        let pairs: Vec<(CFString, CFType)> = vec![
            (class_key, class.into_CFType()),
            (service_key, svc.into_CFType()),
            (account_key, acc.into_CFType()),
            (value_key, val.into_CFType()),
            (acl_key, acl.into_CFType()),
        ];
        let dict = CFDictionary::from_CFType_pairs(&pairs);

        // Best-effort delete first so SecItemAdd doesn't bounce
        // on `errSecDuplicateItem`. The delete query mirrors
        // the add minus the value + ACL — SecItemDelete keys on
        // class + service + account.
        let _ = raw_delete(alias);

        let status = unsafe { SecItemAdd(dict.as_concrete_TypeRef(), std::ptr::null_mut()) };
        if status != 0 {
            return Err(SecureStorageError::Backend(format!(
                "SecItemAdd failed: OSStatus {status}"
            )));
        }
        Ok(())
    }

    /// Raw SecItemCopyMatching for the biometric-ACL alias. The
    /// `kSecAttrAccessControl` is recorded on the entry; we
    /// don't have to re-specify it here — the OS reads the
    /// stored ACL and prompts the user for biometry on its own
    /// when the row matches.
    fn raw_read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        // SAFETY: every `wrap_under_get_rule` below takes a static
        // `CFStringRef` exported by Security.framework; refcount
        // stays balanced. `SecItemCopyMatching` writes its result
        // into `out` under the create-rule (we own the returned
        // ref); the immediate `wrap_under_create_rule` takes
        // ownership so the early-return paths drop and CFRelease
        // exactly once. A non-null `out` paired with a non-zero
        // `status` (Apple's docs imply impossible but don't forbid)
        // would otherwise leak; the early ownership wrap closes that.
        let class = unsafe { CFString::wrap_under_get_rule(kSecClassGenericPassword) };
        let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
        let service_key = unsafe { CFString::wrap_under_get_rule(kSecAttrService) };
        let account_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccount) };
        let return_data_key = unsafe { CFString::wrap_under_get_rule(kSecReturnData) };
        let match_limit_key = unsafe { CFString::wrap_under_get_rule(kSecMatchLimit) };
        let match_limit_one = unsafe { CFString::wrap_under_get_rule(kSecMatchLimitOne) };

        let svc = CFString::new(SERVICE_NAME);
        let acc = CFString::new(alias);
        let one = CFNumber::from(1i32);

        let pairs: Vec<(CFString, CFType)> = vec![
            (class_key, class.into_CFType()),
            (service_key, svc.into_CFType()),
            (account_key, acc.into_CFType()),
            (return_data_key, one.into_CFType()),
            (match_limit_key, match_limit_one.into_CFType()),
        ];
        let dict = CFDictionary::from_CFType_pairs(&pairs);

        let mut out: core_foundation_sys::base::CFTypeRef = std::ptr::null();
        let status = unsafe { SecItemCopyMatching(dict.as_concrete_TypeRef(), &mut out) };
        // Eagerly take ownership of any non-null out-param so it
        // is CFRelease'd on every code path, including the
        // anomalous (status != 0 && out != null) case Apple's
        // docs imply doesn't happen but doesn't forbid.
        let owned: Option<CFData> = if out.is_null() {
            None
        } else {
            Some(unsafe {
                CFData::wrap_under_create_rule(out as *const core_foundation_sys::data::__CFData)
            })
        };
        if status == errSecItemNotFound {
            return Ok(None);
        }
        if status != 0 {
            // Any non-success (user cancel / biometric failure /
            // enrolment changed) maps to "no entry" so the Dart
            // caller routes through the master-password prompt;
            // `owned` drops here and releases the CF ref if set.
            //
            // Log the OSStatus to stderr so a support trace
            // distinguishes "user cancelled" / "wrong biometric"
            // from "hardware fault" — without this every non-
            // success collapsed into the same blank "missing
            // entry" bucket and there was no way to tell why a
            // user kept dropping back to the password prompt.
            // Stderr only (no app::instance — `lfs_os_security`
            // sits below `lfs_core` and cannot reach the bus).
            eprintln!(
                "[lfs_os_security] SecItemCopyMatching biometric read failed: \
                 OSStatus {status} (mapped to None — caller routes to password)"
            );
            return Ok(None);
        }
        match owned {
            Some(data) => Ok(Some(data.bytes().to_vec())),
            None => Ok(None),
        }
    }

    fn raw_delete(alias: &str) -> Result<(), SecureStorageError> {
        // SAFETY: same get-rule + CFDictionary contract as the
        // sibling functions above; `SecItemDelete` returns 0 /
        // `errSecItemNotFound` for our purposes — both treated
        // as success.
        let class = unsafe { CFString::wrap_under_get_rule(kSecClassGenericPassword) };
        let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
        let service_key = unsafe { CFString::wrap_under_get_rule(kSecAttrService) };
        let account_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccount) };

        let svc = CFString::new(SERVICE_NAME);
        let acc = CFString::new(alias);

        let pairs: Vec<(CFString, CFType)> = vec![
            (class_key, class.into_CFType()),
            (service_key, svc.into_CFType()),
            (account_key, acc.into_CFType()),
        ];
        let dict = CFDictionary::from_CFType_pairs(&pairs);

        let status = unsafe { SecItemDelete(dict.as_concrete_TypeRef()) };
        if status == 0 || status == errSecItemNotFound {
            Ok(())
        } else {
            Err(SecureStorageError::Backend(format!(
                "SecItemDelete failed: OSStatus {status}"
            )))
        }
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
        fn CredReadW(
            target: LPCWSTR,
            cred_type: DWORD,
            flags: DWORD,
            out: *mut *mut Credential,
        ) -> BOOL;
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
            // SAFETY: CredReadW MAY return a zero-length blob with a NULL
            // `credential_blob` pointer; `slice::from_raw_parts` requires a
            // non-null pointer regardless of length. Treat a NULL or zero-length
            // blob as an empty value rather than constructing a UB slice.
            let bytes = if cred.credential_blob.is_null() || len == 0 {
                Vec::new()
            } else {
                std::slice::from_raw_parts(cred.credential_blob, len).to_vec()
            };
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
            // SAFETY: see `read()` above — CredReadW NULL/zero-length
            // blob fast path before `slice::from_raw_parts`.
            let bytes = if cred.credential_blob.is_null() || len == 0 {
                Vec::new()
            } else {
                std::slice::from_raw_parts(cred.credential_blob, len).to_vec()
            };
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
                return Err(SecureStorageError::Backend(format!(
                    "CredDeleteW err={err}"
                )));
            }
            Ok(())
        })
        .await
        .map_err(|e| SecureStorageError::Backend(format!("join: {e}")))?
    }
}

// ── Android — direct JNI to AndroidKeyStore ──────────────────

#[cfg(target_os = "android")]
mod platform_impl {
    use super::SecureStorageError;
    use crate::android::keystore;

    pub(super) async fn read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        keystore::read(alias).await
    }
    pub(super) async fn read_biometric(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
        keystore::read_biometric(alias).await
    }
    pub(super) async fn write(
        alias: &str,
        value: &[u8],
        biometric: bool,
    ) -> Result<(), SecureStorageError> {
        keystore::write(alias, value, biometric).await
    }
    pub(super) async fn delete(alias: &str, biometric: bool) -> Result<(), SecureStorageError> {
        keystore::delete(alias, biometric).await
    }
}

// ── Every other target (no desktop OS, no Android) ──────────

#[cfg(not(any(
    target_os = "linux",
    target_os = "macos",
    target_os = "ios",
    target_os = "windows",
    target_os = "android"
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
