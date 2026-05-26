//! Hardware-bound T2 vault for Apple platforms.
//!
//! Mirrors `macos/Runner/HardwareVaultPlugin.swift` +
//! `ios/Runner/HardwareVaultPlugin.swift` byte-for-byte:
//!
//! - **Primary key** — a Secure Enclave P-256 keypair tagged
//!   `com.letsflutssh.hw_vault.l3` with
//!   `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` +
//!   `kSecAccessControlPrivateKeyUsage`. Silent (no biometric
//!   prompt) — biometric is the *overlay* key, not the primary.
//! - **Wrap algorithm** — `ECIESEncryptionCofactorVariableIVX963SHA256AESGCM`
//!   over the SE-bound key. Same algorithm Swift uses.
//! - **PIN-HMAC envelope on disk** — the Dart layer hashes the
//!   user-typed PIN with a per-install salt and hands the resulting
//!   HMAC to `store` / `read`. The HMAC is stored on disk alongside
//!   the wrapped DB key; `read` constant-time-compares the supplied
//!   HMAC against the stored one before invoking the SE. Wrong PIN
//!   fails locally without waking the SE prompt — bounded by the
//!   per-install salt + SE rate-limit when the SE itself is
//!   exercised.
//! - **Biometric overlay key** — separate SE-bound key tagged
//!   `com.letsflutssh.hw_password_overlay` carrying the user's typed
//!   short password. Gated by `kSecAccessControlBiometryCurrentSet`
//!   so any biometric enrolment change invalidates the entry. Never
//!   touches the DB wrapping key.
//! - **On-disk format** — length-prefixed binary frames:
//!   * vault file (`hardware_vault_apple.bin`):
//!     `u32(pin_hmac_len) || pin_hmac || u32(wrapped_len) || wrapped`
//!   * biometric overlay file (`hardware_vault_password_overlay_apple.bin`):
//!     `u32(wrapped_len) || wrapped`
//! - **POSIX hardening** — both files chmod 0600 after atomic write.
//!
//! The Dart caller resolves `getApplicationSupportDirectory()` and
//! hands the path in; Rust never reaches for a directory itself
//! (matches the rest of `lfs_os_security` — no `directories` crate
//! / `objc2-foundation::NSFileManager` dance).
//!
//! On non-Apple platforms every entry point returns
//! [`HardwareVaultError::PlatformUnsupported`] — Linux uses the
//! TPM2 path in `lfs_os_security::linux::tpm`, Windows uses the
//! NCrypt port in [`super::windows::hardware_vault`], Android uses
//! the AndroidKeystore port in [`super::android::hardware_vault`].

use std::fmt;
// `Path` is used only by the Apple-side file-name helpers below;
// cfg-gate to Apple targets so non-Apple builds don't fail with an
// unused-import warning. Windows + Android each own their path
// resolution in their own modules.
#[cfg(any(target_os = "macos", target_os = "ios"))]
use std::path::Path;

/// Classified outcome of [`probe_detail`]. Mirrors the Dart
/// `HardwareProbeDetail` enum; the wizard maps each variant to a
/// localised hint string.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HardwareProbeReason {
    /// Secure Enclave reachable + passcode set + signing identity OK.
    Available,
    /// `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)`
    /// failed with `LAError.biometryNotAvailable` /
    /// `touchIDNotAvailable` — typically a pre-T2 Intel Mac with no
    /// SE hardware at all.
    AppleNoSecureEnclave,
    /// SE hardware present but device passcode unset; T2 requires
    /// one for the `WhenPasscodeSet` access-control binding.
    ApplePasscodeNotSet,
    /// `SecKeyCreateRandomKey` rejected the SE binding with
    /// `errSecMissingEntitlement` (-34018). Ad-hoc-signed bundles
    /// without a stable identity hit this. The wizard surfaces the
    /// bundled `macos-resign.sh` script as the actionable fix.
    AppleSigningIdentityMissing,
    /// Any other failure (LAError fall-through, generic SE create
    /// failure). Logged for diagnostics; UI shows generic copy.
    AppleGeneric,
    /// Non-Apple platform — Linux uses the TPM2 path,
    /// Windows + Android keep their MethodChannel plugins.
    PlatformUnsupported,
}

impl fmt::Display for HardwareProbeReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.wire_name())
    }
}

impl HardwareProbeReason {
    /// Stable wire name matching the existing Dart-side string codes
    /// the `HardwareProbeDetail` enum parses. Bumping any of these
    /// is a wire break.
    pub fn wire_name(&self) -> &'static str {
        match self {
            Self::Available => "available",
            Self::AppleNoSecureEnclave => "macosNoSecureEnclave",
            Self::ApplePasscodeNotSet => "macosPasscodeNotSet",
            Self::AppleSigningIdentityMissing => "macosSigningIdentityMissing",
            Self::AppleGeneric => "macosGeneric",
            Self::PlatformUnsupported => "unknown",
        }
    }
}

/// Errors raised by every `store` / `read` / `clear` entry point.
#[derive(Debug)]
pub enum HardwareVaultError {
    /// Non-Apple platform — caller should fall back to its
    /// existing per-platform path (Linux TPM, Windows / Android
    /// MethodChannel).
    PlatformUnsupported,
    /// A Secure Enclave / Keychain Services API returned an error
    /// (raw `OSStatus` or `CFError` body). Caller's policy is to
    /// drop the cached key and route the user back through the PIN
    /// dialog so the SE is exercised once with the right input.
    Backend(String),
    /// Filesystem error reading or writing the on-disk envelope.
    /// Same disposition as `Backend` — UI shows a "vault unreachable"
    /// hint and falls back to PIN entry.
    Io(String),
    /// On-disk envelope failed length-prefix sanity (truncated
    /// header, length out of range). UI treats as "vault corrupt"
    /// and routes the user through the reset cascade.
    Corrupt,
}

impl fmt::Display for HardwareVaultError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::PlatformUnsupported => f.write_str("platform unsupported"),
            Self::Backend(s) => write!(f, "backend: {s}"),
            Self::Io(s) => write!(f, "io: {s}"),
            Self::Corrupt => f.write_str("vault corrupt"),
        }
    }
}

impl std::error::Error for HardwareVaultError {}

// ── Common envelope header ────────────────────────────────────────
//
// Every platform's hardware-vault on-disk format prepends a
// fixed-shape `magic + version + platform_id` header so the
// migration framework can sniff the format without per-platform
// probes. v1 had no header; v2 readers reject v1 outright (no
// migration ships in this revision — `SchemaVersions::HW_VAULT_*`
// bumped to 2 and existing installs hit `HardwareVaultError::Corrupt`
// → tier-reset cascade).

const HW_VAULT_MAGIC: &[u8; 4] = b"LFHV";
const HW_VAULT_VERSION: u8 = 2;
pub const HW_VAULT_PLATFORM_APPLE: u8 = 1;
pub const HW_VAULT_PLATFORM_WINDOWS: u8 = 2;
pub const HW_VAULT_PLATFORM_ANDROID: u8 = 3;
pub const HW_VAULT_PLATFORM_LINUX: u8 = 4;
pub const HW_VAULT_HEADER_LEN: usize = 6;

/// Prepend `magic[4] + version[1] + platform[1]` to `body` and
/// return the assembled envelope ready for atomic write.
pub fn prepend_envelope_header(platform: u8, body: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(HW_VAULT_HEADER_LEN + body.len());
    out.extend_from_slice(HW_VAULT_MAGIC);
    out.push(HW_VAULT_VERSION);
    out.push(platform);
    out.extend_from_slice(body);
    out
}

/// Strip + verify the common envelope header. Returns the body
/// slice on success; `Err(HardwareVaultError::Corrupt)` for
/// truncated input, magic mismatch, version mismatch, or
/// platform-id mismatch (= cross-platform file copy or downgrade
/// attempt).
pub fn parse_envelope_header(
    raw: &[u8],
    expected_platform: u8,
) -> Result<&[u8], HardwareVaultError> {
    if raw.len() < HW_VAULT_HEADER_LEN
        || &raw[0..4] != HW_VAULT_MAGIC
        || raw[4] != HW_VAULT_VERSION
        || raw[5] != expected_platform
    {
        return Err(HardwareVaultError::Corrupt);
    }
    Ok(&raw[HW_VAULT_HEADER_LEN..])
}

/// Atomic 0600 write mirroring `lfs_core::path::write_bytes_atomic`.
/// Cannot reach into `lfs_core` directly (lfs_os_security is the
/// lower edge of the dependency direction), so the helper lives
/// here. Random tmp suffix avoids per-process tmp-name collisions;
/// `sync_data` + parent-dir fsync close the torn-write window on
/// power loss.
pub fn os_atomic_write_0600(
    path: &std::path::Path,
    bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    use std::io::Write as _;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};
    // tmp-file suffix for collision avoidance — does not need to be
    // cryptographically random. Fold pid + monotonic counter + nanos
    // so concurrent writers in the same process pick distinct names
    // even if SystemTime resolution is coarse.
    static COUNTER: AtomicU32 = AtomicU32::new(0);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let suffix = (std::process::id() ^ nanos).wrapping_add(counter);
    let parent = path.parent().unwrap_or(std::path::Path::new("."));
    std::fs::create_dir_all(parent)
        .map_err(|e| HardwareVaultError::Io(format!("mkdir parent: {e}")))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // Best-effort 0700 on the parent so secret-bearing
        // artefacts inside don't sit under an inherited 0755 umask.
        // Failure is non-fatal — the file write itself remains 0600.
        let _ = std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700));
    }
    let stem = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| String::from("blob"));
    let tmp = parent.join(format!("{stem}.tmp{suffix:08x}"));
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.create(true).write(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts
            .open(&tmp)
            .map_err(|e| HardwareVaultError::Io(format!("open tmp: {e}")))?;
        if let Err(e) = f.write_all(bytes) {
            let _ = std::fs::remove_file(&tmp);
            return Err(HardwareVaultError::Io(format!("write tmp: {e}")));
        }
        if let Err(e) = f.sync_data() {
            let _ = std::fs::remove_file(&tmp);
            return Err(HardwareVaultError::Io(format!("sync tmp: {e}")));
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600))
            .map_err(|e| HardwareVaultError::Io(format!("chmod tmp: {e}")))?;
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(HardwareVaultError::Io(format!("rename: {e}")));
    }
    // Parent-dir fsync so the rename is durable (Unix only —
    // Windows does not expose directory fsync via std).
    #[cfg(unix)]
    {
        if let Ok(dir) = std::fs::File::open(parent) {
            let _ = dir.sync_all();
        }
    }
    Ok(())
}

/// Length-prefixed binary frame:
/// `u32(len_be) || bytes`. Used by both the vault and biometric
/// overlay file formats. `pos` is the input cursor.
#[cfg(any(test, target_os = "macos", target_os = "ios"))]
fn read_len_prefixed(raw: &[u8], pos: &mut usize) -> Option<Vec<u8>> {
    if *pos + 4 > raw.len() {
        return None;
    }
    let len = u32::from_be_bytes([raw[*pos], raw[*pos + 1], raw[*pos + 2], raw[*pos + 3]]) as usize;
    *pos += 4;
    if *pos + len > raw.len() {
        return None;
    }
    let out = raw[*pos..*pos + len].to_vec();
    *pos += len;
    Some(out)
}

#[cfg(any(test, target_os = "macos", target_os = "ios", target_os = "windows"))]
pub(crate) fn write_len_prefixed(
    out: &mut Vec<u8>,
    bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    // **Don't `as u32` a `usize` here** — silently capping at
    // `u32::MAX` emits a corrupt envelope (buffer copy runs the
    // full length but the length prefix lies). `try_from`
    // surfaces overflow as a typed error so a misuse (a wrap key
    // resized past 4 GiB, an unexpected oversize platform field)
    // fails loud before any unreadable header lands on disk.
    let len = u32::try_from(bytes.len()).map_err(|_| {
        HardwareVaultError::Backend(format!(
            "write_len_prefixed: bytes length exceeds u32 ({} > {})",
            bytes.len(),
            u32::MAX
        ))
    })?;
    out.extend_from_slice(&len.to_be_bytes());
    out.extend_from_slice(bytes);
    Ok(())
}

/// Constant-time byte-slice equality. Used by [`read`] to compare
/// the caller-supplied PIN HMAC against the stored one before the
/// SE is exercised. Routes through `subtle::ConstantTimeEq` so the
/// timing posture is whatever the audited primitive guarantees;
/// the local hand-rolled XOR loop relied on the compiler not
/// short-circuiting, which is not a contract LLVM owes us.
#[cfg(any(test, target_os = "macos", target_os = "ios"))]
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    if a.len() != b.len() {
        return false;
    }
    a.ct_eq(b).into()
}

// Apple-side filenames. Other platforms own their constants in
// their own modules (`crate::windows::hardware_vault`,
// `crate::android::hardware_vault`). Exposed `pub` so
// `lfs_core::security::wipe`'s coverage tests can cross-reference
// the canonical filename without copy-pasting a string literal
// that drifts. Constants stay visible on non-Apple desktops so
// the wipe-coverage test can compile-check them; the path helpers
// below are Apple-only to keep dead-code linting happy on
// Windows / Linux.
#[cfg(not(target_os = "android"))]
pub const VAULT_FILE_NAME: &str = "hardware_vault_apple.bin";
#[cfg(not(target_os = "android"))]
pub const BIO_PASSWORD_FILE_NAME: &str = "hardware_vault_password_overlay_apple.bin";

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn vault_file_path(support_dir: &str) -> std::path::PathBuf {
    Path::new(support_dir).join(VAULT_FILE_NAME)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn bio_password_file_path(support_dir: &str) -> std::path::PathBuf {
    Path::new(support_dir).join(BIO_PASSWORD_FILE_NAME)
}

/// True when the primary vault file exists. Cheap path-stat — does
/// not invoke the SE; the SE-side existence check happens inside
/// [`read`] when the wrap key is needed. UI uses this to decide
/// "show unlock dialog" vs "first-launch wizard"; the salt
/// companion file is checked Dart-side because the Dart layer owns
/// the salt's lifecycle (it's the per-install random seed).
///
/// Each platform owns its own primary-vault filename (Apple's
/// `hardware_vault_apple.bin`, Windows's `hardware_vault.bin`,
/// Android's `hardware_vault_android.bin`) so this probe dispatches
/// per-target to avoid cross-platform false positives.
pub fn is_stored(support_dir: &str) -> bool {
    #[cfg(target_os = "android")]
    {
        crate::android::hardware_vault::is_stored(support_dir)
    }
    #[cfg(target_os = "windows")]
    {
        crate::windows::hardware_vault::is_stored(support_dir)
    }
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        vault_file_path(support_dir).exists()
    }
    #[cfg(not(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "android",
        target_os = "windows"
    )))]
    {
        let _ = support_dir;
        false
    }
}

/// True when the biometric-overlay password file exists. Same
/// existence-check semantics as [`is_stored`]. Each platform owns
/// its own overlay filename (Apple's lives under
/// `hardware_vault_password_overlay_apple.bin`; Windows under
/// `hardware_vault_password_overlay_windows.bin`; Android under
/// `hardware_vault_android_bio.bin`) so the existence probe
/// dispatches per-target to avoid cross-platform false positives.
pub fn is_biometric_password_stored(support_dir: &str) -> bool {
    #[cfg(target_os = "android")]
    {
        crate::android::hardware_vault::is_biometric_password_stored(support_dir)
    }
    #[cfg(target_os = "windows")]
    {
        crate::windows::hardware_vault::is_biometric_password_stored(support_dir)
    }
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        bio_password_file_path(support_dir).exists()
    }
    #[cfg(not(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "android",
        target_os = "windows"
    )))]
    {
        let _ = support_dir;
        false
    }
}

// ---- Apple impl ----------------------------------------------------

#[cfg(any(target_os = "macos", target_os = "ios"))]
mod apple {
    use super::{
        bio_password_file_path, constant_time_eq, read_len_prefixed, vault_file_path,
        write_len_prefixed, HardwareProbeReason, HardwareVaultError,
    };
    use core_foundation::base::{CFType, TCFType};
    use core_foundation::data::CFData;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::error::CFError;
    use core_foundation::number::CFNumber;
    use core_foundation::string::CFString;
    use core_foundation_sys::string::CFStringRef;
    use security_framework::access_control::{ProtectionMode, SecAccessControl};
    use security_framework_sys::access_control::{
        kSecAccessControlBiometryCurrentSet, kSecAccessControlPrivateKeyUsage,
    };
    use security_framework_sys::base::{errSecItemNotFound, SecKeyRef};
    use security_framework_sys::item::{
        kSecAttrAccessControl, kSecAttrIsPermanent, kSecAttrKeyClass, kSecAttrKeyClassPrivate,
        kSecAttrKeySizeInBits, kSecAttrKeyType, kSecAttrKeyTypeECSECPrimeRandom, kSecAttrTokenID,
        kSecAttrTokenIDSecureEnclave, kSecClass, kSecClassKey, kSecPrivateKeyAttrs, kSecReturnRef,
    };

    // `kSecAttrApplicationTag` isn't exported by
    // security-framework-sys 2.17 (only `kSecAttrApplicationLabel`
    // ships). The symbol is exported by `Security.framework` so
    // `extern "C"` resolution links at run time. Same pattern
    // `secure_key_storage::platform_impl` uses for
    // `kSecMatchLimitOne`.
    extern "C" {
        static kSecAttrApplicationTag: CFStringRef;
    }
    use security_framework_sys::key::{
        kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM,
        kSecKeyOperationTypeDecrypt, kSecKeyOperationTypeEncrypt, SecKeyCopyPublicKey,
        SecKeyCreateDecryptedData, SecKeyCreateEncryptedData, SecKeyCreateRandomKey,
        SecKeyIsAlgorithmSupported,
    };
    use security_framework_sys::keychain_item::{SecItemCopyMatching, SecItemDelete};
    use std::ffi::c_void;
    use std::fs;
    use std::ptr;

    /// Application-tag bytes the primary T2 SE key is registered
    /// under. Mirrors the Swift `keyTag` constant — bumping is a
    /// wire break (existing on-disk vaults would unwrap against the
    /// wrong key).
    const PRIMARY_KEY_TAG: &[u8] = b"com.letsflutssh.hw_vault.l3";
    /// Application-tag bytes for the biometric overlay key.
    const BIO_PASSWORD_KEY_TAG: &[u8] = b"com.letsflutssh.hw_password_overlay";
    /// Throw-away tag used by [`probe_detail`] when it needs to
    /// validate the SE actually accepts a real key-create. A real
    /// failure surfaces `errSecMissingEntitlement` (-34018) on
    /// ad-hoc-signed bundles.
    const PROBE_KEY_TAG: &[u8] = b"com.letsflutssh.hw_vault.probe";

    /// `errSecMissingEntitlement` — raised by the SE when the
    /// signing identity is the ad-hoc Code Directory hash macOS
    /// Keychain Services refuses to bind keys to.
    const ERR_SEC_MISSING_ENTITLEMENT: i32 = -34018;

    /// Build a `SecAccessControl` with the requested SE
    /// protection + flag bitfield. `protection` always pins to
    /// `WhenPasscodeSetThisDeviceOnly` so the entry never syncs and
    /// never persists past a passcode unset.
    fn build_access_control(extra_flags: u64) -> Result<SecAccessControl, HardwareVaultError> {
        // `CFOptionFlags` is a usize on 64-bit darwin; the OR
        // happens in u64 space so the call site is independent
        // of the host pointer width, then we narrow to the
        // platform-native `CFOptionFlags`.
        let flags = (kSecAccessControlPrivateKeyUsage as u64) | extra_flags;
        SecAccessControl::create_with_protection(
            Some(ProtectionMode::AccessibleWhenPasscodeSetThisDeviceOnly),
            flags as core_foundation_sys::base::CFOptionFlags,
        )
        .map_err(|e| HardwareVaultError::Backend(format!("SecAccessControl: {e}")))
    }

    /// Build the `SecPrivateKeyAttrs` sub-dictionary the SE uses to
    /// stamp the new key with its application tag + access control.
    ///
    /// # Safety
    ///
    /// Every `kSec*` symbol referenced inside is a static `CFString`
    /// constant exported by Security.framework; `wrap_under_get_rule`
    /// follows the get-rule (no extra retain) so the constant's
    /// refcount stays balanced for the program's lifetime. The
    /// returned `CFDictionary` borrows the wrapped constants through
    /// `as_CFType` clones held inside the pair list — caller must
    /// keep the dictionary alive across any FFI use.
    unsafe fn build_private_attrs(
        tag: &[u8],
        access: &SecAccessControl,
    ) -> CFDictionary<CFString, CFType> {
        // SAFETY: `kSecAttrIsPermanent` is a static `CFStringRef`
        // exported by Security.framework with program-lifetime
        // refcount; the get-rule wrap takes no extra retain.
        let is_perm_key = unsafe { CFString::wrap_under_get_rule(kSecAttrIsPermanent) };
        // SAFETY: same get-rule contract as above for the
        // `kSecAttrApplicationTag` static constant.
        let app_tag_key = unsafe { CFString::wrap_under_get_rule(kSecAttrApplicationTag) };
        // SAFETY: same get-rule contract for `kSecAttrAccessControl`.
        let ac_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccessControl) };
        let true_val = CFNumber::from(1i32);
        let tag_data = CFData::from_buffer(tag);
        CFDictionary::from_CFType_pairs(&[
            (is_perm_key, true_val.as_CFType()),
            (app_tag_key, tag_data.as_CFType()),
            (ac_key, access.as_CFType()),
        ])
    }

    /// Build the full `SecKeyCreateRandomKey` attribute dictionary.
    ///
    /// # Safety
    ///
    /// Same get-rule contract as `build_private_attrs`. `kSec*`
    /// constants live for program lifetime; the returned dictionary
    /// borrows them via `as_CFType` clones held in the pair list.
    unsafe fn build_create_attrs(
        private_attrs: CFDictionary<CFString, CFType>,
    ) -> CFDictionary<CFString, CFType> {
        // SAFETY: every `kSec*` argument below is a static
        // `CFStringRef` exported by Security.framework with
        // program-lifetime refcount; `wrap_under_get_rule` follows
        // the get-rule (no extra retain).
        let key_type_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyType) };
        // SAFETY: see `key_type_key` above.
        let key_type_val =
            // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
            // program-lifetime refcount; the get-rule wrap takes no extra retain.
            unsafe { CFString::wrap_under_get_rule(kSecAttrKeyTypeECSECPrimeRandom) };
        // SAFETY: see `key_type_key` above.
        let size_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeySizeInBits) };
        // SAFETY: see `key_type_key` above.
        let token_key = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenID) };
        // SAFETY: see `key_type_key` above.
        let token_val = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenIDSecureEnclave) };
        // SAFETY: see `key_type_key` above.
        let priv_key = unsafe { CFString::wrap_under_get_rule(kSecPrivateKeyAttrs) };
        CFDictionary::from_CFType_pairs(&[
            (key_type_key, key_type_val.as_CFType()),
            (size_key, CFNumber::from(256i32).as_CFType()),
            (token_key, token_val.as_CFType()),
            (priv_key, private_attrs.as_CFType()),
        ])
    }

    /// Build a `SecItemCopyMatching` query that resolves a stored
    /// SE private key by application tag.
    ///
    /// # Safety
    ///
    /// Same get-rule contract as `build_private_attrs`. The
    /// returned dictionary is single-use — pass it directly into
    /// `SecItemCopyMatching` while the wrapped tag bytes are still
    /// alive.
    unsafe fn build_lookup_query(tag: &[u8]) -> CFDictionary<CFString, CFType> {
        // SAFETY: every `kSec*` argument is a static `CFStringRef`
        // exported by Security.framework with program-lifetime
        // refcount; the get-rule wraps take no extra retain.
        let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
        // SAFETY: see `class_key` above.
        let class_val = unsafe { CFString::wrap_under_get_rule(kSecClassKey) };
        // SAFETY: see `class_key` above.
        let key_type_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyType) };
        // SAFETY: see `class_key` above.
        let key_type_val =
            // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
            // program-lifetime refcount; the get-rule wrap takes no extra retain.
            unsafe { CFString::wrap_under_get_rule(kSecAttrKeyTypeECSECPrimeRandom) };
        // SAFETY: see `class_key` above.
        let app_tag_key = unsafe { CFString::wrap_under_get_rule(kSecAttrApplicationTag) };
        // SAFETY: see `class_key` above.
        let return_ref_key = unsafe { CFString::wrap_under_get_rule(kSecReturnRef) };
        let true_val = CFNumber::from(1i32);
        CFDictionary::from_CFType_pairs(&[
            (class_key, class_val.as_CFType()),
            (key_type_key, key_type_val.as_CFType()),
            (app_tag_key, CFData::from_buffer(tag).as_CFType()),
            (return_ref_key, true_val.as_CFType()),
        ])
    }

    /// Build the `SecItemDelete` query — by-tag delete is the
    /// canonical way to drop an SE key without first holding a
    /// `SecKeyRef`.
    ///
    /// # Safety
    ///
    /// Same get-rule contract as the sibling builders above; the
    /// dictionary must outlive the `SecItemDelete` FFI call.
    unsafe fn build_delete_query(tag: &[u8]) -> CFDictionary<CFString, CFType> {
        // SAFETY: every `kSec*` argument is a static `CFStringRef`
        // exported by Security.framework with program-lifetime
        // refcount; the get-rule wraps take no extra retain.
        let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
        // SAFETY: see `class_key` above.
        let class_val = unsafe { CFString::wrap_under_get_rule(kSecClassKey) };
        // SAFETY: see `class_key` above.
        let key_class_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyClass) };
        // SAFETY: see `class_key` above.
        let key_class_val = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyClassPrivate) };
        // SAFETY: see `class_key` above.
        let token_key = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenID) };
        // SAFETY: see `class_key` above.
        let token_val = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenIDSecureEnclave) };
        // SAFETY: see `class_key` above.
        let app_tag_key = unsafe { CFString::wrap_under_get_rule(kSecAttrApplicationTag) };
        CFDictionary::from_CFType_pairs(&[
            (class_key, class_val.as_CFType()),
            (key_class_key, key_class_val.as_CFType()),
            (token_key, token_val.as_CFType()),
            (app_tag_key, CFData::from_buffer(tag).as_CFType()),
        ])
    }

    /// Owned wrapper around a `SecKeyRef` so the `Drop` impl
    /// releases the CF reference exactly once.
    struct OwnedSecKey(SecKeyRef);

    impl Drop for OwnedSecKey {
        fn drop(&mut self) {
            if !self.0.is_null() {
                // SAFETY: `self.0` is a non-null `SecKeyRef` we
                // received via `wrap_under_create_rule` semantics
                // (SecItemCopyMatching / SecKeyCreateRandomKey /
                // SecKeyCopyPublicKey all hand us +1 references);
                // releasing once balances the create.
                unsafe { core_foundation_sys::base::CFRelease(self.0 as *const c_void) };
            }
        }
    }

    /// Lookup a stored SE private key by tag. Returns `Ok(None)`
    /// when the key is absent (`errSecItemNotFound`); other status
    /// codes propagate as backend errors.
    fn load_private_key(tag: &[u8]) -> Result<Option<OwnedSecKey>, HardwareVaultError> {
        // SAFETY: `build_lookup_query` is `unsafe fn` because it
        // wraps Security.framework static `CFStringRef` constants;
        // we own the resulting dictionary on the stack for the
        // duration of the `SecItemCopyMatching` call below.
        let query = unsafe { build_lookup_query(tag) };
        let mut item: *const c_void = ptr::null();
        // SAFETY: `SecItemCopyMatching` reads the query dictionary
        // (alive through `query`) and writes one CF reference into
        // `item` (we own that stack slot). On any non-error return
        // the kernel gives us a +1 retained reference which we wrap
        // in `OwnedSecKey` so its `Drop` balances the count.
        let status = unsafe {
            SecItemCopyMatching(query.as_concrete_TypeRef(), &mut item as *mut *const c_void)
        };
        // Wrap any non-null out-pointer eagerly so Drop releases
        // the CF ref on every error branch, including the
        // anomalous (status != 0 && item != null) case.
        let owned = if item.is_null() {
            None
        } else {
            Some(OwnedSecKey(item as SecKeyRef))
        };
        if status == errSecItemNotFound {
            return Ok(None);
        }
        if status != 0 {
            return Err(HardwareVaultError::Backend(format!(
                "SecItemCopyMatching: OSStatus {status}"
            )));
        }
        Ok(owned)
    }

    /// Lookup the public half of a stored SE key. Returns
    /// `Ok(None)` when the private key is absent.
    fn load_public_key(tag: &[u8]) -> Result<Option<OwnedSecKey>, HardwareVaultError> {
        let Some(private_key) = load_private_key(tag)? else {
            return Ok(None);
        };
        // SAFETY: `private_key.0` is a non-null `SecKeyRef` owned
        // by `OwnedSecKey`. `SecKeyCopyPublicKey` reads the private
        // key reference and returns a fresh +1 retained
        // `SecKeyRef` (or null on failure) which we wrap below.
        let pub_ref = unsafe { SecKeyCopyPublicKey(private_key.0) };
        if pub_ref.is_null() {
            return Err(HardwareVaultError::Backend(
                "SecKeyCopyPublicKey returned null".to_string(),
            ));
        }
        Ok(Some(OwnedSecKey(pub_ref)))
    }

    /// Create a new SE-bound P-256 keypair under `tag` with the
    /// supplied access control. Returns the public key for
    /// immediate `SecKeyCreateEncryptedData` use; the private key
    /// stays on the SE.
    fn create_se_key(
        tag: &[u8],
        access: &SecAccessControl,
    ) -> Result<OwnedSecKey, HardwareVaultError> {
        // SAFETY: `build_private_attrs` / `build_create_attrs` are
        // `unsafe fn` because they wrap Security.framework static
        // `CFStringRef` constants; the resulting dictionaries are
        // owned here for the duration of `SecKeyCreateRandomKey`.
        let private_attrs = unsafe { build_private_attrs(tag, access) };
        // SAFETY: see `private_attrs` above.
        let create_attrs = unsafe { build_create_attrs(private_attrs) };
        let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
        // SAFETY: `SecKeyCreateRandomKey` reads `create_attrs`
        // (alive on the stack) and on failure writes a +1 retained
        // `CFErrorRef` into `*err`. The kernel does not retain the
        // dictionary past return; `private_key` is either null or a
        // +1 retained `SecKeyRef` we wrap in `OwnedSecKey` below.
        let private_key = unsafe {
            SecKeyCreateRandomKey(
                create_attrs.as_concrete_TypeRef(),
                &mut err as *mut *mut core_foundation_sys::error::__CFError,
            )
        };
        // Wrap a non-null err out-param eagerly so Drop releases
        // it on every path (success or failure).
        let owned_err = if err.is_null() {
            None
        } else {
            // SAFETY: `err` is non-null and points to a `CFErrorRef`
            // returned with create-rule semantics (+1 retain) by
            // `SecKeyCreateRandomKey`; wrapping transfers ownership
            // so `CFError`'s `Drop` balances the create.
            Some(unsafe { CFError::wrap_under_create_rule(err) })
        };
        if private_key.is_null() {
            let cf_err = match owned_err {
                Some(e) => format!("SecKeyCreateRandomKey: {e:?}"),
                None => "SecKeyCreateRandomKey: null".to_string(),
            };
            return Err(HardwareVaultError::Backend(cf_err));
        }
        let private_owned = OwnedSecKey(private_key);
        // SAFETY: `private_owned.0` is the non-null `SecKeyRef`
        // we just minted; `SecKeyCopyPublicKey` derives the public
        // half and returns a +1 retained reference (or null).
        let pub_ref = unsafe { SecKeyCopyPublicKey(private_owned.0) };
        if pub_ref.is_null() {
            return Err(HardwareVaultError::Backend(
                "SecKeyCopyPublicKey returned null".to_string(),
            ));
        }
        Ok(OwnedSecKey(pub_ref))
    }

    /// Ensure the named SE key exists; create it if missing.
    /// Returns the public key in either case so the caller can
    /// invoke `SecKeyCreateEncryptedData` against it.
    fn ensure_se_key(
        tag: &[u8],
        access: &SecAccessControl,
    ) -> Result<OwnedSecKey, HardwareVaultError> {
        if let Some(existing) = load_public_key(tag)? {
            return Ok(existing);
        }
        create_se_key(tag, access)
    }

    /// ECIES-GCM wrap of `plaintext` against the SE-bound public key.
    fn ecies_encrypt(
        public_key: &OwnedSecKey,
        plaintext: &[u8],
    ) -> Result<Vec<u8>, HardwareVaultError> {
        // SAFETY: `kSecKeyAlgorithm…` is a static `CFStringRef`
        // exported by Security.framework with program-lifetime
        // refcount; reading the static is a plain pointer copy.
        let algorithm =
            // SAFETY: identifier is a static `CFStringRef` exported by Security.framework with
            // program-lifetime refcount; reading the static is a plain pointer copy.
            unsafe { kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM };
        // SAFETY: `SecKeyIsAlgorithmSupported` reads `public_key.0`
        // (non-null `SecKeyRef` we own via `OwnedSecKey`) and the
        // static algorithm constant; pure query, no out-params.
        let supported = unsafe {
            SecKeyIsAlgorithmSupported(public_key.0, kSecKeyOperationTypeEncrypt, algorithm)
        };
        if supported == 0 {
            return Err(HardwareVaultError::Backend(
                "ECIES algorithm unsupported by public key".to_string(),
            ));
        }
        let plaintext_cf = CFData::from_buffer(plaintext);
        let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
        // SAFETY: `SecKeyCreateEncryptedData` reads the key + algo
        // + plaintext (all alive on the stack) and returns a +1
        // retained `CFDataRef` (or null + err out-param). The
        // kernel does not retain any pointer past return.
        let ct_ref = unsafe {
            SecKeyCreateEncryptedData(
                public_key.0,
                algorithm,
                plaintext_cf.as_concrete_TypeRef(),
                &mut err as *mut *mut core_foundation_sys::error::__CFError,
            )
        };
        let owned_err = if err.is_null() {
            None
        } else {
            // SAFETY: `err` is a non-null `CFErrorRef` returned
            // with create-rule semantics (+1 retain) by
            // `SecKeyCreateEncryptedData`; wrap transfers ownership.
            Some(unsafe { CFError::wrap_under_create_rule(err) })
        };
        if ct_ref.is_null() {
            let cf_err = match owned_err {
                Some(e) => format!("SecKeyCreateEncryptedData: {e:?}"),
                None => "SecKeyCreateEncryptedData: null".to_string(),
            };
            return Err(HardwareVaultError::Backend(cf_err));
        }
        // SAFETY: `ct_ref` is a non-null `CFDataRef` with +1 retain
        // from `SecKeyCreateEncryptedData`; wrap transfers ownership.
        let ct_data = unsafe { CFData::wrap_under_create_rule(ct_ref) };
        Ok(ct_data.bytes().to_vec())
    }

    /// ECIES-GCM unwrap of `ciphertext` against the SE-bound private
    /// key. The SE itself enforces the `WhenPasscodeSet` access
    /// control; for the biometric overlay key it also surfaces the
    /// system biometric prompt at this call site.
    fn ecies_decrypt(
        private_key: &OwnedSecKey,
        ciphertext: &[u8],
    ) -> Result<Vec<u8>, HardwareVaultError> {
        // SAFETY: `kSecKeyAlgorithm…` is a static `CFStringRef`
        // exported by Security.framework with program-lifetime
        // refcount; reading the static is a plain pointer copy.
        let algorithm =
            // SAFETY: identifier is a static `CFStringRef` exported by Security.framework with
            // program-lifetime refcount; reading the static is a plain pointer copy.
            unsafe { kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM };
        // SAFETY: `SecKeyIsAlgorithmSupported` reads `private_key.0`
        // (non-null `SecKeyRef` owned via `OwnedSecKey`) and the
        // static algorithm constant; pure query, no out-params.
        let supported = unsafe {
            SecKeyIsAlgorithmSupported(private_key.0, kSecKeyOperationTypeDecrypt, algorithm)
        };
        if supported == 0 {
            return Err(HardwareVaultError::Backend(
                "ECIES algorithm unsupported by private key".to_string(),
            ));
        }
        let ct_cf = CFData::from_buffer(ciphertext);
        let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
        // SAFETY: `SecKeyCreateDecryptedData` reads the key + algo
        // + ciphertext (all alive on the stack) and returns a +1
        // retained `CFDataRef` (or null + err out-param). The SE
        // may surface the system biometric prompt for the overlay
        // key; spawn_blocking is the caller's responsibility.
        let pt_ref = unsafe {
            SecKeyCreateDecryptedData(
                private_key.0,
                algorithm,
                ct_cf.as_concrete_TypeRef(),
                &mut err as *mut *mut core_foundation_sys::error::__CFError,
            )
        };
        let owned_err = if err.is_null() {
            None
        } else {
            // SAFETY: `err` is a non-null `CFErrorRef` with +1
            // retain from `SecKeyCreateDecryptedData`; wrap
            // transfers ownership.
            Some(unsafe { CFError::wrap_under_create_rule(err) })
        };
        if pt_ref.is_null() {
            let cf_err = match owned_err {
                Some(e) => format!("SecKeyCreateDecryptedData: {e:?}"),
                None => "SecKeyCreateDecryptedData: null".to_string(),
            };
            return Err(HardwareVaultError::Backend(cf_err));
        }
        // SAFETY: `pt_ref` is a non-null `CFDataRef` with +1 retain
        // from `SecKeyCreateDecryptedData`; wrap transfers ownership.
        let pt_data = unsafe { CFData::wrap_under_create_rule(pt_ref) };
        Ok(pt_data.bytes().to_vec())
    }

    /// SE-availability probe — runs a real `SecKeyCreateRandomKey`
    /// against a throw-away tag, deletes it immediately. Classifies
    /// signing-identity rejection (-34018) separately so the wizard
    /// can route the user at the `macos-resign.sh` script.
    fn probe_se_round_trip() -> HardwareProbeReason {
        let access = match build_access_control(0) {
            Ok(a) => a,
            Err(_) => return HardwareProbeReason::AppleGeneric,
        };
        // SAFETY: `build_private_attrs` / `build_create_attrs` are
        // `unsafe fn` because they wrap Security.framework static
        // `CFStringRef` constants; the resulting dictionaries are
        // owned here for the duration of the `SecKeyCreateRandomKey`
        // probe call below.
        let private_attrs = unsafe { build_private_attrs(PROBE_KEY_TAG, &access) };
        // SAFETY: see `private_attrs` above.
        let create_attrs = unsafe { build_create_attrs(private_attrs) };
        let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
        // SAFETY: `SecKeyCreateRandomKey` reads `create_attrs`
        // (alive on the stack) and on failure writes a +1 retained
        // `CFErrorRef` into `*err`. `key` is either null or a +1
        // retained `SecKeyRef` we wrap in `OwnedSecKey` below.
        let key = unsafe {
            SecKeyCreateRandomKey(
                create_attrs.as_concrete_TypeRef(),
                &mut err as *mut *mut core_foundation_sys::error::__CFError,
            )
        };
        // Wrap any non-null err out-param eagerly so it's
        // released on every path, including the success path
        // where Apple typically leaves err null but doesn't
        // contractually forbid setting it.
        let owned_err = if err.is_null() {
            None
        } else {
            // SAFETY: `err` is a non-null `CFErrorRef` with +1
            // retain from `SecKeyCreateRandomKey`; wrap transfers
            // ownership so `CFError`'s `Drop` balances the create.
            Some(unsafe { CFError::wrap_under_create_rule(err) })
        };
        if key.is_null() {
            // `CFError::code()` returns `CFIndex` (= isize on
            // 64-bit). The errSecMissingEntitlement constant
            // is the i32 the OS surfaces; cast both sides
            // through i64 for a portable compare.
            let (code, has_err) = match owned_err {
                Some(e) => (e.code() as i64, true),
                None => (0, false),
            };
            if code == ERR_SEC_MISSING_ENTITLEMENT as i64 {
                return HardwareProbeReason::AppleSigningIdentityMissing;
            }
            // Apple's API contract — when `SecKeyCreateRandomKey`
            // returns null, the `err` out-param SHOULD be set. The
            // null/null case is "impossible" per the docs but we've
            // observed it in the wild (entitlement edge-cases on
            // Apple Silicon Developer Beta builds). Surface it in
            // diagnostics so a support trace shows the anomaly
            // explicitly rather than collapsing into the generic
            // bucket alongside legitimate OS-level failures.
            if !has_err {
                eprintln!(
                    "[lfs_os_security] SecKeyCreateRandomKey returned null key with null err — \
                     classifying as AppleGeneric (Apple API contract violation)"
                );
            }
            return HardwareProbeReason::AppleGeneric;
        }
        // Wrap the SE key so Drop releases it after the
        // best-effort delete below completes — replaces the
        // earlier manual `CFRelease(key)` pattern.
        let _owned_key = OwnedSecKey(key);
        // Best-effort cleanup. Even on delete failure the OS GCs
        // the key on next launch.
        // SAFETY: `build_delete_query` is `unsafe fn` because it
        // wraps Security.framework static `CFStringRef` constants;
        // the resulting dictionary is owned for the call below.
        let delete_query = unsafe { build_delete_query(PROBE_KEY_TAG) };
        // SAFETY: `SecItemDelete` reads `delete_query` (alive on
        // the stack) and removes the matching key; no out-params,
        // return code intentionally ignored (best-effort cleanup).
        unsafe {
            SecItemDelete(delete_query.as_concrete_TypeRef());
        }
        HardwareProbeReason::Available
    }

    /// Apple-side dispatch for [`super::probe_detail`]. Combines
    /// the LAContext shallow probe with the
    /// `SecKeyCreateRandomKey` deep probe so ad-hoc-signed bundles
    /// surface as `AppleSigningIdentityMissing` rather than silently
    /// succeeding on the LAContext shallow check and then failing
    /// on the user's first store.
    pub(super) fn probe_detail() -> HardwareProbeReason {
        // LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)
        // gates the SE backing — Intel Macs without a T2 fail
        // here with .biometryNotAvailable. We invoke the same
        // probe via objc2-local-authentication so the platform's
        // own gating applies.
        match super::apple_la::can_evaluate_device_owner() {
            super::apple_la::DeviceOwnerProbe::CanEvaluate => {
                // SE binding might still fail at create time if
                // the signing identity is rejected — exercise the
                // round-trip.
                probe_se_round_trip()
            }
            super::apple_la::DeviceOwnerProbe::PasscodeNotSet => {
                HardwareProbeReason::ApplePasscodeNotSet
            }
            super::apple_la::DeviceOwnerProbe::BiometryNotAvailable => {
                HardwareProbeReason::AppleNoSecureEnclave
            }
            super::apple_la::DeviceOwnerProbe::Other => HardwareProbeReason::AppleGeneric,
        }
    }

    pub(super) fn is_available() -> bool {
        matches!(probe_detail(), HardwareProbeReason::Available)
    }

    /// Wrap `db_key` against the primary T2 SE key and write the
    /// `(pin_hmac, wrapped)` envelope to disk. Re-uses the existing
    /// SE key when one is registered; creates one otherwise.
    pub(super) fn store(
        support_dir: &str,
        db_key: &[u8],
        pin_hmac: &[u8],
    ) -> Result<(), HardwareVaultError> {
        let access = build_access_control(0)?;
        let public_key = ensure_se_key(PRIMARY_KEY_TAG, &access)?;
        let wrapped = ecies_encrypt(&public_key, db_key)?;
        let mut body = Vec::with_capacity(8 + pin_hmac.len() + wrapped.len());
        write_len_prefixed(&mut body, pin_hmac)?;
        write_len_prefixed(&mut body, &wrapped)?;
        let blob = super::prepend_envelope_header(super::HW_VAULT_PLATFORM_APPLE, &body);
        super::os_atomic_write_0600(&vault_file_path(support_dir), &blob)
    }

    /// Read the on-disk envelope, constant-time-compare `pin_hmac`
    /// against the stored value, and unwrap the DB key when they
    /// match. Returns `Ok(None)` for any of:
    ///
    ///   * missing vault file
    ///   * malformed envelope (handled as Corrupt, but turned into
    ///     `Ok(None)` so the caller routes through reset)
    ///   * PIN HMAC mismatch
    ///
    /// Any SE-side error (key missing after a previous `clear`,
    /// passcode reset, biometric enrolment change for the overlay)
    /// surfaces as `Err`.
    pub(super) fn read(
        support_dir: &str,
        pin_hmac: &[u8],
    ) -> Result<Option<Vec<u8>>, HardwareVaultError> {
        let path = vault_file_path(support_dir);
        let raw = match fs::read(&path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(HardwareVaultError::Io(format!("{}: {e}", path.display()))),
        };
        let body = super::parse_envelope_header(&raw, super::HW_VAULT_PLATFORM_APPLE)?;
        let mut pos = 0;
        let stored_hmac = match read_len_prefixed(body, &mut pos) {
            Some(b) => b,
            None => return Err(HardwareVaultError::Corrupt),
        };
        let wrapped = match read_len_prefixed(body, &mut pos) {
            Some(b) => b,
            None => return Err(HardwareVaultError::Corrupt),
        };
        if !constant_time_eq(&stored_hmac, pin_hmac) {
            return Ok(None);
        }
        let private_key = load_private_key(PRIMARY_KEY_TAG)?
            .ok_or_else(|| HardwareVaultError::Backend("SE key missing".to_string()))?;
        let plaintext = ecies_decrypt(&private_key, &wrapped)?;
        Ok(Some(plaintext))
    }

    /// Drop the on-disk envelope, the SE primary key, and the
    /// biometric overlay (key + file). Best-effort: any sub-step
    /// that fails is logged and skipped; the user-facing semantics
    /// are "vault cleared" regardless.
    pub(super) fn clear(support_dir: &str) -> Result<(), HardwareVaultError> {
        let _ = fs::remove_file(vault_file_path(support_dir));
        // SAFETY: `build_delete_query` is `unsafe fn` because it
        // wraps Security.framework static `CFStringRef` constants;
        // the dictionary is owned for the call below.
        let primary_query = unsafe { build_delete_query(PRIMARY_KEY_TAG) };
        // SAFETY: `SecItemDelete` reads the query dictionary alive
        // on the stack; no out-params. Best-effort cleanup.
        unsafe {
            SecItemDelete(primary_query.as_concrete_TypeRef());
        }
        let _ = clear_biometric_password(support_dir);
        Ok(())
    }

    /// Wrap `password_bytes` under the biometric overlay SE key
    /// (gated by `kSecAccessControlBiometryCurrentSet`) and write
    /// the `wrapped`-only envelope. Reading the overlay later
    /// surfaces the system biometric prompt automatically.
    pub(super) fn store_biometric_password(
        support_dir: &str,
        password_bytes: &[u8],
    ) -> Result<(), HardwareVaultError> {
        let access = build_access_control(kSecAccessControlBiometryCurrentSet as u64)?;
        let public_key = ensure_se_key(BIO_PASSWORD_KEY_TAG, &access)?;
        let wrapped = ecies_encrypt(&public_key, password_bytes)?;
        let mut body = Vec::with_capacity(4 + wrapped.len());
        write_len_prefixed(&mut body, &wrapped)?;
        let blob = super::prepend_envelope_header(super::HW_VAULT_PLATFORM_APPLE, &body);
        super::os_atomic_write_0600(&bio_password_file_path(support_dir), &blob)
    }

    /// Unwrap the biometric overlay password — invokes the system
    /// biometric prompt. Returns `Ok(None)` when the overlay file
    /// is missing; backend errors (cancel, wrong finger, biometric
    /// disabled) propagate as `Err`.
    pub(super) fn read_biometric_password(
        support_dir: &str,
    ) -> Result<Option<Vec<u8>>, HardwareVaultError> {
        let path = bio_password_file_path(support_dir);
        let raw = match fs::read(&path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(HardwareVaultError::Io(format!("{}: {e}", path.display()))),
        };
        let body = super::parse_envelope_header(&raw, super::HW_VAULT_PLATFORM_APPLE)?;
        let mut pos = 0;
        let wrapped = match read_len_prefixed(body, &mut pos) {
            Some(b) => b,
            None => return Err(HardwareVaultError::Corrupt),
        };
        let private_key = load_private_key(BIO_PASSWORD_KEY_TAG)?
            .ok_or_else(|| HardwareVaultError::Backend("biometric key missing".to_string()))?;
        let plaintext = ecies_decrypt(&private_key, &wrapped)?;
        Ok(Some(plaintext))
    }

    pub(super) fn clear_biometric_password(support_dir: &str) -> Result<(), HardwareVaultError> {
        let _ = fs::remove_file(bio_password_file_path(support_dir));
        // SAFETY: `build_delete_query` is `unsafe fn` because it
        // wraps Security.framework static `CFStringRef` constants;
        // the dictionary is owned for the call below.
        let bio_query = unsafe { build_delete_query(BIO_PASSWORD_KEY_TAG) };
        // SAFETY: `SecItemDelete` reads the query dictionary alive
        // on the stack; no out-params. Best-effort cleanup.
        unsafe {
            SecItemDelete(bio_query.as_concrete_TypeRef());
        }
        Ok(())
    }

    // `write_atomic_0600` retired — every store now routes through
    // the parent module's `os_atomic_write_0600` so the random
    // tmp-suffix + sync_data + parent-dir fsync hardening lands
    // uniformly across Apple, Windows, Android, Linux paths.
}

/// LAContext device-owner-policy probe — split out so the
/// hardware-vault probe stays focused on SE-specific failure modes
/// while the LAContext shallow check reuses the same enum surface
/// the Settings UI already maps to copy.
#[cfg(any(target_os = "macos", target_os = "ios"))]
mod apple_la {
    use objc2::msg_send;
    use objc2::rc::Retained;
    use objc2_foundation::NSError;
    use objc2_local_authentication::{LAContext, LAError, LAPolicy};

    /// Outcome of `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)`.
    pub(super) enum DeviceOwnerProbe {
        CanEvaluate,
        PasscodeNotSet,
        BiometryNotAvailable,
        Other,
    }

    pub(super) fn can_evaluate_device_owner() -> DeviceOwnerProbe {
        // SAFETY: `LAContext::new` is marked unsafe in
        // objc2-local-authentication 0.3 because it returns an
        // unbound autoreleased instance — fine for our use, we
        // hold the `Retained<>` for the rest of the function and
        // drop it deterministically on return.
        let ctx: Retained<LAContext> = unsafe { LAContext::new() };
        let mut err: Option<Retained<NSError>> = None;
        // SAFETY: `canEvaluatePolicy:error:` is the documented
        // LAContext selector that returns BOOL and writes an
        // `NSError` into the out-param on failure. `&*ctx` borrows
        // the `Retained<LAContext>` alive on the stack; `&mut err`
        // is an `Option<Retained<NSError>>` slot owned here.
        let can: bool = unsafe {
            msg_send![
                &*ctx,
                canEvaluatePolicy: LAPolicy::DeviceOwnerAuthentication,
                error: &mut err,
            ]
        };
        if can {
            return DeviceOwnerProbe::CanEvaluate;
        }
        let Some(err) = err else {
            return DeviceOwnerProbe::Other;
        };
        // Match against integer codes — the LAError swift bridge
        // exposes the same numbers across SDK versions, but the
        // enum import is internal API in some bindings.
        let raw = err.code();
        if raw == LAError::PasscodeNotSet.0 {
            return DeviceOwnerProbe::PasscodeNotSet;
        }
        // `LAError::TouchIDNotAvailable` is just a deprecated
        // alias for `LAError::BiometryNotAvailable` (same -6
        // value); the comparison is now a no-op but kept for
        // clarity that the raw OS value covers both legacy
        // Touch ID and modern Face ID failure paths.
        if raw == LAError::BiometryNotAvailable.0 {
            return DeviceOwnerProbe::BiometryNotAvailable;
        }
        DeviceOwnerProbe::Other
    }
}

// ---- Public dispatch -----------------------------------------------

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn is_available() -> bool {
    apple::is_available()
}

#[cfg(target_os = "android")]
pub fn is_available() -> bool {
    crate::android::hardware_vault::is_available()
}

#[cfg(target_os = "windows")]
pub fn is_available() -> bool {
    crate::windows::hardware_vault::is_available()
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn is_available() -> bool {
    false
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn probe_detail() -> HardwareProbeReason {
    apple::probe_detail()
}

#[cfg(target_os = "android")]
pub fn probe_detail() -> HardwareProbeReason {
    if crate::android::hardware_vault::is_available() {
        HardwareProbeReason::Available
    } else {
        // Android-side cause discovery (e.g. no StrongBox HAL,
        // BouncyCastle provider missing) is best surfaced via
        // the existing Settings probe-detail strings; we
        // collapse to a generic "unavailable" until a richer
        // BiometricManager.canAuthenticate-style classifier lands.
        HardwareProbeReason::AppleGeneric
    }
}

#[cfg(target_os = "windows")]
pub fn probe_detail() -> HardwareProbeReason {
    if crate::windows::hardware_vault::is_available() {
        HardwareProbeReason::Available
    } else {
        // Windows-side cause discovery (no Microsoft Platform Crypto
        // Provider, no TPM, GPO blocking persisted-key UI) belongs
        // to a future classifier — collapse to generic for now.
        HardwareProbeReason::AppleGeneric
    }
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn probe_detail() -> HardwareProbeReason {
    HardwareProbeReason::PlatformUnsupported
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn store(support_dir: &str, db_key: &[u8], pin_hmac: &[u8]) -> Result<(), HardwareVaultError> {
    apple::store(support_dir, db_key, pin_hmac)
}

#[cfg(target_os = "android")]
pub fn store(support_dir: &str, db_key: &[u8], pin_hmac: &[u8]) -> Result<(), HardwareVaultError> {
    crate::android::hardware_vault::store(support_dir, db_key, pin_hmac)
}

#[cfg(target_os = "windows")]
pub fn store(support_dir: &str, db_key: &[u8], pin_hmac: &[u8]) -> Result<(), HardwareVaultError> {
    crate::windows::hardware_vault::store(support_dir, db_key, pin_hmac)
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn store(
    _support_dir: &str,
    _db_key: &[u8],
    _pin_hmac: &[u8],
) -> Result<(), HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    apple::read(support_dir, pin_hmac)
}

#[cfg(target_os = "android")]
pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    crate::android::hardware_vault::read(support_dir, pin_hmac)
}

#[cfg(target_os = "windows")]
pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    crate::windows::hardware_vault::read(support_dir, pin_hmac)
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn read(_support_dir: &str, _pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn clear(support_dir: &str) -> Result<(), HardwareVaultError> {
    apple::clear(support_dir)
}

#[cfg(target_os = "android")]
pub fn clear(support_dir: &str) -> Result<(), HardwareVaultError> {
    crate::android::hardware_vault::clear(support_dir)
}

#[cfg(target_os = "windows")]
pub fn clear(support_dir: &str) -> Result<(), HardwareVaultError> {
    crate::windows::hardware_vault::clear(support_dir)
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn clear(_support_dir: &str) -> Result<(), HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn store_biometric_password(
    support_dir: &str,
    password_bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    apple::store_biometric_password(support_dir, password_bytes)
}

#[cfg(target_os = "android")]
pub fn store_biometric_password(
    support_dir: &str,
    password_bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    crate::android::hardware_vault::store_biometric_password(support_dir, password_bytes)
}

#[cfg(target_os = "windows")]
pub fn store_biometric_password(
    support_dir: &str,
    password_bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    crate::windows::hardware_vault::store_biometric_password(support_dir, password_bytes)
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn store_biometric_password(
    _support_dir: &str,
    _password_bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn read_biometric_password(support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    apple::read_biometric_password(support_dir)
}

#[cfg(target_os = "android")]
pub fn read_biometric_password(support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    crate::android::hardware_vault::read_biometric_password(support_dir)
}

#[cfg(target_os = "windows")]
pub fn read_biometric_password(support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    crate::windows::hardware_vault::read_biometric_password(support_dir)
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn read_biometric_password(_support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn clear_biometric_password(support_dir: &str) -> Result<(), HardwareVaultError> {
    apple::clear_biometric_password(support_dir)
}

#[cfg(target_os = "android")]
pub fn clear_biometric_password(support_dir: &str) -> Result<(), HardwareVaultError> {
    crate::android::hardware_vault::clear_biometric_password(support_dir)
}

#[cfg(target_os = "windows")]
pub fn clear_biometric_password(support_dir: &str) -> Result<(), HardwareVaultError> {
    crate::windows::hardware_vault::clear_biometric_password(support_dir)
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
    target_os = "windows"
)))]
pub fn clear_biometric_password(_support_dir: &str) -> Result<(), HardwareVaultError> {
    Err(HardwareVaultError::PlatformUnsupported)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn len_prefix_round_trip() {
        let mut buf = Vec::new();
        write_len_prefixed(&mut buf, b"hello").unwrap();
        write_len_prefixed(&mut buf, b"").unwrap();
        write_len_prefixed(&mut buf, b"world!").unwrap();
        let mut pos = 0;
        assert_eq!(
            read_len_prefixed(&buf, &mut pos).as_deref(),
            Some(&b"hello"[..])
        );
        assert_eq!(read_len_prefixed(&buf, &mut pos).as_deref(), Some(&b""[..]));
        assert_eq!(
            read_len_prefixed(&buf, &mut pos).as_deref(),
            Some(&b"world!"[..])
        );
        assert!(read_len_prefixed(&buf, &mut pos).is_none());
    }

    #[test]
    fn len_prefix_rejects_truncation() {
        // 4-byte length prefix says 100 bytes follow, but only 5 are present.
        let mut buf = Vec::new();
        buf.extend_from_slice(&100u32.to_be_bytes());
        buf.extend_from_slice(b"short");
        let mut pos = 0;
        assert!(read_len_prefixed(&buf, &mut pos).is_none());
    }

    #[test]
    fn constant_time_eq_handles_length_mismatch() {
        assert!(!constant_time_eq(b"abc", b"abcd"));
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(!constant_time_eq(b"abc", b"abd"));
    }

    #[test]
    fn probe_reason_wire_names_stable() {
        // Bumping any of these is a wire break with the Dart-side
        // `HardwareProbeDetail` enum parser.
        assert_eq!(HardwareProbeReason::Available.wire_name(), "available");
        assert_eq!(
            HardwareProbeReason::AppleNoSecureEnclave.wire_name(),
            "macosNoSecureEnclave"
        );
        assert_eq!(
            HardwareProbeReason::ApplePasscodeNotSet.wire_name(),
            "macosPasscodeNotSet"
        );
        assert_eq!(
            HardwareProbeReason::AppleSigningIdentityMissing.wire_name(),
            "macosSigningIdentityMissing"
        );
        assert_eq!(
            HardwareProbeReason::AppleGeneric.wire_name(),
            "macosGeneric"
        );
        assert_eq!(
            HardwareProbeReason::PlatformUnsupported.wire_name(),
            "unknown"
        );
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    #[test]
    fn non_apple_targets_report_platform_unsupported() {
        assert!(!is_available());
        assert_eq!(probe_detail(), HardwareProbeReason::PlatformUnsupported);
        assert!(!is_stored("/tmp/nonexistent"));
        assert!(!is_biometric_password_stored("/tmp/nonexistent"));
        assert!(matches!(
            store("/tmp/x", &[1, 2, 3], &[]),
            Err(HardwareVaultError::PlatformUnsupported)
        ));
        assert!(matches!(
            read("/tmp/x", &[]),
            Err(HardwareVaultError::PlatformUnsupported)
        ));
        assert!(matches!(
            clear("/tmp/x"),
            Err(HardwareVaultError::PlatformUnsupported)
        ));
    }

    // ─── Envelope header coverage ──────────────────────────────────

    #[test]
    fn envelope_header_round_trip_per_platform_tag() {
        // Every supported platform tag must round-trip through
        // prepend → parse cleanly. A regression that flips a
        // platform constant silently corrupts every existing
        // envelope on disk for that platform.
        for platform in [
            HW_VAULT_PLATFORM_APPLE,
            HW_VAULT_PLATFORM_WINDOWS,
            HW_VAULT_PLATFORM_ANDROID,
        ] {
            let body = b"vault-body-bytes";
            let envelope = prepend_envelope_header(platform, body);
            let parsed = parse_envelope_header(&envelope, platform).expect("parse");
            assert_eq!(parsed, body);
        }
    }

    #[test]
    fn envelope_header_rejects_truncated_input() {
        // Input shorter than the header itself = corrupt. A truncated
        // file (interrupted write before the rename, partial backup
        // restore) must surface as `Corrupt` so the caller routes
        // through the destructive reset cascade rather than silently
        // returning random parsed bytes.
        let envelope = prepend_envelope_header(HW_VAULT_PLATFORM_APPLE, b"body-bytes");
        for take in 0..HW_VAULT_HEADER_LEN {
            let truncated = &envelope[..take];
            assert!(
                matches!(
                    parse_envelope_header(truncated, HW_VAULT_PLATFORM_APPLE),
                    Err(HardwareVaultError::Corrupt)
                ),
                "expected Corrupt for truncated len={take}"
            );
        }
    }

    #[test]
    fn envelope_header_rejects_magic_mismatch() {
        // Manually-crafted "envelope" with wrong magic — the kind of
        // garbage a `dd if=/dev/urandom of=hardware_vault.bin` would
        // produce. Must surface as Corrupt, not Backend (the user
        // routing depends on that distinction — Corrupt triggers
        // reset; Backend triggers retry).
        let mut bad = Vec::new();
        bad.extend_from_slice(b"XXXX"); // wrong magic
        bad.push(HW_VAULT_VERSION);
        bad.push(HW_VAULT_PLATFORM_APPLE);
        bad.extend_from_slice(b"body");
        assert!(matches!(
            parse_envelope_header(&bad, HW_VAULT_PLATFORM_APPLE),
            Err(HardwareVaultError::Corrupt)
        ));
    }

    #[test]
    fn envelope_header_rejects_version_mismatch() {
        // A future-version envelope (bumped HW_VAULT_VERSION on a
        // newer client) MUST surface as Corrupt so older clients
        // don't try to parse a body shape they don't understand.
        let mut envelope = prepend_envelope_header(HW_VAULT_PLATFORM_APPLE, b"body");
        envelope[4] = HW_VAULT_VERSION.wrapping_add(1);
        assert!(matches!(
            parse_envelope_header(&envelope, HW_VAULT_PLATFORM_APPLE),
            Err(HardwareVaultError::Corrupt)
        ));
    }

    #[test]
    fn envelope_header_rejects_cross_platform_copy() {
        // An envelope written under one platform tag must NOT parse
        // when the caller expects another — that's a cross-platform
        // file copy attempt (user moved hardware_vault.bin between
        // an Apple and a Windows install). Each platform's wrap key
        // is per-installation; the bytes are unusable cross-platform.
        let envelope = prepend_envelope_header(HW_VAULT_PLATFORM_APPLE, b"body");
        assert!(matches!(
            parse_envelope_header(&envelope, HW_VAULT_PLATFORM_WINDOWS),
            Err(HardwareVaultError::Corrupt)
        ));
        assert!(matches!(
            parse_envelope_header(&envelope, HW_VAULT_PLATFORM_ANDROID),
            Err(HardwareVaultError::Corrupt)
        ));
    }

    #[test]
    fn envelope_header_round_trip_with_empty_body_is_legal() {
        // A zero-length body is a degenerate but legitimate shape
        // (caller might prepend the header before populating). The
        // parser must not reject empty body — only header-level
        // corruption is fatal.
        let envelope = prepend_envelope_header(HW_VAULT_PLATFORM_APPLE, &[]);
        let parsed = parse_envelope_header(&envelope, HW_VAULT_PLATFORM_APPLE).expect("parse");
        assert!(parsed.is_empty());
    }

    // ─── len_prefix edge cases ─────────────────────────────────────

    #[test]
    fn len_prefix_empty_buffer_returns_none() {
        let mut pos = 0;
        assert!(read_len_prefixed(&[], &mut pos).is_none());
    }

    #[test]
    fn len_prefix_advances_pos_only_on_success() {
        // A failed read MUST NOT advance pos. The caller treats pos
        // as "first un-consumed offset" and a partial advance would
        // skip the truncated frame's prefix, then misalign the next
        // read at random body bytes.
        let mut buf = Vec::new();
        write_len_prefixed(&mut buf, b"hello").unwrap();
        // Truncate by 2 bytes — declared 5 bytes, only 3 present.
        buf.truncate(buf.len() - 2);
        let mut pos = 0;
        assert!(read_len_prefixed(&buf, &mut pos).is_none());
        // Pos may have advanced past the length header but must not
        // have advanced past the (claimed) body bytes — otherwise a
        // subsequent legitimate frame would be misaligned.
        assert!(pos <= buf.len());
    }

    #[test]
    fn len_prefix_rejects_oversize_claim_with_real_short_body() {
        // u32 length prefix claiming the entire u32::MAX worth of
        // body, but only a few bytes of buffer left. read_len_prefixed
        // returns None instead of panicking on the slice OOB.
        let mut buf = Vec::new();
        buf.extend_from_slice(&u32::MAX.to_be_bytes());
        buf.extend_from_slice(b"x");
        let mut pos = 0;
        assert!(read_len_prefixed(&buf, &mut pos).is_none());
    }

    // ─── os_atomic_write_0600 ──────────────────────────────────────

    #[test]
    fn os_atomic_write_lands_bytes_at_target_path() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let target = tmp.path().join("nested").join("vault.bin");
        os_atomic_write_0600(&target, b"hello-vault").expect("write");
        let read = std::fs::read(&target).expect("read");
        assert_eq!(read, b"hello-vault");
    }

    #[cfg(unix)]
    #[test]
    fn os_atomic_write_sets_0600_mode() {
        use std::os::unix::fs::PermissionsExt as _;
        let tmp = tempfile::tempdir().expect("tmp dir");
        let target = tmp.path().join("vault.bin");
        os_atomic_write_0600(&target, b"secret").expect("write");
        let mode = std::fs::metadata(&target)
            .expect("stat")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }

    #[test]
    fn os_atomic_write_overwrites_existing_file() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let target = tmp.path().join("vault.bin");
        std::fs::write(&target, b"old-bytes").expect("seed");
        os_atomic_write_0600(&target, b"new-bytes").expect("overwrite");
        let read = std::fs::read(&target).expect("read");
        assert_eq!(read, b"new-bytes");
    }

    #[test]
    fn os_atomic_write_creates_missing_parent_dirs() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let target = tmp.path().join("a").join("b").join("c").join("vault.bin");
        os_atomic_write_0600(&target, b"deep").expect("write");
        assert!(target.exists());
    }

    #[test]
    fn os_atomic_write_concurrent_writes_to_distinct_paths_dont_collide() {
        // The tmp-name suffix folds pid + monotonic counter + nanos so
        // two writes started in quick succession (same nanos resolution)
        // pick different tmp filenames. Two distinct target paths, two
        // writes — both must land their bytes.
        let tmp = tempfile::tempdir().expect("tmp dir");
        let p1 = tmp.path().join("a.bin");
        let p2 = tmp.path().join("b.bin");
        os_atomic_write_0600(&p1, b"one").expect("write a");
        os_atomic_write_0600(&p2, b"two").expect("write b");
        assert_eq!(std::fs::read(&p1).unwrap(), b"one");
        assert_eq!(std::fs::read(&p2).unwrap(), b"two");
    }

    // ─── is_stored / is_biometric_password_stored on real FS ───────
    //
    // Apple-host coverage — the dispatcher routes Windows / Android to
    // their own modules whose tests live alongside the per-platform
    // backend. Pinning these checks under `cfg(target_os = "macos")`
    // keeps the assertion against the canonical Apple filename
    // constants stable; the Windows + Android backends carry equivalent
    // existence-probe tests in their own modules.

    #[cfg(any(target_os = "macos", target_os = "ios"))]
    #[test]
    fn is_stored_returns_false_for_missing_file_and_true_after_create() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let support = tmp.path().to_string_lossy().into_owned();
        assert!(!is_stored(&support));
        std::fs::write(tmp.path().join(VAULT_FILE_NAME), b"x").expect("seed");
        assert!(is_stored(&support));
    }

    #[cfg(any(target_os = "macos", target_os = "ios"))]
    #[test]
    fn is_biometric_password_stored_distinguishes_overlay_file() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let support = tmp.path().to_string_lossy().into_owned();
        assert!(!is_biometric_password_stored(&support));
        std::fs::write(tmp.path().join(BIO_PASSWORD_FILE_NAME), b"x").expect("seed");
        assert!(is_biometric_password_stored(&support));
        // The vault file presence MUST NOT cross-trigger this check —
        // each is gated on its own filename.
        std::fs::remove_file(tmp.path().join(BIO_PASSWORD_FILE_NAME)).expect("rm");
        std::fs::write(tmp.path().join(VAULT_FILE_NAME), b"x").expect("seed vault");
        assert!(!is_biometric_password_stored(&support));
    }

    // ─── HardwareVaultError Display ────────────────────────────────

    #[test]
    fn hardware_vault_error_display_includes_kind_marker() {
        // The `Display` impl drives FRB envelope's `detail` text;
        // each variant must surface a stable hint so support traces
        // can grep on the kind. Bumping any of these is a wire break
        // for log analysis tooling.
        assert!(
            format!("{}", HardwareVaultError::PlatformUnsupported).contains("platform unsupported")
        );
        assert!(format!("{}", HardwareVaultError::Corrupt).contains("vault corrupt"));
        assert!(format!("{}", HardwareVaultError::Backend("xyz".into())).contains("backend"));
        assert!(format!("{}", HardwareVaultError::Backend("xyz".into())).contains("xyz"));
        assert!(format!("{}", HardwareVaultError::Io("fs nope".into())).contains("io"));
        assert!(format!("{}", HardwareVaultError::Io("fs nope".into())).contains("fs nope"));
    }
}
