//! Transport dispatcher between the OS-managed FIDO2 broker and
//! the direct HID path.
//!
//! The broker (`lfs_os_security::fido2_broker`) handles
//! USB / NFC / BLE / platform authenticator transparently and works
//! without admin permission grants or the Apple Developer Program
//! entitlement. It is preferred wherever it works. The direct HID
//! transport (`super::client`, `ctap-hid-fido2`) is the fallback —
//! Linux always uses it, every other target falls back when the
//! broker probe says "unavailable".
//!
//! Selection logic at a glance:
//!
//! | OS      | Default        | Fallback              | Settings override |
//! |---------|----------------|-----------------------|-------------------|
//! | Linux   | direct HID     | none                  | n/a               |
//! | Windows | broker         | direct HID            | "prefer HID" forces direct |
//! | macOS   | broker         | direct HID            | "prefer HID" forces direct |
//! | iOS     | broker         | none (broker-or-fail) | n/a               |
//! | Android | broker         | none (broker-or-fail) | n/a               |
//!
//! The "Prefer direct USB HID over system dialog" toggle the
//! Settings security section exposes flips a process-wide
//! `AtomicBool` ([`set_prefer_direct_hid`]) the dispatcher reads on
//! every call. Off by default. The Dart Settings page hands the
//! toggled value to FRB; the Rust side persists it via the
//! `AppConfig.fido2_prefer_direct_hid` flag.

use std::sync::atomic::{AtomicBool, Ordering};

use crate::error::Error;
use crate::fido2::types::SkAssertion;

/// True when the user has flipped on "Prefer direct USB HID over
/// system dialog" — the dispatcher then skips the broker even on
/// platforms where it works. Off by default. Persisted via
/// `AppConfig.fido2_prefer_direct_hid`; the FRB shim drives this
/// atomic at startup and on every toggle.
static PREFER_DIRECT_HID: AtomicBool = AtomicBool::new(false);

/// Update the process-wide "prefer direct HID" flag. Called by the
/// FRB shim at startup (with the persisted config value) and on
/// every Settings toggle.
pub fn set_prefer_direct_hid(prefer: bool) {
    PREFER_DIRECT_HID.store(prefer, Ordering::Relaxed);
}

/// Read the current value of the "prefer direct HID" flag. Tests +
/// the Dart Settings UI read this to keep the toggle in sync.
#[must_use]
pub fn prefer_direct_hid() -> bool {
    PREFER_DIRECT_HID.load(Ordering::Relaxed)
}

/// Transports the dispatcher routes to. Pure-data enum so unit
/// tests can pin the selection logic without touching either FFI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    /// OS broker dialog (Windows WebAuthn.dll / Apple
    /// ASAuthorization / Android Credential Manager). USB / NFC /
    /// BLE handled by the OS.
    Broker,
    /// Direct CTAP2 over USB HID via `ctap-hid-fido2`. Linux
    /// default; fallback on Windows / macOS.
    DirectHid,
    /// Neither path is reachable on this host. UI surfaces the row
    /// disabled.
    None,
}

/// Pure-data view of the per-host availability that drives the
/// dispatcher. Factored out so tests can pass a stub instead of
/// the real `is_available` probes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Availability {
    pub broker: bool,
    pub direct_hid: bool,
    pub prefer_direct_hid: bool,
    /// `target_os` family. `Os::Linux` always picks HID; broker
    /// preference is irrelevant. Mobile (`Ios` / `Android`) has no
    /// HID fallback so `None` is the right answer when the broker
    /// is missing.
    pub os: Os,
}

/// Coarse target-OS bucket the dispatcher reasons over.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Os {
    Linux,
    Windows,
    Macos,
    Ios,
    Android,
    /// Anything else (BSDs, Fuchsia, WASM). HID path may exist via
    /// `ctap-hid-fido2`'s libusb backend, broker definitely doesn't.
    Other,
}

impl Os {
    #[must_use]
    pub fn current() -> Self {
        #[cfg(target_os = "linux")]
        {
            Self::Linux
        }
        #[cfg(target_os = "windows")]
        {
            Self::Windows
        }
        #[cfg(target_os = "macos")]
        {
            Self::Macos
        }
        #[cfg(target_os = "ios")]
        {
            Self::Ios
        }
        #[cfg(target_os = "android")]
        {
            Self::Android
        }
        #[cfg(not(any(
            target_os = "linux",
            target_os = "windows",
            target_os = "macos",
            target_os = "ios",
            target_os = "android",
        )))]
        {
            Self::Other
        }
    }
}

/// Pure dispatch decision. Linux pins to `DirectHid`; mobile pins
/// to the broker (no HID fallback there); desktop prefers broker
/// unless the user flipped the "prefer direct HID" toggle.
#[must_use]
pub fn select_transport(av: Availability) -> Transport {
    match av.os {
        Os::Linux => {
            if av.direct_hid {
                Transport::DirectHid
            } else {
                Transport::None
            }
        }
        Os::Ios | Os::Android => {
            if av.broker {
                Transport::Broker
            } else {
                Transport::None
            }
        }
        Os::Windows | Os::Macos => select_desktop_transport(&av),
        Os::Other => direct_hid_then_broker(&av),
    }
}

/// Desktop preference order — honour the user's "prefer direct HID"
/// toggle first, then fall back to broker, then any HID.
fn select_desktop_transport(av: &Availability) -> Transport {
    if av.prefer_direct_hid && av.direct_hid {
        Transport::DirectHid
    } else {
        broker_then_direct_hid(av)
    }
}

/// Broker first, then direct HID, then none.
fn broker_then_direct_hid(av: &Availability) -> Transport {
    if av.broker {
        Transport::Broker
    } else if av.direct_hid {
        Transport::DirectHid
    } else {
        Transport::None
    }
}

/// Direct HID first, then broker, then none.
fn direct_hid_then_broker(av: &Availability) -> Transport {
    if av.direct_hid {
        Transport::DirectHid
    } else if av.broker {
        Transport::Broker
    } else {
        Transport::None
    }
}

/// Probe the host and decide which transport the dispatcher should
/// use on the next call. Single source of truth for the runtime
/// `is_available` / `list_devices` / `get_assertion` branches.
pub fn current_transport() -> Transport {
    let availability = Availability {
        broker: lfs_os_security::fido2_broker::is_available().is_ok(),
        direct_hid: direct_hid_available(),
        prefer_direct_hid: prefer_direct_hid(),
        os: Os::current(),
    };
    select_transport(availability)
}

#[cfg(all(feature = "fido2", any(target_os = "linux", target_os = "windows")))]
fn direct_hid_available() -> bool {
    super::client::probe_available()
}

#[cfg(not(all(feature = "fido2", any(target_os = "linux", target_os = "windows"))))]
fn direct_hid_available() -> bool {
    false
}

/// Wrap the broker call into a `SkAssertion` so the dispatcher in
/// `super::get_assertion` swaps transports without touching the
/// caller's contract.
pub(super) async fn get_assertion_via_broker(
    credential_id: &[u8],
    application: &str,
    challenge: &[u8],
    require_user_verification: bool,
) -> Result<SkAssertion, Error> {
    let rp_id = lfs_os_security::fido2_broker::rp_id_from_application(application).to_string();
    let assertion = lfs_os_security::fido2_broker::get_assertion(
        credential_id.to_vec(),
        rp_id,
        challenge.to_vec(),
        require_user_verification,
    )
    .await
    .map_err(map_broker_err)?;
    Ok(SkAssertion {
        signature: assertion.signature,
        authenticator_data: assertion.authenticator_data,
        user_handle: assertion.user_handle,
    })
}

/// Map the broker's typed error into the shared `Error::Fido2`
/// envelope, prefixing the same discriminator strings the direct-
/// HID path uses (`wrong pin:` / `timeout:`) so the FRB envelope's
/// typed routing in Dart works the same on both transports.
fn map_broker_err(err: lfs_os_security::fido2_broker::BrokerError) -> Error {
    use lfs_os_security::fido2_broker::BrokerError;
    match err {
        BrokerError::Cancelled => Error::Fido2("cancelled: user dismissed the dialog".into()),
        BrokerError::Timeout => Error::Fido2("timeout: dialog timed out".into()),
        BrokerError::WrongPin => Error::Fido2("wrong pin".into()),
        BrokerError::NoMatchingCredential => {
            Error::Fido2("no matching credential on the device".into())
        }
        BrokerError::Transport => Error::Fido2("transport: device disconnected".into()),
        BrokerError::Other(msg) => Error::Fido2(msg),
    }
}
#[cfg(test)]
#[path = "../../tests/unit/fido2_brokers.rs"]
mod tests;
