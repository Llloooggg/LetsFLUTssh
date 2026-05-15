//! OS-managed FIDO2 broker — system security-key dialog that
//! covers USB / NFC / BLE / platform authenticator transparently.
//!
//! Per-OS coverage:
//!
//! * **Windows** — `webauthn.dll`'s `WebAuthNAuthenticatorGetAssertion`
//!   (Win 10 1903+ in-box). USB / NFC / BLE + the platform Hello
//!   authenticator. No admin permission. UV requirement controlled by
//!   `WEBAUTHN_USER_VERIFICATION_REQUIREMENT_*`; OS handles PIN +
//!   touch flow inside the system dialog.
//!
//! * **macOS / iOS** — `ASAuthorizationSecurityKeyPublicKeyCredentialProvider`
//!   via a Swift glue file (`SecurityKeyBroker.swift`) loaded
//!   dynamically through `libloading`. Requires the
//!   `com.apple.developer.web-browser.public-key-credential`
//!   entitlement and a release built under the Apple Developer
//!   Program; the runtime probe surfaces the path as unavailable
//!   until both land. macOS 12+ / iOS 15.5+ for the API.
//!
//! * **Android** — JNI into `androidx.credentials.CredentialManager`
//!   (`GetPublicKeyCredentialOption`) via the Kotlin `Fido2Broker`
//!   shim. Covers USB-host / NFC / BLE + platform StrongBox passkey
//!   without the legacy `Fido2ApiClient` quirks. Verification depends
//!   on the host device (no compile-time runner reaches a real
//!   Credential Manager dialog).
//!
//! * **Linux** — no broker. Linux's USB stack is fronted by the
//!   distro's udev rules + `libfido2`; the direct HID path is the
//!   only viable surface. [`is_available`] returns `false` so the
//!   dispatcher falls through to the HID transport.
//!
//! ## Why the broker is preferred when present
//!
//! The OS dialog handles transport, vendor quirks, and the PIN /
//! biometric prompt in a single system-managed surface the user
//! already trusts. No admin permission grant (the direct HID path
//! needs `udev` rules on Linux and HID class access on Windows),
//! no per-vendor driver vendoring, no Apple Developer entitlement
//! gymnastic for non-broker users.
//!
//! ## hmac-secret note
//!
//! Brokers subset the CTAP2 surface — WebAuthn.dll exposes
//! `hmac-secret` only on `MakeCredential`, ASAuthorization and
//! Credential Manager never expose it. PROTOCOL.u2f's "No extensions
//! are yet defined for SSH use" pins this as irrelevant for SSH
//! `sk-*` userauth; document so a future hmac-secret-dependent
//! feature doesn't silently regress on broker paths.

/// CTAP2 assertion result the broker returns. Same wire shape as
/// `lfs_core::fido2::SkAssertion` (which we mirror without
/// depending on it — audit perimeter requires `lfs_os_security`
/// to stay free of `lfs_core` deps).
#[derive(Debug, Clone)]
pub struct BrokerAssertion {
    /// Raw CTAP signature bytes. Ed25519 is 64 raw bytes; ECDSA
    /// P-256 is DER `SEQUENCE { r, s }`. The caller (in `lfs_core`)
    /// wraps via the shared `ssh::wire` helpers.
    pub signature: Vec<u8>,
    /// WebAuthn `authenticatorData` blob: 32-byte rpIdHash || flags
    /// byte || u32 BE signCount || any extension bytes.
    pub authenticator_data: Vec<u8>,
    /// Optional user handle the credential was registered against.
    /// `None` when the device omitted it (SSH does not consume the
    /// field; surfaced for completeness).
    pub user_handle: Option<Vec<u8>>,
}

/// Reasons the broker cannot be used right now. Drives the
/// dispatcher in `lfs_core::fido2` and the UI's per-OS label.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BrokerUnavailable {
    /// Host OS has no broker primitive at all (Linux today).
    PlatformUnsupported,
    /// Broker API version probe rejected the host (`webauthn.dll`
    /// missing or < v1, macOS / iOS pre-12 / pre-15.5, Android pre
    /// API 28).
    TooOld,
    /// Apple-specific: the running bundle is not signed with the
    /// `com.apple.developer.web-browser.public-key-credential`
    /// entitlement, so AS routes refuse to display the dialog.
    /// Direct HID is the available fallback on macOS for self-
    /// signed builds; on iOS the path stays disabled.
    AppleEntitlementMissing,
    /// JVM / Activity capture has not run yet (Android only — the
    /// bootstrap JNI call from `MainActivity.onCreate` is the gate).
    NotBootstrapped,
    /// Catch-all probe error. Carries the raw message for the
    /// telemetry / log line; UI maps to the locale-aware "broker
    /// unavailable" toast.
    Probe(String),
}

/// `Ok(())` = broker reachable and ready; `Err(reason)` = broker
/// path stays disabled, caller falls through to the direct HID
/// transport (or surfaces "no hardware key" on iOS / Android where
/// no fallback exists).
pub type BrokerAvailability = Result<(), BrokerUnavailable>;

/// Reasons the broker may report when an assertion fails. Routed
/// to typed UI toasts; sibling of the direct-HID error mapping in
/// `lfs_core::fido2::client::map_upstream_err`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BrokerError {
    Cancelled,
    Timeout,
    WrongPin,
    NoMatchingCredential,
    /// Broker is reachable but the dialog reported a transport
    /// failure (USB unplugged, NFC tag pulled, BLE pairing lost).
    Transport,
    /// Catch-all — carries the OS-side message for log + telemetry.
    Other(String),
}

impl core::fmt::Display for BrokerError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Cancelled => f.write_str("user cancelled the security-key dialog"),
            Self::Timeout => f.write_str("security-key dialog timed out"),
            Self::WrongPin => f.write_str("wrong pin"),
            Self::NoMatchingCredential => f.write_str("no matching credential on the device"),
            Self::Transport => f.write_str("security key disconnected before signing"),
            Self::Other(s) => f.write_str(s),
        }
    }
}

/// Probe whether the OS broker is ready. Pure-Rust on every
/// non-broker target; behind a cfg-gate for the real per-OS probe.
pub fn is_available() -> BrokerAvailability {
    platform_impl::is_available()
}

/// Request a CTAP2 assertion through the OS broker.
///
/// `credential_id` is the opaque blob captured at `sk-*` key import.
/// `rp_id` is the SSH `application` string with the `ssh:` URI scheme
/// stripped if present (WebAuthn / ASAuthorization / Credential
/// Manager all key on a bare host-name-shaped RP id). `challenge` is
/// the SHA-256 pre-hash of the SSH userauth signature input the
/// caller has already computed. `require_user_verification` matches
/// the captured-at-import `has_user_verification` flag — when `true`
/// the broker is asked to gate on PIN / biometric; when `false` a
/// touch-only credential signs without UV.
pub async fn get_assertion(
    credential_id: Vec<u8>,
    rp_id: String,
    challenge: Vec<u8>,
    require_user_verification: bool,
) -> Result<BrokerAssertion, BrokerError> {
    platform_impl::get_assertion(credential_id, rp_id, challenge, require_user_verification).await
}

/// Strip the `ssh:` URI scheme from an SSH `application` field so
/// the broker can match the credential by bare RP id. OpenSSH
/// stores `ssh:` (or `ssh:<host>`) in the public-key body; the
/// system broker treats it as a percent-encoded relying-party
/// identifier the host did NOT register against, so the lookup
/// fails. Strip leaving the rest verbatim.
///
/// Returns `application` unchanged when no prefix is present. Empty
/// input collapses to empty (broker call will reject).
#[must_use]
pub fn rp_id_from_application(application: &str) -> &str {
    application.strip_prefix("ssh:").unwrap_or(application)
}

// ── Per-OS impl ─────────────────────────────────────────────────────

#[cfg(target_os = "windows")]
mod platform_impl {
    use super::{BrokerAssertion, BrokerAvailability, BrokerError, BrokerUnavailable};
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::HWND;
    use windows::Win32::Networking::WindowsWebServices::{
        WebAuthNAuthenticatorGetAssertion, WebAuthNFreeAssertion, WebAuthNGetApiVersionNumber,
        WEBAUTHN_API_VERSION_1, WEBAUTHN_AUTHENTICATOR_ATTACHMENT_CROSS_PLATFORM,
        WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS,
        WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS_VERSION_1, WEBAUTHN_CLIENT_DATA,
        WEBAUTHN_CLIENT_DATA_CURRENT_VERSION, WEBAUTHN_CREDENTIAL, WEBAUTHN_CREDENTIALS,
        WEBAUTHN_CREDENTIAL_CURRENT_VERSION, WEBAUTHN_CREDENTIAL_TYPE_PUBLIC_KEY,
        WEBAUTHN_HASH_ALGORITHM_SHA_256, WEBAUTHN_USER_VERIFICATION_REQUIREMENT_DISCOURAGED,
        WEBAUTHN_USER_VERIFICATION_REQUIREMENT_REQUIRED,
    };

    pub(super) fn is_available() -> BrokerAvailability {
        // SAFETY: WebAuthNGetApiVersionNumber is a parameterless
        // probe; returns 0 when the import resolves but the OS has
        // no implementation, non-zero version on supported hosts.
        let api_version = unsafe { WebAuthNGetApiVersionNumber() };
        if api_version >= WEBAUTHN_API_VERSION_1 {
            Ok(())
        } else {
            Err(BrokerUnavailable::TooOld)
        }
    }

    pub(super) async fn get_assertion(
        credential_id: Vec<u8>,
        rp_id: String,
        challenge: Vec<u8>,
        require_user_verification: bool,
    ) -> Result<BrokerAssertion, BrokerError> {
        // The dialog must own a window handle so the OS can keep the
        // prompt above the app's main window. The broker tolerates a
        // null HWND (uses the foreground window) but the docs warn
        // that a hosting HWND is preferable; for the Flutter app
        // path the active window is reachable via `GetForegroundWindow`
        // which we treat as good-enough.
        let rp_id_owned = rp_id.clone();
        let cred_owned = credential_id.clone();
        let chal_owned = challenge.clone();
        let uv = require_user_verification;
        tokio::task::spawn_blocking(move || {
            blocking_get_assertion(&rp_id_owned, &cred_owned, &chal_owned, uv)
        })
        .await
        .unwrap_or_else(|e| Err(BrokerError::Other(format!("spawn_blocking: {e}"))))
    }

    fn blocking_get_assertion(
        rp_id: &str,
        credential_id: &[u8],
        challenge: &[u8],
        require_uv: bool,
    ) -> Result<BrokerAssertion, BrokerError> {
        // Build a UTF-16 null-terminated buffer for the RP id; the
        // PCWSTR points into this owned buffer for the lifetime of
        // the call.
        let rp_id_utf16: Vec<u16> = rp_id.encode_utf16().chain([0]).collect();

        // Mutable copies the FFI structs hold raw pointers into;
        // their owners must outlive the call. `unsafe` blocks are
        // bounded — every pointer is freshly aimed at a local Vec.
        let mut challenge_buf = challenge.to_vec();
        let client_data = WEBAUTHN_CLIENT_DATA {
            dwVersion: WEBAUTHN_CLIENT_DATA_CURRENT_VERSION,
            cbClientDataJSON: challenge_buf.len() as u32,
            pbClientDataJSON: challenge_buf.as_mut_ptr(),
            pwszHashAlgId: WEBAUTHN_HASH_ALGORITHM_SHA_256,
        };

        let mut cred_id_buf = credential_id.to_vec();
        let mut credential = WEBAUTHN_CREDENTIAL {
            dwVersion: WEBAUTHN_CREDENTIAL_CURRENT_VERSION,
            cbId: cred_id_buf.len() as u32,
            pbId: cred_id_buf.as_mut_ptr(),
            pwszCredentialType: WEBAUTHN_CREDENTIAL_TYPE_PUBLIC_KEY,
        };

        let cred_list = WEBAUTHN_CREDENTIALS {
            cCredentials: 1,
            pCredentials: &mut credential as *mut _,
        };

        let options = WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS {
            dwVersion: WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS_VERSION_1,
            dwTimeoutMilliseconds: 60_000,
            CredentialList: cred_list,
            dwAuthenticatorAttachment: WEBAUTHN_AUTHENTICATOR_ATTACHMENT_CROSS_PLATFORM,
            dwUserVerificationRequirement: if require_uv {
                WEBAUTHN_USER_VERIFICATION_REQUIREMENT_REQUIRED
            } else {
                WEBAUTHN_USER_VERIFICATION_REQUIREMENT_DISCOURAGED
            },
            ..Default::default()
        };

        // SAFETY: `foreground_window` is a thin wrapper over `GetForegroundWindow`, a no-argument
        // Win32 query that returns the current foreground HWND (or null).
        let hwnd = unsafe { foreground_window() };

        // SAFETY: every pointer field above lives in a Vec we own
        // on the stack for the duration of the call. The OS reads
        // them inside the call and never retains them; the returned
        // `*mut WEBAUTHN_ASSERTION` is freed via `WebAuthNFreeAssertion`
        // below in the same scope.
        let result = unsafe {
            WebAuthNAuthenticatorGetAssertion(
                hwnd,
                PCWSTR::from_raw(rp_id_utf16.as_ptr()),
                &client_data as *const _,
                Some(&options as *const _),
            )
        };

        match result {
            // SAFETY: `slice::from_raw_parts` constructs a slice from a pointer + length; the
            // pointer is owned by the calling FFI and valid for the slice length for the borrow's
            // duration.
            Ok(assertion_ptr) => unsafe {
                let assertion = match assertion_ptr.as_ref() {
                    Some(a) => a,
                    None => return Err(BrokerError::Other("null assertion pointer".into())),
                };
                let signature = std::slice::from_raw_parts(
                    assertion.pbSignature,
                    assertion.cbSignature as usize,
                )
                .to_vec();
                let authenticator_data = std::slice::from_raw_parts(
                    assertion.pbAuthenticatorData,
                    assertion.cbAuthenticatorData as usize,
                )
                .to_vec();
                let user_handle = if assertion.cbUserId > 0 && !assertion.pbUserId.is_null() {
                    Some(
                        std::slice::from_raw_parts(assertion.pbUserId, assertion.cbUserId as usize)
                            .to_vec(),
                    )
                } else {
                    None
                };
                WebAuthNFreeAssertion(assertion_ptr);
                Ok(BrokerAssertion {
                    signature,
                    authenticator_data,
                    user_handle,
                })
            },
            Err(e) => Err(map_hresult(e)),
        }
    }

    /// Map a WebAuthn HRESULT to the typed broker error. Windows
    /// surfaces HRESULTs from the `NTE_*` / `WEBAUTHN_*` ranges;
    /// the official error names live in `winerror.h`.
    fn map_hresult(err: windows::core::Error) -> BrokerError {
        // HRESULTs we route to typed reasons. Values are stable
        // across Windows revisions (documented in winerror.h).
        const NTE_USER_CANCELLED: i32 = 0x8009_0036u32 as i32;
        const NTE_NO_MATCH: i32 = 0x8009_002Au32 as i32;
        const NTE_BAD_KEYSET: i32 = 0x8009_0016u32 as i32;
        const NTE_DEVICE_NOT_READY: i32 = 0x8007_0015u32 as i32;
        let code = err.code().0;
        match code {
            NTE_USER_CANCELLED => BrokerError::Cancelled,
            NTE_NO_MATCH => BrokerError::NoMatchingCredential,
            NTE_BAD_KEYSET => BrokerError::WrongPin,
            NTE_DEVICE_NOT_READY => BrokerError::Transport,
            _ => BrokerError::Other(err.message().to_string()),
        }
    }

    /// Resolve the foreground window so the broker dialog stacks
    /// above the calling app. `GetForegroundWindow` is documented
    /// to return a null HWND when no window is focused; the broker
    /// tolerates that.
    ///
    /// # Safety
    ///
    /// Single Win32 query, no arguments, no pointer args.
    unsafe fn foreground_window() -> HWND {
        windows::Win32::UI::WindowsAndMessaging::GetForegroundWindow()
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
mod platform_impl {
    use super::{BrokerAssertion, BrokerAvailability, BrokerError, BrokerUnavailable};
    use libloading::{Library, Symbol};
    use std::os::raw::{c_char, c_int};
    use std::sync::OnceLock;
    use tokio::sync::oneshot;

    /// Captured at first probe attempt. `None` after a failed dlopen
    /// means the Swift glue is not linked into this bundle (self-
    /// signed dev builds without the entitlement) — surface as
    /// `AppleEntitlementMissing` to the dispatcher.
    static SWIFT_GLUE: OnceLock<Option<Library>> = OnceLock::new();

    /// The Swift side calls back via this signature once the
    /// `ASAuthorizationController` resolves. `tag` is the
    /// request id we minted; `status` is `0` = success / `1` =
    /// cancelled / `2` = timeout / `3` = wrong-pin / `4` =
    /// no-credential / `5` = transport / `6` = other.
    /// `signature_ptr` / `auth_data_ptr` / `user_handle_ptr` are
    /// owned by the Swift side and copied out before the callback
    /// returns; the Swift code frees them after our return.
    type SwiftCallback = unsafe extern "C" fn(
        tag: u64,
        status: c_int,
        signature_ptr: *const u8,
        signature_len: usize,
        auth_data_ptr: *const u8,
        auth_data_len: usize,
        user_handle_ptr: *const u8,
        user_handle_len: usize,
        message_ptr: *const c_char,
    );

    type SwiftIsAvailable = unsafe extern "C" fn() -> c_int;
    type SwiftGetAssertion = unsafe extern "C" fn(
        rp_id: *const c_char,
        credential_id_ptr: *const u8,
        credential_id_len: usize,
        challenge_ptr: *const u8,
        challenge_len: usize,
        require_uv: c_int,
        tag: u64,
        callback: SwiftCallback,
    ) -> c_int;

    fn glue() -> Option<&'static Library> {
        SWIFT_GLUE
            .get_or_init(|| {
                // The Swift glue is statically linked into the host
                // executable; dlopen with the special null name
                // resolves against the running process so the
                // `lfs_security_key_broker_*` symbols are visible.
                // SAFETY: `Library::new("")` wraps `dlopen(NULL)` /
                // `GetModuleHandle(NULL)`; the handle resolves to the
                // currently-loaded executable so no external library
                // initialisers can fire as a side effect of the load.
                // The returned handle's lifetime is process-wide.
                unsafe { Library::new("") }.ok()
            })
            .as_ref()
    }

    pub(super) fn is_available() -> BrokerAvailability {
        let Some(lib) = glue() else {
            return Err(BrokerUnavailable::AppleEntitlementMissing);
        };
        // SAFETY: symbol lookup is read-only; the resolved fn ptr
        // has the documented signature.
        let probe: Result<Symbol<SwiftIsAvailable>, _> =
            // SAFETY: `Library::get` performs a dlsym/GetProcAddress against an `unsafe` symbol;
            // the returned `Symbol<T>` borrows from `lib` for the rest of the function and the
            // function pointer signature `T` must match the C ABI of the exported symbol (verified
            // against the Windows / Apple SDK header).
            unsafe { lib.get(b"lfs_security_key_broker_is_available") };
        let Ok(probe) = probe else {
            return Err(BrokerUnavailable::AppleEntitlementMissing);
        };
        // SAFETY: parameterless probe, returns 0 / 1 / 2 per the
        // Swift contract (see SecurityKeyBroker.swift).
        let rc = unsafe { probe() };
        match rc {
            0 => Ok(()),
            1 => Err(BrokerUnavailable::TooOld),
            2 => Err(BrokerUnavailable::AppleEntitlementMissing),
            other => Err(BrokerUnavailable::Probe(format!("apple probe rc {other}"))),
        }
    }

    /// Pending map keyed on the request tag so the C callback can
    /// route the result back to the awaiting Rust future.
    type Pending = std::sync::Mutex<
        std::collections::HashMap<u64, oneshot::Sender<Result<BrokerAssertion, BrokerError>>>,
    >;
    static PENDING: OnceLock<Pending> = OnceLock::new();
    fn pending() -> &'static Pending {
        PENDING.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()))
    }
    static NEXT_TAG: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

    unsafe extern "C" fn on_complete(
        tag: u64,
        status: c_int,
        signature_ptr: *const u8,
        signature_len: usize,
        auth_data_ptr: *const u8,
        auth_data_len: usize,
        user_handle_ptr: *const u8,
        user_handle_len: usize,
        message_ptr: *const c_char,
    ) {
        let outcome = match status {
            // SAFETY: `slice::from_raw_parts` constructs a slice from a pointer + length; the
            // pointer is owned by the calling FFI and valid for the slice length for the borrow's
            // duration.
            0 => unsafe {
                let signature = if signature_len > 0 && !signature_ptr.is_null() {
                    std::slice::from_raw_parts(signature_ptr, signature_len).to_vec()
                } else {
                    Vec::new()
                };
                let authenticator_data = if auth_data_len > 0 && !auth_data_ptr.is_null() {
                    std::slice::from_raw_parts(auth_data_ptr, auth_data_len).to_vec()
                } else {
                    Vec::new()
                };
                let user_handle = if user_handle_len > 0 && !user_handle_ptr.is_null() {
                    Some(std::slice::from_raw_parts(user_handle_ptr, user_handle_len).to_vec())
                } else {
                    None
                };
                Ok(BrokerAssertion {
                    signature,
                    authenticator_data,
                    user_handle,
                })
            },
            1 => Err(BrokerError::Cancelled),
            2 => Err(BrokerError::Timeout),
            3 => Err(BrokerError::WrongPin),
            4 => Err(BrokerError::NoMatchingCredential),
            5 => Err(BrokerError::Transport),
            _ => {
                let msg = if message_ptr.is_null() {
                    String::from("apple broker error")
                } else {
                    // SAFETY: pointer is a null-terminated UTF-8
                    // C string owned by the Swift caller for the
                    // duration of this callback.
                    unsafe { std::ffi::CStr::from_ptr(message_ptr) }
                        .to_string_lossy()
                        .into_owned()
                };
                Err(BrokerError::Other(msg))
            }
        };
        if let Ok(mut map) = pending().lock() {
            if let Some(tx) = map.remove(&tag) {
                let _ = tx.send(outcome);
            }
        }
    }

    pub(super) async fn get_assertion(
        credential_id: Vec<u8>,
        rp_id: String,
        challenge: Vec<u8>,
        require_user_verification: bool,
    ) -> Result<BrokerAssertion, BrokerError> {
        let Some(lib) = glue() else {
            return Err(BrokerError::Other(
                "apple security-key broker glue not linked".into(),
            ));
        };
        // SAFETY: symbol lookup is read-only; fn ptr has the
        // documented Swift contract.
        let entry: Result<Symbol<SwiftGetAssertion>, _> =
            // SAFETY: `Library::get` performs a dlsym/GetProcAddress against an `unsafe` symbol;
            // the returned `Symbol<T>` borrows from `lib` for the rest of the function and the
            // function pointer signature `T` must match the C ABI of the exported symbol (verified
            // against the Windows / Apple SDK header).
            unsafe { lib.get(b"lfs_security_key_broker_get_assertion") };
        let Ok(entry) = entry else {
            return Err(BrokerError::Other(
                "apple security-key broker entrypoint missing".into(),
            ));
        };

        let tag = NEXT_TAG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        if let Ok(mut map) = pending().lock() {
            map.insert(tag, tx);
        }

        let rp_id_c = match std::ffi::CString::new(rp_id) {
            Ok(c) => c,
            Err(_) => return Err(BrokerError::Other("rp id contains nul byte".into())),
        };

        // SAFETY: every pointer is owned by a local on this stack
        // (`rp_id_c`, `credential_id`, `challenge`) and outlives
        // the call; the Swift side copies the bytes synchronously
        // before returning. The callback fn ptr is a stable
        // `extern "C" fn`.
        let rc = unsafe {
            entry(
                rp_id_c.as_ptr(),
                credential_id.as_ptr(),
                credential_id.len(),
                challenge.as_ptr(),
                challenge.len(),
                if require_user_verification { 1 } else { 0 },
                tag,
                on_complete,
            )
        };
        if rc != 0 {
            // Synchronous reject — pull the pending entry back.
            if let Ok(mut map) = pending().lock() {
                map.remove(&tag);
            }
            return Err(BrokerError::Other(format!("apple broker rc {rc}")));
        }
        rx.await
            .unwrap_or_else(|_| Err(BrokerError::Other("apple broker channel dropped".into())))
    }
}

#[cfg(target_os = "android")]
mod platform_impl {
    use super::{BrokerAssertion, BrokerAvailability, BrokerError, BrokerUnavailable};
    use crate::android::{jni_bootstrap, jni_helpers as h};
    use jni::objects::{JByteArray, JObject, JValue};
    use jni::sys::jlong;
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{Mutex, OnceLock};
    use tokio::sync::oneshot;

    type Pending = Mutex<HashMap<u64, oneshot::Sender<Result<BrokerAssertion, BrokerError>>>>;
    static PENDING: OnceLock<Pending> = OnceLock::new();
    static NEXT_TAG: AtomicU64 = AtomicU64::new(1);

    fn pending() -> &'static Pending {
        PENDING.get_or_init(|| Mutex::new(HashMap::new()))
    }

    pub(super) fn is_available() -> BrokerAvailability {
        if jni_bootstrap::main_activity().is_none() {
            return Err(BrokerUnavailable::NotBootstrapped);
        }
        // The Kotlin shim's static `isAvailable()` checks the
        // device's `PackageManager.hasSystemFeature("android.hardware.credentials")`
        // shape — wraps the API-28 minimum check + the
        // androidx.credentials runtime probe.
        let probe = h::with_env(|env| {
            let class = env
                .find_class("com/llloooggg/letsflutssh/Fido2Broker")
                .map_err(|e| format!("jni: find_class Fido2Broker: {e}"))?;
            let result = env
                .call_static_method(class, "isAvailable", "()Z", &[])
                .map_err(|e| format!("jni: Fido2Broker.isAvailable: {e}"))?;
            result
                .z()
                .map_err(|e| format!("jni: Fido2Broker.isAvailable not bool: {e}"))
        });
        match probe {
            Ok(true) => Ok(()),
            Ok(false) => Err(BrokerUnavailable::TooOld),
            Err(e) => Err(BrokerUnavailable::Probe(e)),
        }
    }

    pub(super) async fn get_assertion(
        credential_id: Vec<u8>,
        rp_id: String,
        challenge: Vec<u8>,
        require_user_verification: bool,
    ) -> Result<BrokerAssertion, BrokerError> {
        let tag = NEXT_TAG.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        if let Ok(mut map) = pending().lock() {
            map.insert(tag, tx);
        }
        let credential_id = credential_id.clone();
        let rp_id = rp_id.clone();
        let challenge = challenge.clone();
        if tokio::task::spawn_blocking(move || {
            kick_off(
                tag,
                &credential_id,
                &rp_id,
                &challenge,
                require_user_verification,
            )
        })
        .await
        .is_err()
        {
            if let Ok(mut map) = pending().lock() {
                map.remove(&tag);
            }
            return Err(BrokerError::Other("tokio join failed".into()));
        }
        rx.await
            .unwrap_or_else(|_| Err(BrokerError::Other("android broker channel dropped".into())))
    }

    fn kick_off(
        tag: u64,
        credential_id: &[u8],
        rp_id: &str,
        challenge: &[u8],
        require_uv: bool,
    ) -> Result<(), String> {
        h::with_env(|env| {
            let activity = jni_bootstrap::main_activity()
                .ok_or_else(|| "fido2 broker: MainActivity not bootstrapped".to_string())?;
            let rp_id_j = h::jstring(env, rp_id)?;
            let cred_arr: JByteArray<'_> = h::bytes_to_jbyte_array(env, credential_id)?;
            let chal_arr: JByteArray<'_> = h::bytes_to_jbyte_array(env, challenge)?;
            let cred_obj = JObject::from(cred_arr);
            let chal_obj = JObject::from(chal_arr);
            let class = env
                .find_class("com/llloooggg/letsflutssh/Fido2Broker")
                .map_err(|e| format!("jni: find_class Fido2Broker: {e}"))?;
            env.call_static_method(
                class,
                "getAssertion",
                "(Landroidx/fragment/app/FragmentActivity;Ljava/lang/String;[B[BZJ)V",
                &[
                    activity.into(),
                    (&rp_id_j).into(),
                    (&cred_obj).into(),
                    (&chal_obj).into(),
                    JValue::Bool(u8::from(require_uv)),
                    JValue::Long(tag as jlong),
                ],
            )
            .map(|_| ())
            .map_err(|e| format!("jni: Fido2Broker.getAssertion: {e}"))
        })
        .inspect_err(|_| {
            if let Ok(mut map) = pending().lock() {
                map.remove(&tag);
            }
        })
    }

    fn deliver(tag: u64, outcome: Result<BrokerAssertion, BrokerError>) {
        if let Ok(mut map) = pending().lock() {
            if let Some(tx) = map.remove(&tag) {
                let _ = tx.send(outcome);
            }
        }
    }

    /// Bridge into Kotlin → Rust on a successful Credential Manager
    /// assertion. The Kotlin side already unpacked the
    /// `AuthenticationResponseJson` and base64url-decoded the three
    /// component byte arrays.
    ///
    /// # Safety
    ///
    /// Invoked by the JVM through JNI when `Fido2Broker.kt` fires
    /// the success callback.
    #[no_mangle]
    pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_Fido2Broker_nativeOnAssertion<
        'local,
    >(
        mut env: jni::JNIEnv<'local>,
        _class: jni::objects::JClass<'local>,
        tag: jlong,
        signature: jni::objects::JByteArray<'local>,
        authenticator_data: jni::objects::JByteArray<'local>,
        user_handle: jni::objects::JByteArray<'local>,
    ) {
        let sig_obj = JObject::from(signature);
        let auth_obj = JObject::from(authenticator_data);
        let uh_obj = JObject::from(user_handle);
        let sig_bytes = match h::jbyte_array_to_bytes(&mut env, &sig_obj) {
            Ok(b) => b,
            Err(e) => {
                deliver(
                    tag as u64,
                    Err(BrokerError::Other(format!("sig decode: {e}"))),
                );
                return;
            }
        };
        let auth_bytes = match h::jbyte_array_to_bytes(&mut env, &auth_obj) {
            Ok(b) => b,
            Err(e) => {
                deliver(
                    tag as u64,
                    Err(BrokerError::Other(format!("auth-data decode: {e}"))),
                );
                return;
            }
        };
        let user_handle = if uh_obj.is_null() {
            None
        } else {
            h::jbyte_array_to_bytes(&mut env, &uh_obj).ok()
        };
        deliver(
            tag as u64,
            Ok(BrokerAssertion {
                signature: sig_bytes,
                authenticator_data: auth_bytes,
                user_handle,
            }),
        );
    }

    /// Bridge into Kotlin → Rust on a failed Credential Manager
    /// assertion. The Kotlin side maps the typed Credential Manager
    /// exception to a reason tag the dispatcher routes to UI
    /// toasts.
    ///
    /// # Safety
    ///
    /// Invoked by the JVM through JNI when `Fido2Broker.kt` fires
    /// the failure callback.
    #[no_mangle]
    pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_Fido2Broker_nativeOnFailure<
        'local,
    >(
        mut env: jni::JNIEnv<'local>,
        _class: jni::objects::JClass<'local>,
        tag: jlong,
        reason_tag: jni::objects::JString<'local>,
        detail: jni::objects::JString<'local>,
    ) {
        let reason = env
            .get_string(&reason_tag)
            .map(|s| -> String { s.into() })
            .unwrap_or_else(|_| "other".to_string());
        let detail_str = env
            .get_string(&detail)
            .map(|s| -> String { s.into() })
            .unwrap_or_default();
        let mapped = match reason.as_str() {
            "cancelled" => BrokerError::Cancelled,
            "timeout" => BrokerError::Timeout,
            "wrong-pin" => BrokerError::WrongPin,
            "no-credential" => BrokerError::NoMatchingCredential,
            "transport" => BrokerError::Transport,
            _ => BrokerError::Other(detail_str),
        };
        deliver(tag as u64, Err(mapped));
    }
}

#[cfg(not(any(
    target_os = "windows",
    target_os = "macos",
    target_os = "ios",
    target_os = "android",
)))]
mod platform_impl {
    use super::{BrokerAssertion, BrokerAvailability, BrokerError, BrokerUnavailable};

    pub(super) fn is_available() -> BrokerAvailability {
        Err(BrokerUnavailable::PlatformUnsupported)
    }

    pub(super) async fn get_assertion(
        _credential_id: Vec<u8>,
        _rp_id: String,
        _challenge: Vec<u8>,
        _require_user_verification: bool,
    ) -> Result<BrokerAssertion, BrokerError> {
        Err(BrokerError::Other(
            "OS broker not available on this platform".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rp_id_strips_ssh_prefix() {
        assert_eq!(rp_id_from_application("ssh:"), "");
        assert_eq!(rp_id_from_application("ssh:my-host"), "my-host");
    }

    #[test]
    fn rp_id_passes_through_unchanged_when_no_prefix() {
        assert_eq!(rp_id_from_application("example.com"), "example.com");
        assert_eq!(rp_id_from_application(""), "");
    }

    #[test]
    fn is_available_total() {
        // Linux runner under CI reaches the unsupported arm
        // (PlatformUnsupported). Other targets return whatever the
        // host probe yields; either way the call must not panic.
        let _ = is_available();
    }
}
