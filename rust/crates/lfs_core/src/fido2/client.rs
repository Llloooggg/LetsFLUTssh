//! Thin wrapper around `ctap-hid-fido2`. Pure-sync API — the
//! upstream crate's read loop is blocking; [`super::get_assertion`]
//! hops to `spawn_blocking` for the FRB worker's sake.
//!
//! The wrapper exists so a future bump of the upstream API surface
//! lands here and nowhere else. The `lfs_core::fido2` module
//! exposes the FRB-friendly signatures; this file is the only
//! place that names upstream types.

use ctap_hid_fido2::fidokey::FidoKeyHid;
use ctap_hid_fido2::{get_fidokey_devices, FidoKeyHidFactory, HidParam, LibCfg};

use crate::error::Error;
use crate::fido2::types::{DeviceInfo, SkAssertion};

/// Build the upstream `LibCfg` with the project's default
/// posture. `enable_log = false` because the upstream crate's
/// `println!`-style log path bypasses our sanitiser; the wrapper
/// surfaces failures through `Error::Fido2` instead.
fn cfg() -> LibCfg {
    LibCfg::init().with_enable_log(false)
}

/// True when at least one FIDO2 authenticator is currently
/// enumerable through HID. `ctap-hid-fido2` 3.5.x swallows HID
/// transport failures and returns an empty Vec for both
/// "transport unreachable" (no udev rules, sandboxed runner,
/// missing `libusb`/`hidapi`) and "no device plugged in", so the
/// two cases aren't distinguishable through the public API; the
/// availability signal degrades to "device currently present",
/// which matches the honest UI question (the FIDO2 connect row
/// disables when no key is plugged in regardless of why).
pub(crate) fn probe_available() -> bool {
    !get_fidokey_devices().is_empty()
}

pub(crate) fn list_devices() -> Result<Vec<DeviceInfo>, Error> {
    let devices = get_fidokey_devices();
    let mut out = Vec::with_capacity(devices.len());
    for info in devices {
        let path = match &info.param {
            HidParam::Path(p) => p.clone(),
            // VidPid params have no stable host-side path; the UI
            // falls back to the vendor/product label.
            _ => String::new(),
        };
        out.push(DeviceInfo {
            path,
            vendor_id: info.vid,
            product_id: info.pid,
            product_string: info.product_string,
        });
    }
    Ok(out)
}

/// Open the first reachable authenticator and request a
/// non-resident-key assertion. Authentication is single-shot —
/// every connect spins up a fresh `FidoKeyHid`. PIN auth bumps
/// the call to the user-verification CTAP2 flow on the upstream
/// crate's side; the device's LED blinks until the user taps.
pub(crate) fn get_assertion_blocking(
    credential_id: &[u8],
    application: &str,
    challenge: &[u8],
    pin: Option<&str>,
) -> Result<SkAssertion, Error> {
    let devices = get_fidokey_devices();
    if devices.is_empty() {
        return Err(Error::Fido2("no hardware key plugged in".into()));
    }

    let params: Vec<HidParam> = devices.iter().map(|d| d.param.clone()).collect();
    let device: FidoKeyHid = FidoKeyHidFactory::create_by_params(&params, &cfg())
        .map_err(|e| Error::Fido2(format!("hid open: {e}")))?;

    let credential_ids = vec![credential_id.to_vec()];
    let assertion = device
        .get_assertion(application, challenge, &credential_ids, pin)
        .map_err(map_upstream_err)?;

    Ok(SkAssertion {
        signature: assertion.signature,
        authenticator_data: assertion.auth_data,
        user_handle: if assertion.user.id.is_empty() {
            None
        } else {
            Some(assertion.user.id)
        },
    })
}

/// Translate an `anyhow::Error` from the upstream crate into a
/// typed `Error::Fido2`. The matcher pins three discriminators
/// the connect path's UI cares about — wrong PIN, timeout, and
/// the catch-all device failure — so the locale-aware toast can
/// branch without substring-matching the upstream message.
fn map_upstream_err(err: impl std::fmt::Display) -> Error {
    let msg = err.to_string();
    let lower = msg.to_ascii_lowercase();
    if lower.contains("pin") && (lower.contains("invalid") || lower.contains("incorrect")) {
        Error::Fido2(format!("wrong pin: {msg}"))
    } else if lower.contains("timeout") || lower.contains("timed out") {
        Error::Fido2(format!("timeout: {msg}"))
    } else {
        Error::Fido2(msg)
    }
}
#[cfg(test)]
#[path = "../../tests/unit/fido2_client.rs"]
mod tests;
