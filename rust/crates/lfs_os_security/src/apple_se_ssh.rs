//! Apple Secure Enclave SSH key driver — shared macOS + iOS impl.
//!
//! Generates / lists / signs / deletes ECDSA P-256 keypairs whose
//! private half lives on Apple's Secure Enclave. The chip refuses
//! to export the private bytes — every signing operation routes
//! through `SecKeyCreateSignature` and the OS gates each call on
//! the access-control flags chosen at creation time (Touch ID /
//! Face ID, or device passcode as fallback).
//!
//! ## Algorithm exclusivity
//!
//! ECDSA P-256 only. The SE silicon implements no other curve and
//! no asymmetric primitive beyond ECDSA + ECIES — `SecKeyCreateRandomKey`
//! with `kSecAttrTokenIDSecureEnclave` fails for every other
//! `kSecAttrKeyType`. SSH wire-side this surfaces as
//! `ecdsa-sha2-nistp256` exclusively.
//!
//! ## Access-control policy
//!
//! Two shapes selected per-key at creation:
//!
//! - **Biometry-required** (`kSecAccessControlBiometryCurrentSet`) —
//!   Touch ID / Face ID gates every sign. Re-enrolment invalidates
//!   the key (the chip's biometric template snapshot changes); the
//!   user must re-generate. Strongest binding.
//! - **User-presence** (`kSecAccessControlUserPresence`) — accepts
//!   biometry OR the device passcode as fallback. Survives
//!   re-enrolment but a stolen passcode unlocks every key.
//!
//! Both shapes pin to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
//! so the key never syncs (iCloud Keychain stays out of the loop)
//! and never persists past a passcode unset.
//!
//! ## Application tag
//!
//! Each key is registered under a unique `kSecAttrApplicationTag`
//! blob — `letsflutssh.ssh.<uuid>` — generated at creation time and
//! persisted in `ssh_keys.enclave_tag`. The Keychain query at sign
//! time matches on the tag; storing the tag in our own DB rather
//! than letting Keychain enumerate by partial match keeps the
//! mapping unambiguous when multiple keys co-exist on the same
//! device.
//!
//! ## LAContext caching
//!
//! Mirrors Secretive's `PersistentAuthenticationHandler` pattern:
//! the caller may cache a single `LAContext` per session and pass
//! it via `kSecUseAuthenticationContext` on subsequent
//! `SecItemCopyMatching` calls. The OS skips the biometric prompt
//! while the context's `evaluatedPolicyDomainState` blob is still
//! valid (a few minutes per Apple's docs; we mirror PKCS#11's
//! 5-minute idle drop). For T-5 the caching surface is wired but
//! the per-session reuse path lives at the FRB worker boundary
//! (one `LAContext` per connect / agent dispatch); the in-process
//! ssh-agent endpoint reuses it across SIGN_REQUEST bursts from
//! the same external client.
//!
//! ## Code-signing requirement
//!
//! Unsigned / ad-hoc bundles surface `errSecMissingEntitlement`
//! (`-34018`) on the first `SecKeyCreateRandomKey` call against the
//! SE. Apple's API contract requires the binary to carry a stable
//! signing identity (Developer ID, App Store, or `codesign -s -
//! --identifier <bundle-id>` ad-hoc for self-build users). The
//! probe surfaces this as
//! [`UnavailableReason::CodeSignRequired`] so the UI can route the
//! user at the documented remediation.

#![cfg(any(target_os = "macos", target_os = "ios"))]

use core_foundation::base::{CFType, TCFType};
use core_foundation::data::CFData;
use core_foundation::dictionary::CFDictionary;
use core_foundation::error::CFError;
use core_foundation::number::CFNumber;
use core_foundation::string::CFString;
use core_foundation_sys::string::CFStringRef;
use objc2::rc::Retained;
use objc2_local_authentication::LAContext;
use security_framework::access_control::{ProtectionMode, SecAccessControl};
use security_framework_sys::access_control::{
    kSecAccessControlBiometryCurrentSet, kSecAccessControlPrivateKeyUsage,
    kSecAccessControlUserPresence,
};
use security_framework_sys::base::{errSecItemNotFound, SecKeyRef};
use security_framework_sys::item::{
    kSecAttrAccessControl, kSecAttrIsPermanent, kSecAttrKeyClass, kSecAttrKeyClassPrivate,
    kSecAttrKeySizeInBits, kSecAttrKeyType, kSecAttrKeyTypeECSECPrimeRandom, kSecAttrTokenID,
    kSecAttrTokenIDSecureEnclave, kSecClass, kSecClassKey, kSecMatchLimit, kSecMatchLimitAll,
    kSecPrivateKeyAttrs, kSecReturnAttributes, kSecReturnRef,
};
use security_framework_sys::key::{
    SecKeyCopyExternalRepresentation, SecKeyCopyPublicKey, SecKeyCreateRandomKey,
    SecKeyCreateSignature,
};
use security_framework_sys::keychain_item::{SecItemCopyMatching, SecItemDelete};
use std::ffi::c_void;
use std::ptr;

// `security-framework-sys` doesn't re-export every Security.framework
// symbol we need. `kSecAttrApplicationTag`,
// `kSecUseAuthenticationContext`, and the ECDSA-message algorithm
// are re-declared here as `extern "C"` statics — same pattern the T2
// hardware-vault path uses for the application tag. Each is
// `#[link_name]`-bound to its camelCase OS symbol so the Rust binding
// keeps an `UPPER_CASE` name without a `non_upper_case_globals` allow;
// the linker resolves the OS symbol at load time on every macOS / iOS
// host.
extern "C" {
    #[link_name = "kSecAttrApplicationTag"]
    static K_SEC_ATTR_APPLICATION_TAG: CFStringRef;
    #[link_name = "kSecUseAuthenticationContext"]
    static K_SEC_USE_AUTHENTICATION_CONTEXT: CFStringRef;
    #[link_name = "kSecKeyAlgorithmECDSASignatureMessageX962SHA256"]
    static K_SEC_KEY_ALGORITHM_ECDSA_SIGNATURE_MESSAGE_X962_SHA256: CFStringRef;
    // `security-framework-sys` exports `kSecMatchLimit` (the attr
    // key) and `kSecMatchLimitAll` (a value), but not
    // `kSecMatchLimitOne`. Re-declare it here as an extern static so
    // the lookup query can request a single match — the OS resolves
    // the symbol from Security.framework at load time like every
    // other entry in this block.
    #[link_name = "kSecMatchLimitOne"]
    static K_SEC_MATCH_LIMIT_ONE: CFStringRef;
}

/// `errSecMissingEntitlement` — Keychain Services refuses an SE
/// key-bind because the signing identity is ad-hoc / unsigned /
/// rejected by the trust evaluator.
const ERR_SEC_MISSING_ENTITLEMENT: i32 = -34018;

/// Why the SE-SSH driver is unreachable on this host. Surfaced by
/// [`probe_availability`] and mapped to a localized reason in the
/// Dart wizard.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnavailableReason {
    /// `errSecMissingEntitlement` (-34018) — the running binary
    /// must carry a stable code-signing identity. Self-build
    /// users get the documented `codesign -s -` ad-hoc snippet in
    /// `USER_GUIDE.md`.
    CodeSignRequired,
    /// No Secure Enclave hardware (pre-T2 Intel Mac, simulator).
    NoSecureEnclave,
    /// Device passcode unset — SE keys require a passcode for the
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility
    /// class. The user must enable a passcode before generating
    /// keys.
    PasscodeNotSet,
    /// Any other failure mode — Apple API contract violation, OS
    /// version-specific edge case. The wizard surfaces the
    /// generic reason and links the user at the support guide.
    Other(String),
}

impl std::fmt::Display for UnavailableReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CodeSignRequired => write!(f, "code-signing required"),
            Self::NoSecureEnclave => write!(f, "no Secure Enclave present"),
            Self::PasscodeNotSet => write!(f, "device passcode not set"),
            Self::Other(s) => write!(f, "{s}"),
        }
    }
}

/// Result of `probe_availability`. The `Err` arm carries the
/// human-routable reason; `Ok(())` means the driver is usable on
/// this host.
pub type AvailabilityResult = Result<(), UnavailableReason>;

/// SSH access-control policy at create time. Drives the
/// `SecAccessControlCreateWithFlags` flag bitfield. Persisted
/// implicitly via the on-chip ACL — there is no DB column for it
/// because the chip refuses to mutate the ACL after creation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthPolicy {
    /// `kSecAccessControlBiometryCurrentSet` — Touch ID / Face ID
    /// every sign. Re-enrolment invalidates the key.
    BiometryCurrentSet,
    /// `kSecAccessControlUserPresence` — biometry OR device
    /// passcode. Survives re-enrolment.
    UserPresence,
}

impl AuthPolicy {
    fn extra_flags(self) -> u64 {
        match self {
            Self::BiometryCurrentSet => kSecAccessControlBiometryCurrentSet as u64,
            Self::UserPresence => kSecAccessControlUserPresence as u64,
        }
    }
}

/// Handle returned by [`create`] / [`list`]. Carries the
/// application-tag bytes the [`sign`] / [`delete`] /
/// [`public_key_ssh_wire`] entry points use to resolve the on-chip
/// key. Opaque to Dart; the FRB shim persists the tag in
/// `ssh_keys.enclave_tag` and routes back into [`sign`] on every
/// userauth signature.
#[derive(Debug, Clone)]
pub struct EnclaveKeyHandle {
    pub application_tag: Vec<u8>,
    /// User-typed label captured at create time. Echoed back on
    /// `list` so the key-manager UI can render the row label
    /// without a second DB hop.
    pub label: String,
}

/// SSH-side error envelope. The connect / sign / generate paths
/// surface this as `Error::Enclave(format!("{e}"))` at the
/// `lfs_core` boundary.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("enclave: unavailable: {0}")]
    Unavailable(UnavailableReason),

    #[error("enclave: {0}")]
    Backend(String),

    #[error("enclave: key not found")]
    KeyNotFound,

    #[error("enclave: sign refused")]
    SignRefused,
}

impl From<UnavailableReason> for Error {
    fn from(r: UnavailableReason) -> Self {
        Self::Unavailable(r)
    }
}

/// Throw-away tag the [`probe_availability`] round-trip
/// generate / delete pair runs under. A real classifier — Intel
/// Macs without a T2 don't even reach this code path because
/// `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)`
/// short-circuits the call.
const PROBE_KEY_TAG: &[u8] = b"letsflutssh.ssh.probe";

/// Probe whether SE-bound SSH keys are reachable on this host.
/// Runs a real `SecKeyCreateRandomKey` against a throw-away tag,
/// deletes it immediately. Routes `errSecMissingEntitlement` to
/// [`UnavailableReason::CodeSignRequired`] so the wizard can show
/// the documented `codesign -s -` remediation. Mirrors the
/// `hardware_tier_vault::probe_se_round_trip` shape one crate
/// over so both paths stay in sync.
pub fn probe_availability() -> AvailabilityResult {
    // `build_access_control` returns `Result<_, Error>`; map back into
    // `UnavailableReason` for the probe-side envelope. A failure here
    // is always an Apple API mishap (SecAccessControlCreateWithFlags
    // refused our flag combination) — not a hardware-class signal —
    // so it routes through `Other` rather than a dedicated variant.
    let access = build_access_control(AuthPolicy::UserPresence)
        .map_err(|e| UnavailableReason::Other(e.to_string()))?;
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let private_attrs = unsafe { build_private_attrs(PROBE_KEY_TAG, &access) };
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let create_attrs = unsafe { build_create_attrs(private_attrs) };
    let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
    // SAFETY: `SecKeyCreateRandomKey` reads the create-attributes dictionary alive on the stack
    // and writes a +1-retained `SecKeyRef` (or null + err out-param). The SE/keychain holds the
    // private bytes; the returned handle is wrapped for RAII release.
    let key = unsafe {
        SecKeyCreateRandomKey(
            create_attrs.as_concrete_TypeRef(),
            &mut err as *mut *mut core_foundation_sys::error::__CFError,
        )
    };
    let owned_err = if err.is_null() {
        None
    } else {
        // SAFETY: pointer is a non-null `CFErrorRef` returned with create-rule semantics (+1
        // retain) by the preceding Sec*/CFCopy* call; wrap transfers ownership so `Drop` balances
        // the create.
        Some(unsafe { CFError::wrap_under_create_rule(err) })
    };
    if key.is_null() {
        let code = owned_err.as_ref().map(|e| e.code() as i64).unwrap_or(0);
        return Err(if code == ERR_SEC_MISSING_ENTITLEMENT as i64 {
            UnavailableReason::CodeSignRequired
        } else {
            UnavailableReason::Other(match owned_err {
                Some(e) => format!("SecKeyCreateRandomKey: {e:?}"),
                None => "SecKeyCreateRandomKey: null".to_string(),
            })
        });
    }
    // Wrap so Drop releases on the way out.
    let _owned = OwnedSecKey(key);
    // Best-effort cleanup. The OS GCs the key on next launch even
    // if delete fails.
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let delete_query = unsafe { build_delete_query(PROBE_KEY_TAG) };
    // SAFETY: `SecItemDelete` reads the query dictionary alive on the stack; no out-params.
    unsafe {
        SecItemDelete(delete_query.as_concrete_TypeRef());
    }
    Ok(())
}

/// Mint a fresh ECDSA P-256 key on the Secure Enclave. Returns the
/// handle the caller persists in `ssh_keys.enclave_tag` (plus
/// `label` for the row's user-typed display name).
///
/// The OS fires its biometric / passcode prompt on this call when
/// the chosen [`AuthPolicy`] requires it — we don't pre-prompt
/// Dart-side. `label` is the user-typed name the wizard captured;
/// it does NOT become the `CFString` `kSecAttrLabel` because that
/// field surfaces in `keychain.app` and we want the SSH-key
/// metadata to live in our own DB.
pub fn create(label: &str, policy: AuthPolicy) -> Result<EnclaveKeyHandle, Error> {
    let tag = mint_application_tag();
    let access = build_access_control(policy)?;
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let private_attrs = unsafe { build_private_attrs(&tag, &access) };
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let create_attrs = unsafe { build_create_attrs(private_attrs) };
    let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
    // SAFETY: `SecKeyCreateRandomKey` reads the create-attributes dictionary alive on the stack
    // and writes a +1-retained `SecKeyRef` (or null + err out-param). The SE/keychain holds the
    // private bytes; the returned handle is wrapped for RAII release.
    let key = unsafe {
        SecKeyCreateRandomKey(
            create_attrs.as_concrete_TypeRef(),
            &mut err as *mut *mut core_foundation_sys::error::__CFError,
        )
    };
    let owned_err = if err.is_null() {
        None
    } else {
        // SAFETY: pointer is a non-null `CFErrorRef` returned with create-rule semantics (+1
        // retain) by the preceding Sec*/CFCopy* call; wrap transfers ownership so `Drop` balances
        // the create.
        Some(unsafe { CFError::wrap_under_create_rule(err) })
    };
    if key.is_null() {
        let code = owned_err.as_ref().map(|e| e.code() as i64).unwrap_or(0);
        if code == ERR_SEC_MISSING_ENTITLEMENT as i64 {
            return Err(Error::Unavailable(UnavailableReason::CodeSignRequired));
        }
        return Err(Error::Backend(match owned_err {
            Some(e) => format!("SecKeyCreateRandomKey: {e:?}"),
            None => "SecKeyCreateRandomKey: null".to_string(),
        }));
    }
    let _owned = OwnedSecKey(key);
    Ok(EnclaveKeyHandle {
        application_tag: tag,
        label: label.to_string(),
    })
}

/// Sign `data` with the on-chip ECDSA P-256 key resolved by
/// `handle.application_tag`. Returns the SSH wire-format signature
/// blob — two `mpint`s wrapped via
/// [`crate::pkcs11::sign::sign_with_pkcs11`]'s sibling helper in
/// `lfs_core::ssh::wire` (the Signer impl composes the outer
/// `string(algorithm) || string(sig_blob)` userauth wrapper).
///
/// `context` is the cached `LAContext` from the FRB worker — passed
/// via `kSecUseAuthenticationContext` so the OS skips the biometric
/// prompt while the context's `evaluatedPolicyDomainState` blob is
/// still valid. `None` makes the OS fire a fresh prompt on every
/// sign.
///
/// The OS performs SHA-256 internally
/// (`kSecKeyAlgorithmECDSASignatureMessageX962SHA256`) — we pass
/// the raw userauth buffer, not a pre-hash. The returned bytes are
/// DER `SEQUENCE { INTEGER r, INTEGER s }`; the SSH wrapper happens
/// in [`lfs_core::ssh::wire::ecdsa_der_to_ssh_mpint`].
pub fn sign(
    handle: &EnclaveKeyHandle,
    data: &[u8],
    context: Option<&Retained<LAContext>>,
) -> Result<Vec<u8>, Error> {
    let private_key =
        load_private_key(&handle.application_tag, context)?.ok_or(Error::KeyNotFound)?;
    // SAFETY: identifier is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; reading the static is a plain pointer copy.
    let algorithm = unsafe { K_SEC_KEY_ALGORITHM_ECDSA_SIGNATURE_MESSAGE_X962_SHA256 };
    let data_cf = CFData::from_buffer(data);
    let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
    // SAFETY: `SecKeyCreateSignature` reads the key + algo + data (all alive on the stack) and
    // returns a +1-retained `CFDataRef` (or null + err out-param); may surface the biometric
    // prompt.
    let sig_ref = unsafe {
        SecKeyCreateSignature(
            private_key.0,
            algorithm,
            data_cf.as_concrete_TypeRef(),
            &mut err as *mut *mut core_foundation_sys::error::__CFError,
        )
    };
    let owned_err = if err.is_null() {
        None
    } else {
        // SAFETY: pointer is a non-null `CFErrorRef` returned with create-rule semantics (+1
        // retain) by the preceding Sec*/CFCopy* call; wrap transfers ownership so `Drop` balances
        // the create.
        Some(unsafe { CFError::wrap_under_create_rule(err) })
    };
    if sig_ref.is_null() {
        return Err(match owned_err {
            Some(e) => Error::Backend(format!("SecKeyCreateSignature: {e:?}")),
            None => Error::SignRefused,
        });
    }
    // SAFETY: pointer is a non-null `CFDataRef` returned with create-rule semantics (+1 retain) by
    // the preceding Sec*/CFCopy* call; wrap transfers ownership so `Drop` balances the create.
    let sig_data = unsafe { CFData::wrap_under_create_rule(sig_ref) };
    Ok(sig_data.bytes().to_vec())
}

/// Pull the public half of the SE-bound key and return it as the
/// SSH wire-format `ecdsa-sha2-nistp256` body the SSH connect path
/// matches against. The SE returns the 65-byte uncompressed
/// `0x04 || X(32) || Y(32)` shape via
/// `SecKeyCopyExternalRepresentation`; we hand it to
/// [`lfs_core::ssh::wire::encode_public_ecdsa_p256`] for the
/// `string(algo) || string(curve) || string(point)` wrap.
///
/// Caller composes the `authorized_keys` line; this only returns
/// the wire body.
pub fn public_key_ssh_wire(handle: &EnclaveKeyHandle) -> Result<Vec<u8>, Error> {
    let private_key = load_private_key(&handle.application_tag, None)?.ok_or(Error::KeyNotFound)?;
    // SAFETY: `SecKeyCopyPublicKey` reads the private `SecKeyRef` we own and returns a fresh
    // +1-retained `SecKeyRef` (or null on failure) which is wrapped below.
    let public_ref = unsafe { SecKeyCopyPublicKey(private_key.0) };
    if public_ref.is_null() {
        return Err(Error::Backend("SecKeyCopyPublicKey returned null".into()));
    }
    let public_owned = OwnedSecKey(public_ref);
    let mut err: *mut core_foundation_sys::error::__CFError = ptr::null_mut();
    // SAFETY: `SecKeyCopyExternalRepresentation` reads the key reference we own and returns a
    // +1-retained `CFDataRef` (or null + err out-param).
    let bytes_ref = unsafe {
        SecKeyCopyExternalRepresentation(
            public_owned.0,
            &mut err as *mut *mut core_foundation_sys::error::__CFError,
        )
    };
    let owned_err = if err.is_null() {
        None
    } else {
        // SAFETY: pointer is a non-null `CFErrorRef` returned with create-rule semantics (+1
        // retain) by the preceding Sec*/CFCopy* call; wrap transfers ownership so `Drop` balances
        // the create.
        Some(unsafe { CFError::wrap_under_create_rule(err) })
    };
    if bytes_ref.is_null() {
        return Err(match owned_err {
            Some(e) => Error::Backend(format!("SecKeyCopyExternalRepresentation: {e:?}")),
            None => Error::Backend("SecKeyCopyExternalRepresentation: null".into()),
        });
    }
    // SAFETY: pointer is a non-null `CFDataRef` returned with create-rule semantics (+1 retain) by
    // the preceding Sec*/CFCopy* call; wrap transfers ownership so `Drop` balances the create.
    let cf_bytes = unsafe { CFData::wrap_under_create_rule(bytes_ref) };
    Ok(cf_bytes.bytes().to_vec())
}

/// Enumerate every SE-bound SSH key whose application-tag prefix
/// matches our `letsflutssh.ssh.` namespace. Used by the
/// import-recovery path that surfaces "Already on this device:
/// re-link or wipe?" when the DB lost track of a tag the chip
/// still holds.
///
/// Returns handles with empty `label` — the Keychain has no
/// label column we control (we don't set `kSecAttrLabel`); the
/// caller should join against `ssh_keys.enclave_tag` to recover
/// the user-typed name.
pub fn list() -> Result<Vec<EnclaveKeyHandle>, Error> {
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let query = unsafe { build_list_query() };
    let mut items: *const c_void = ptr::null();
    // SAFETY: `SecItemCopyMatching` reads the query dictionary alive on the stack and writes a
    // +1-retained CF reference into the out-pointer; the kernel does not retain any pointer past
    // return.
    let status = unsafe {
        SecItemCopyMatching(
            query.as_concrete_TypeRef(),
            &mut items as *mut *const c_void,
        )
    };
    if status == errSecItemNotFound {
        return Ok(Vec::new());
    }
    if status != 0 {
        return Err(Error::Backend(format!(
            "SecItemCopyMatching: OSStatus {status}"
        )));
    }
    if items.is_null() {
        return Ok(Vec::new());
    }
    // The return shape is `CFArray<CFDictionary<CFString, _>>` —
    // one dict per matched key, each carrying the
    // `kSecAttrApplicationTag` CFData entry we pull back. We
    // re-validate the prefix on the Rust side because Keychain
    // returns every SE-class private key with a tag attribute,
    // and our partial-match filter is best-effort.
    // SAFETY: pointer is a non-null `CFArrayRef` returned with create-rule semantics (+1 retain)
    // by `SecItemCopyMatching`; wrap transfers ownership so `Drop` balances the create.
    let array = unsafe {
        core_foundation::array::CFArray::<*const c_void>::wrap_under_create_rule(items as *const _)
    };
    let mut handles = Vec::with_capacity(array.len() as usize);
    let prefix = b"letsflutssh.ssh.";
    for i in 0..array.len() {
        let Some(dict_ptr) = array.get(i) else {
            continue;
        };
        // Each entry is a CFDictionaryRef. Reach into it for the
        // application-tag CFData.
        let dict =
            // SAFETY: argument is a static CFType reference exported by Security.framework with
            // program-lifetime refcount; the get-rule wrap takes no extra retain.
            unsafe { CFDictionary::<CFString, CFType>::wrap_under_get_rule(*dict_ptr as *const _) };
        // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
        // program-lifetime refcount; the get-rule wrap takes no extra retain.
        let tag_key = unsafe { CFString::wrap_under_get_rule(K_SEC_ATTR_APPLICATION_TAG) };
        let Some(value) = dict.find(&tag_key) else {
            continue;
        };
        // value is &CFType; downcast to CFData.
        let data: CFData = match value.downcast::<CFData>() {
            Some(d) => d,
            None => continue,
        };
        let bytes = data.bytes().to_vec();
        if !bytes.starts_with(prefix) {
            continue;
        }
        handles.push(EnclaveKeyHandle {
            application_tag: bytes,
            label: String::new(),
        });
    }
    Ok(handles)
}

/// Drop the on-chip key matched by `handle.application_tag`.
/// `SecItemDelete` returns success on a missing key (idempotent
/// on the OS side); we treat that as `Ok(())` so the DAO's
/// soft-delete + sync-replay path stays clean.
pub fn delete(handle: &EnclaveKeyHandle) -> Result<(), Error> {
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let query = unsafe { build_delete_query(&handle.application_tag) };
    // SAFETY: `SecItemDelete` reads the query dictionary alive on the stack; no out-params, return
    // code intentionally ignored (best-effort cleanup).
    let status = unsafe { SecItemDelete(query.as_concrete_TypeRef()) };
    if status == errSecItemNotFound || status == 0 {
        Ok(())
    } else {
        Err(Error::Backend(format!("SecItemDelete: OSStatus {status}")))
    }
}

/// Mint a fresh application tag in our namespace. Format:
/// `letsflutssh.ssh.<lowercase-hex-uuid>` — 32 hex chars after
/// the prefix, giving 128 bits of entropy. The Keychain treats
/// the tag as opaque so any byte string would work; we use a UTF-8
/// shape so the on-disk DB rows stay grep-friendly during audits.
fn mint_application_tag() -> Vec<u8> {
    use rand::Rng;
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("letsflutssh.ssh.{hex}").into_bytes()
}

/// Owned wrapper around a `SecKeyRef` so the `Drop` impl releases
/// the CF reference exactly once. Mirrors the wrapper in
/// `hardware_tier_vault::apple` — same shape, separate file so the
/// SSH path stays a self-contained read.
struct OwnedSecKey(SecKeyRef);

impl Drop for OwnedSecKey {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: pointer is a non-null +1-retained CF reference we own via the surrounding
            // wrapper; releasing once balances the create-rule retain.
            unsafe { core_foundation_sys::base::CFRelease(self.0 as *const c_void) };
        }
    }
}

/// Build a `SecAccessControl` with the requested ACL flags. The
/// accessibility class always pins to
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — SSH keys are
/// per-device and never sync.
fn build_access_control(policy: AuthPolicy) -> Result<SecAccessControl, Error> {
    let flags = (kSecAccessControlPrivateKeyUsage as u64) | policy.extra_flags();
    SecAccessControl::create_with_protection(
        Some(ProtectionMode::AccessibleWhenUnlockedThisDeviceOnly),
        flags as core_foundation_sys::base::CFOptionFlags,
    )
    .map_err(|e| Error::Backend(format!("SecAccessControl: {e}")))
}

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
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let is_perm_key = unsafe { CFString::wrap_under_get_rule(kSecAttrIsPermanent) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let app_tag_key = unsafe { CFString::wrap_under_get_rule(K_SEC_ATTR_APPLICATION_TAG) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let ac_key = unsafe { CFString::wrap_under_get_rule(kSecAttrAccessControl) };
    let true_val = CFNumber::from(1i32);
    let tag_data = CFData::from_buffer(tag);
    CFDictionary::from_CFType_pairs(&[
        (is_perm_key, true_val.as_CFType()),
        (app_tag_key, tag_data.as_CFType()),
        (ac_key, access.as_CFType()),
    ])
}

/// # Safety
///
/// Same get-rule contract as `build_private_attrs`. `kSec*`
/// constants live for program lifetime; the returned dictionary
/// borrows them via `as_CFType` clones held in the pair list.
unsafe fn build_create_attrs(
    private_attrs: CFDictionary<CFString, CFType>,
) -> CFDictionary<CFString, CFType> {
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_type_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyType) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_type_val = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyTypeECSECPrimeRandom) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let size_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeySizeInBits) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let token_key = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenID) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let token_val = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenIDSecureEnclave) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let priv_key = unsafe { CFString::wrap_under_get_rule(kSecPrivateKeyAttrs) };
    CFDictionary::from_CFType_pairs(&[
        (key_type_key, key_type_val.as_CFType()),
        (size_key, CFNumber::from(256i32).as_CFType()),
        (token_key, token_val.as_CFType()),
        (priv_key, private_attrs.as_CFType()),
    ])
}

/// Build a `SecItemCopyMatching` query that resolves a stored SE
/// private key by application tag. Optionally attaches a cached
/// `LAContext` so the OS skips the biometric prompt on hot-cache
/// hits.
///
/// # Safety
///
/// Same get-rule contract as `build_private_attrs`. The
/// returned dictionary is single-use — pass it directly into
/// `SecItemCopyMatching` while the wrapped tag bytes are still
/// alive.
unsafe fn build_lookup_query(
    tag: &[u8],
    context: Option<&Retained<LAContext>>,
) -> CFDictionary<CFString, CFType> {
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let class_val = unsafe { CFString::wrap_under_get_rule(kSecClassKey) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_type_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyType) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_type_val = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyTypeECSECPrimeRandom) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let app_tag_key = unsafe { CFString::wrap_under_get_rule(K_SEC_ATTR_APPLICATION_TAG) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let return_ref_key = unsafe { CFString::wrap_under_get_rule(kSecReturnRef) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let match_limit_key = unsafe { CFString::wrap_under_get_rule(kSecMatchLimit) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let match_limit_val = unsafe { CFString::wrap_under_get_rule(K_SEC_MATCH_LIMIT_ONE) };
    let true_val = CFNumber::from(1i32);
    let mut pairs: Vec<(CFString, CFType)> = vec![
        (class_key, class_val.as_CFType()),
        (key_type_key, key_type_val.as_CFType()),
        (app_tag_key, CFData::from_buffer(tag).as_CFType()),
        (return_ref_key, true_val.as_CFType()),
        (match_limit_key, match_limit_val.as_CFType()),
    ];
    if let Some(ctx) = context {
        // `LAContext` is an `NSObject` subclass; wrap via `as *const _`
        // and let CF treat the Obj-C pointer as a CFType for the
        // dictionary slot. `kSecUseAuthenticationContext` is documented
        // to accept LAContext instances verbatim.
        // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
        // program-lifetime refcount; the get-rule wrap takes no extra retain.
        let auth_ctx_key =
            unsafe { CFString::wrap_under_get_rule(K_SEC_USE_AUTHENTICATION_CONTEXT) };
        let ctx_ptr: *const c_void = Retained::as_ptr(ctx) as *const c_void;
        // SAFETY: LAContext is a CFRetain-compatible Obj-C class;
        // wrapping under get-rule retains the existing strong
        // reference held by the caller's `Retained<LAContext>`.
        let ctx_cf = unsafe { CFType::wrap_under_get_rule(ctx_ptr) };
        pairs.push((auth_ctx_key, ctx_cf));
    }
    CFDictionary::from_CFType_pairs(&pairs)
}

/// Build the list-all query — every SE private key on this device,
/// returning the application-tag attribute on each. We post-filter
/// by prefix on the Rust side.
///
/// # Safety
///
/// Same get-rule contract as `build_lookup_query`.
unsafe fn build_list_query() -> CFDictionary<CFString, CFType> {
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let class_val = unsafe { CFString::wrap_under_get_rule(kSecClassKey) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_class_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyClass) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_class_val = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyClassPrivate) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let token_key = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenID) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let token_val = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenIDSecureEnclave) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let return_attrs_key = unsafe { CFString::wrap_under_get_rule(kSecReturnAttributes) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let match_limit_key = unsafe { CFString::wrap_under_get_rule(kSecMatchLimit) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let match_limit_val = unsafe { CFString::wrap_under_get_rule(kSecMatchLimitAll) };
    let true_val = CFNumber::from(1i32);
    CFDictionary::from_CFType_pairs(&[
        (class_key, class_val.as_CFType()),
        (key_class_key, key_class_val.as_CFType()),
        (token_key, token_val.as_CFType()),
        (return_attrs_key, true_val.as_CFType()),
        (match_limit_key, match_limit_val.as_CFType()),
    ])
}

/// Build the delete query — by-tag delete is the canonical way to
/// drop an SE key without first holding a `SecKeyRef`.
///
/// # Safety
///
/// Same get-rule contract as the sibling builders above; the
/// dictionary must outlive the `SecItemDelete` FFI call.
unsafe fn build_delete_query(tag: &[u8]) -> CFDictionary<CFString, CFType> {
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let class_key = unsafe { CFString::wrap_under_get_rule(kSecClass) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let class_val = unsafe { CFString::wrap_under_get_rule(kSecClassKey) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_class_key = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyClass) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let key_class_val = unsafe { CFString::wrap_under_get_rule(kSecAttrKeyClassPrivate) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let token_key = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenID) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let token_val = unsafe { CFString::wrap_under_get_rule(kSecAttrTokenIDSecureEnclave) };
    // SAFETY: argument is a static `CFStringRef` exported by Security.framework with
    // program-lifetime refcount; the get-rule wrap takes no extra retain.
    let app_tag_key = unsafe { CFString::wrap_under_get_rule(K_SEC_ATTR_APPLICATION_TAG) };
    CFDictionary::from_CFType_pairs(&[
        (class_key, class_val.as_CFType()),
        (key_class_key, key_class_val.as_CFType()),
        (token_key, token_val.as_CFType()),
        (app_tag_key, CFData::from_buffer(tag).as_CFType()),
    ])
}

/// Lookup a stored SE private key by tag. Returns `Ok(None)` when
/// the key is absent (`errSecItemNotFound`); other status codes
/// propagate as backend errors.
fn load_private_key(
    tag: &[u8],
    context: Option<&Retained<LAContext>>,
) -> Result<Option<OwnedSecKey>, Error> {
    // SAFETY: callee is `unsafe fn` because it wraps Security.framework static `CFStringRef`
    // constants; the resulting dictionary is owned for the duration of the call below.
    let query = unsafe { build_lookup_query(tag, context) };
    let mut item: *const c_void = ptr::null();
    // SAFETY: `SecItemCopyMatching` reads the query dictionary alive on the stack and writes a
    // +1-retained CF reference into the out-pointer; the kernel does not retain any pointer past
    // return.
    let status = unsafe {
        SecItemCopyMatching(query.as_concrete_TypeRef(), &mut item as *mut *const c_void)
    };
    let owned = if item.is_null() {
        None
    } else {
        Some(OwnedSecKey(item as SecKeyRef))
    };
    if status == errSecItemNotFound {
        return Ok(None);
    }
    if status != 0 {
        return Err(Error::Backend(format!(
            "SecItemCopyMatching: OSStatus {status}"
        )));
    }
    Ok(owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn application_tag_mint_carries_prefix() {
        // Mint a handful and pin both the prefix shape + the
        // randomness of the suffix. Two mints in a row must not
        // collide.
        let a = mint_application_tag();
        let b = mint_application_tag();
        assert!(a.starts_with(b"letsflutssh.ssh."));
        assert_eq!(a.len(), b"letsflutssh.ssh.".len() + 32);
        assert_ne!(a, b);
    }

    #[test]
    fn unavailable_reason_renders_human_text() {
        assert!(UnavailableReason::CodeSignRequired
            .to_string()
            .contains("code-signing"));
        assert!(UnavailableReason::NoSecureEnclave
            .to_string()
            .contains("Secure Enclave"));
        assert!(UnavailableReason::PasscodeNotSet
            .to_string()
            .contains("passcode"));
        assert_eq!(
            UnavailableReason::Other("custom".into()).to_string(),
            "custom"
        );
    }

    #[test]
    fn auth_policy_extra_flags_set_per_variant() {
        let bio = AuthPolicy::BiometryCurrentSet.extra_flags();
        let pres = AuthPolicy::UserPresence.extra_flags();
        assert_ne!(bio, pres);
        assert_eq!(bio, kSecAccessControlBiometryCurrentSet as u64);
        assert_eq!(pres, kSecAccessControlUserPresence as u64);
    }

    /// Integration tests are gated behind `#[ignore]` so CI without
    /// an Apple machine can still compile-check. Run locally:
    /// `cargo test -p lfs_os_security --target aarch64-apple-darwin
    /// apple_se_ssh -- --ignored --test-threads=1`.
    #[test]
    #[ignore]
    fn probe_round_trip_completes() {
        let _ = probe_availability();
    }
}
