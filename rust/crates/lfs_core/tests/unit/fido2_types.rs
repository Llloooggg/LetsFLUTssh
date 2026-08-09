/// Unit tests extracted from fido2/types.rs
/// Declared via `#[path] mod tests;` in the source file.
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
