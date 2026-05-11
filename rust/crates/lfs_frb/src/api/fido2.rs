//! FRB adapter for `lfs_core::fido2` — capability probe, device
//! enumeration, and on-demand assertion request for `sk-*` SSH
//! keys. The Dart connect path calls into [`fido2_is_available`]
//! to gate the hardware-key import row, [`fido2_list_devices`] to
//! render the multi-key disambiguation chip list, and
//! [`fido2_get_assertion`] when an `sk-*` key is the chosen
//! session credential.

use crate::api::frb_err;

/// FRB mirror of [`lfs_core::fido2::DeviceInfo`]. Mirrored — not
/// re-exported — so the codegen-emitted Dart class lives under
/// `lib/src/rust/api/fido2.dart` instead of cross-importing the
/// `lfs_core` shape into the FRB-generated tree.
#[derive(Debug, Clone)]
pub struct DbFido2Device {
    pub path: String,
    pub vendor_id: u16,
    pub product_id: u16,
    pub product_string: String,
}

impl From<lfs_core::fido2::DeviceInfo> for DbFido2Device {
    fn from(d: lfs_core::fido2::DeviceInfo) -> Self {
        Self {
            path: d.path,
            vendor_id: d.vendor_id,
            product_id: d.product_id,
            product_string: d.product_string,
        }
    }
}

/// FRB mirror of [`lfs_core::fido2::SkAssertion`].
#[derive(Debug, Clone)]
pub struct DbSkAssertion {
    pub signature: Vec<u8>,
    pub authenticator_data: Vec<u8>,
    pub user_handle: Option<Vec<u8>>,
}

impl From<lfs_core::fido2::SkAssertion> for DbSkAssertion {
    fn from(a: lfs_core::fido2::SkAssertion) -> Self {
        Self {
            signature: a.signature,
            authenticator_data: a.authenticator_data,
            user_handle: a.user_handle,
        }
    }
}

/// True when the host has a usable HID FIDO2 backend reachable.
/// Sync because the probe is a single `get_fidokey_devices()` call
/// and the FRB hop overhead would dwarf the actual work; the
/// hardware-key import row in the key manager polls this on every
/// rebuild.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn fido2_is_available() -> bool {
    lfs_core::fido2::is_available()
}

/// Enumerate plugged-in HID FIDO2 authenticators. Returns an empty
/// list when [`fido2_is_available`] is `false`. Surfaces a typed
/// error envelope via [`frb_err::kind::FIDO2`] when the HID
/// transport itself rejects enumeration (Linux udev rules missing,
/// Windows HID class driver unreachable).
pub async fn fido2_list_devices() -> Result<Vec<DbFido2Device>, String> {
    tokio::task::spawn_blocking(lfs_core::fido2::list_devices)
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::FIDO2, &format!("spawn_blocking: {e}")))?
        .map(|v| v.into_iter().map(DbFido2Device::from).collect())
        .map_err(|e| frb_err::from_core(&e))
}

/// Request a CTAP2 assertion against [`credential_id`] for the SSH
/// `sk-*` userauth path.
///
/// `application` is the SSH `application` string the device
/// registered the credential under (typically `ssh:`). `challenge`
/// is the SHA-256 pre-hash of the SSH userauth signature input the
/// caller has already computed. `pin` is required iff the
/// credential carries the user-verification bit captured at import.
pub async fn fido2_get_assertion(
    credential_id: Vec<u8>,
    application: String,
    challenge: Vec<u8>,
    pin: Option<String>,
) -> Result<DbSkAssertion, String> {
    lfs_core::fido2::get_assertion(&credential_id, &application, &challenge, pin.as_deref())
        .await
        .map(DbSkAssertion::from)
        .map_err(|e| frb_err::from_core(&e))
}
