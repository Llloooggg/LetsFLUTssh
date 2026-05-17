//! Typed FRB-friendly value shapes for the FIDO2 surface.

/// One CTAP2 authenticator the host can talk to over HID. The
/// `path` is the platform-specific HID device path
/// (`/dev/hidraw0` on Linux, `\\?\hid#vid_1050&pid_0407...`
/// on Windows); UI uses it only as a stable handle to
/// disambiguate when more than one key is plugged in.
#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub path: String,
    /// USB vendor id (e.g. `0x1050` for Yubico). Stable per
    /// hardware vendor; the UI does not show this directly but
    /// the log line carries it for support traces.
    pub vendor_id: u16,
    /// USB product id. Same use as `vendor_id`.
    pub product_id: u16,
    /// Human-readable product string ("YubiKey 5C NFC",
    /// "SoloKey", "Titan Security Key"). Falls back to the empty
    /// string when the device firmware does not expose one.
    pub product_string: String,
}

/// CTAP2 getAssertion response shape, narrowed to the fields the
/// SSH `sk-*` userauth path consumes.
///
/// `signature` is the raw CTAP signature (Ed25519: 64 bytes; ECDSA
/// P-256: DER-encoded `SEQUENCE { r, s }`). `authenticator_data`
/// carries the WebAuthn RP-id-hash header + flags byte + signature
/// counter; the SSH wire format trailer is `flags || u32 counter`,
/// both extracted from this blob. `user_handle` is the optional
/// user-id the credential was registered against — surfaced for
/// completeness; SSH does not consume it.
#[derive(Debug, Clone)]
pub struct SkAssertion {
    pub signature: Vec<u8>,
    pub authenticator_data: Vec<u8>,
    pub user_handle: Option<Vec<u8>>,
}

impl SkAssertion {
    /// SSH wire-format `flags` byte — the 33rd byte of
    /// `authenticator_data` (the WebAuthn flags). OpenSSH copies it
    /// verbatim into the `sk-*` signature trailer.
    #[must_use]
    pub fn ssh_flags(&self) -> u8 {
        self.authenticator_data.get(32).copied().unwrap_or(0)
    }

    /// SSH wire-format `counter` — bytes 33..37 of
    /// `authenticator_data`, big-endian. OpenSSH copies it verbatim
    /// into the `sk-*` signature trailer. Defaults to zero if the
    /// authenticator returned a truncated blob (shape-violation;
    /// the verifier rejects on the next hop).
    #[must_use]
    pub fn ssh_counter(&self) -> u32 {
        let Some(slice) = self.authenticator_data.get(33..37) else {
            return 0;
        };
        let mut out = [0u8; 4];
        out.copy_from_slice(slice);
        u32::from_be_bytes(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ssh_flags_reads_byte_32_of_authdata() {
        // authenticatorData layout per WebAuthn: rpIdHash (32) ||
        // flags (1) || signCount (4). flags MUST come from offset 32.
        let mut blob = vec![0u8; 37];
        blob[32] = 0x05;
        let a = SkAssertion {
            signature: vec![],
            authenticator_data: blob,
            user_handle: None,
        };
        assert_eq!(a.ssh_flags(), 0x05);
    }

    #[test]
    fn ssh_counter_reads_big_endian_u32_from_byte_33() {
        let mut blob = vec![0u8; 37];
        blob[33..37].copy_from_slice(&0x01020304u32.to_be_bytes());
        let a = SkAssertion {
            signature: vec![],
            authenticator_data: blob,
            user_handle: None,
        };
        assert_eq!(a.ssh_counter(), 0x01020304);
    }

    #[test]
    fn ssh_flags_zero_on_truncated_authdata() {
        // Authenticator returned a header shorter than the WebAuthn
        // minimum — UI should treat the assertion as invalid; the
        // accessor just keeps the shape safe so callers don't panic.
        let a = SkAssertion {
            signature: vec![],
            authenticator_data: vec![0u8; 16],
            user_handle: None,
        };
        assert_eq!(a.ssh_flags(), 0);
        assert_eq!(a.ssh_counter(), 0);
    }
}
