/// Unit tests extracted from update/signing.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn rejects_wrong_length_signature() {
    assert!(!verify_release_signature(b"msg", &[0u8; 63]));
    assert!(!verify_release_signature(b"msg", &[0u8; 65]));
    assert!(!verify_release_signature(b"msg", &[]));
}

#[test]
fn rejects_zero_signature_against_pinned_key() {
    // All-zero 64-byte signature must not validate against
    // the production-pinned key.
    assert!(!verify_release_signature(b"any-message", &[0u8; 64]));
}

#[test]
fn primary_key_is_thirty_two_bytes() {
    assert_eq!(PRIMARY_PUBLIC_KEY.len(), 32);
}
