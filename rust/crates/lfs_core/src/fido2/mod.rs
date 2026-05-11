//! Direct CTAP2 over USB HID for hardware-bound SSH keys.
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
//! **Capability ladder.** Desktop (Linux + Windows) uses the
//! direct HID path via `ctap-hid-fido2`. macOS direct CTAP2 works
//! up to the first call inside the sandbox; `is_available()`
//! returns `true` but a `get_assertion` may surface
//! `Error::Fido2("kIOReturnNotPermitted")` when the Developer
//! Program entitlement is absent. iOS keeps the path
//! disabled — NFC-only is a future follow-up. Android keeps the
//! path disabled until the USB-host JNI bridge lands.
//!
//! **Feature gate.** Compiling without the `fido2` Cargo feature
//! stubs every public symbol with the platform-unsupported branch:
//! `is_available() = false`, `list_devices() = empty`,
//! `get_assertion()` returns `Error::Fido2("feature disabled at
//! build time")`. The runtime probe is the single source of truth
//! for whether the UI exposes the hardware-key import row.

pub mod types;

pub use types::{DeviceInfo, SkAssertion};

use crate::error::Error;

#[cfg(feature = "fido2")]
mod client;

/// True when the host has a usable HID FIDO2 backend reachable.
///
/// Linux: succeeds when `hidapi`'s enumeration call returns without
/// a transport error (a missing `libudev` on the runner is the only
/// realistic failure; the udev rules under `linux/letsflutssh/`
/// give the `plugdev` group passthrough on `hidraw*`).
///
/// Windows: succeeds whenever the HID class driver is reachable;
/// `WebAuthn.dll` is the OS-managed alternative but the direct HID
/// path covers every supported Windows version (10+).
///
/// macOS / iOS / Android: returns `false` under today's build.
/// The macOS HID path requires the Apple Developer Program
/// entitlement (`com.apple.developer.kernel.increased-memory-limit`
/// plus a notarised sandbox profile); we surface the row disabled
/// with the locale-aware "requires Apple Developer Program
/// entitlement" tooltip until that entitlement is signed into a
/// release build. iOS reaches CTAP2 only over NFC / Bluetooth
/// (future follow-up). Android needs the USB-host JNI bridge.
#[must_use]
pub fn is_available() -> bool {
    #[cfg(feature = "fido2")]
    {
        // Desktop targets get the real HID probe; mobile targets keep
        // the path disabled at this rung until the per-platform native
        // glue lands (NFC for iOS, USB-host JNI for Android, Apple
        // entitlement for macOS).
        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            return client::probe_available();
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        {
            return false;
        }
    }
    #[cfg(not(feature = "fido2"))]
    {
        false
    }
}

/// Enumerate connected HID FIDO2 authenticators. Empty on platforms
/// where [`is_available`] returns `false`; the connect path treats
/// an empty list the same as the platform-unsupported branch and
/// surfaces the locale-aware "no hardware key found" toast.
pub fn list_devices() -> Result<Vec<DeviceInfo>, Error> {
    #[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
    {
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
/// Blocking I/O runs inside `spawn_blocking` — the `ctap-hid-fido2`
/// read loop is sync.
pub async fn get_assertion(
    credential_id: &[u8],
    application: &str,
    challenge: &[u8],
    pin: Option<&str>,
) -> Result<SkAssertion, Error> {
    #[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
    {
        let credential_id = credential_id.to_vec();
        let application = application.to_string();
        let challenge = challenge.to_vec();
        let pin = pin.map(|p| p.to_string());
        return tokio::task::spawn_blocking(move || {
            client::get_assertion_blocking(&credential_id, &application, &challenge, pin.as_deref())
        })
        .await
        .map_err(|e| Error::Fido2(format!("spawn_blocking join: {e}")))?;
    }
    #[cfg(not(all(feature = "fido2", any(target_os = "linux", target_os = "windows"))))]
    {
        let _ = (credential_id, application, challenge, pin);
        Err(Error::Fido2(
            "direct hardware-key access unavailable on this platform".into(),
        ))
    }
}
