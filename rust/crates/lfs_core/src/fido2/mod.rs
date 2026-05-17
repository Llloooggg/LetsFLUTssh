//! FIDO2 hardware-bound SSH keys — transport dispatcher.
//!
//! Two transports land here:
//!
//! * **Direct CTAP2 over USB HID** (`client`) — `ctap-hid-fido2`
//!   on Linux (always) and as a fallback on Windows / macOS when
//!   the OS broker is unavailable or the user explicitly prefers
//!   direct HID. Pure-Rust transport; needs udev rules on Linux
//!   and HID class access on Windows.
//!
//! * **OS-managed broker** (`brokers`) — Windows `WebAuthn.dll`,
//!   macOS / iOS `ASAuthorizationSecurityKeyPublicKeyCredentialProvider`,
//!   Android Credential Manager (`androidx.credentials`). The
//!   broker dialog handles USB / NFC / BLE + the platform
//!   authenticator transparently; no admin grant on Windows, no
//!   Apple Developer entitlement on macOS for the unsigned
//!   self-build path (broker fails closed there → falls back to
//!   direct HID). iOS / Android have no HID fallback — the broker
//!   is the only viable path.
//!
//! `brokers::select_transport` is the single dispatch decision.
//! Settings exposes "Prefer direct USB HID over system dialog"
//! (off by default) for advanced users on the two platforms where
//! both paths exist; persisted via
//! `AppConfig.fido2_prefer_direct_hid`.
//!
//! Provides the surface the SSH connect path needs to authenticate
//! against an `sk-ssh-ed25519@openssh.com` or
//! `sk-ecdsa-sha2-nistp256@openssh.com` private key — opaque
//! credential id + application string captured at import time; the
//! device computes the signature on demand against a SHA-256
//! pre-hash of the SSH userauth signature input. Private key
//! material never leaves the authenticator and never lands on the
//! Dart heap.
//!
//! **Feature gate.** Compiling without the `fido2` Cargo feature
//! removes the `ctap-hid-fido2` dep but the broker dispatcher
//! still compiles — Windows / macOS / iOS / Android broker paths
//! work without the HID feature flag.

pub mod brokers;
pub mod types;

pub use types::{DeviceInfo, SkAssertion};

use crate::error::Error;

#[cfg(feature = "fido2")]
pub(crate) mod client;

/// True when at least one transport (broker or direct HID) is
/// reachable on this host.
///
/// Linux: returns whatever the HID probe yields. The udev rules
/// under `linux/letsflutssh/` give the `plugdev` group passthrough
/// on `hidraw*`.
///
/// Windows: returns `true` when WebAuthn.dll is present (Windows 10
/// 1903+) OR when the HID class driver is reachable. Either path
/// suffices.
///
/// macOS: returns `true` when the bundle carries the
/// `com.apple.developer.web-browser.public-key-credential`
/// entitlement (broker path), OR the direct HID stack is reachable.
/// Self-signed builds without the entitlement see the broker probe
/// reject and fall through to direct HID — works only after the
/// user grants the per-app permission Apple prompts for.
///
/// iOS: returns `true` only when the broker entitlement is present.
/// No HID fallback exists on iOS.
///
/// Android: returns `true` when Credential Manager is reachable
/// (API 28+) — no HID fallback.
#[must_use]
pub fn is_available() -> bool {
    !matches!(brokers::current_transport(), brokers::Transport::None)
}

/// Run the direct-HID `ctap-hid-fido2` assertion on the blocking
/// thread pool. Split out from [`get_assertion`] so the dispatcher
/// match arm stays compact and the cfg-gate is bounded to one
/// helper instead of leaking into the dispatch flow.
#[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
async fn direct_hid_get_assertion(
    credential_id: &[u8],
    application: &str,
    challenge: &[u8],
    pin: Option<&str>,
) -> Result<SkAssertion, Error> {
    let credential_id = credential_id.to_vec();
    let application = application.to_string();
    let challenge = challenge.to_vec();
    let pin = pin.map(|p| p.to_string());
    tokio::task::spawn_blocking(move || {
        client::get_assertion_blocking(&credential_id, &application, &challenge, pin.as_deref())
    })
    .await
    .map_err(|e| Error::Fido2(format!("spawn_blocking join: {e}")))?
}

#[cfg(not(all(feature = "fido2", any(target_os = "linux", target_os = "windows"))))]
async fn direct_hid_get_assertion(
    _credential_id: &[u8],
    _application: &str,
    _challenge: &[u8],
    _pin: Option<&str>,
) -> Result<SkAssertion, Error> {
    Err(Error::Fido2(
        "direct hardware-key access unavailable on this platform".into(),
    ))
}

/// True when the direct CTAP2 HID transport is reachable on the
/// running host. Exposed for the FRB dispatcher-snapshot probe;
/// the dispatcher itself reads this through `brokers::Availability`.
#[must_use]
pub fn is_available_direct_hid() -> bool {
    #[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
    {
        client::probe_available()
    }
    #[cfg(not(all(feature = "fido2", any(target_os = "linux", target_os = "windows"))))]
    {
        false
    }
}

/// Enumerate connected HID FIDO2 authenticators. Returns an empty
/// list on platforms that route through the OS broker — the broker
/// dialog enumerates the device list itself, and an empty Dart-side
/// list of pre-pickable devices is the right answer.
///
/// The connect path treats an empty list the same as the
/// platform-unsupported branch and surfaces the locale-aware
/// "no hardware key found" toast.
pub fn list_devices() -> Result<Vec<DeviceInfo>, Error> {
    #[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
    {
        // Direct HID transport — `ctap-hid-fido2` enumerates the
        // plugged-in keys. The broker path on Windows hides the
        // enumeration inside the dialog, so even when the broker
        // is preferred we still surface the HID list (it's the
        // single shape the Dart key-manager renders).
        return client::list_devices();
    }
    #[cfg(not(all(feature = "fido2", any(target_os = "linux", target_os = "windows"))))]
    {
        Ok(Vec::new())
    }
}

/// Request a CTAP2 assertion for an `sk-*` SSH key.
///
/// `credential_id` is the opaque blob captured at import from the
/// `sk-ssh-ed25519@openssh.com` / `sk-ecdsa-sha2-nistp256@openssh.com`
/// public-key body. `application` is the SSH RP-id string (the
/// `application` field of the same wire blob — typically `ssh:`).
/// `challenge` is the SHA-256 pre-hash of the SSH userauth signature
/// input the caller has already computed; the device signs over
/// `authenticator_data || clientDataHash`. `pin` is required iff the
/// credential carries the user-verification bit captured at import.
///
/// Transport selection:
///
/// - Windows / macOS: broker by default, direct HID fallback. The
///   `pin` argument forwards to the direct-HID layer; the broker
///   ignores it (the OS dialog handles PIN entry inside the
///   system surface) but the truthiness of `pin.is_some()` /
///   the import-time UV flag is used as the UV requirement.
/// - Linux: always direct HID (no broker primitive exists).
/// - iOS / Android: always broker. `pin` is ignored — the broker
///   surface drives the credential gate.
///
/// Blocking I/O on the direct-HID arm runs inside `spawn_blocking`
/// — the `ctap-hid-fido2` read loop is sync. The broker arms are
/// already async on top of the per-OS callback bridge.
pub async fn get_assertion(
    credential_id: &[u8],
    application: &str,
    challenge: &[u8],
    pin: Option<&str>,
) -> Result<SkAssertion, Error> {
    match brokers::current_transport() {
        brokers::Transport::Broker => {
            // PIN argument's mere presence captures the UV
            // requirement on the broker path. Users who imported a
            // UV-required credential always paired it with a PIN
            // hand-off; touch-only credentials never pass one in.
            let require_uv = pin.is_some();
            brokers::get_assertion_via_broker(credential_id, application, challenge, require_uv)
                .await
        }
        brokers::Transport::DirectHid => {
            direct_hid_get_assertion(credential_id, application, challenge, pin).await
        }
        brokers::Transport::None => {
            // Silence unused-arg warnings on targets where the
            // dispatcher always lands here.
            let _ = (credential_id, application, challenge, pin);
            Err(Error::Fido2(
                "no FIDO2 transport available on this platform".into(),
            ))
        }
    }
}
