//! FRB adapter for `lfs_core::update_signing`. One synchronous
//! verify call — the pinned public key is a tiny compile-time
//! constant and the Ed25519 verify is a few microseconds, so a
//! sync hop is the right shape (no FRB worker scheduling cost).

/// Verify `signature` (raw 64-byte Ed25519 signature) over
/// `message` against the pinned release-signing public key(s).
/// Returns `false` for any malformed input — the Dart caller's
/// "no signature match → fail closed" branch is the only
/// negative path it has to handle.
#[flutter_rust_bridge::frb(sync)]
pub fn update_verify_release_signature(message: Vec<u8>, signature: Vec<u8>) -> bool {
    lfs_core::update_signing::verify_release_signature(&message, &signature)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_signature_returns_false_not_panic() {
        // The Dart caller's only negative branch is "verify returned
        // false → fail closed". A zero-byte signature, a partial one,
        // and a 64-byte all-zero buffer must all collapse to `false`
        // without unwinding through FRB.
        assert!(!update_verify_release_signature(b"hello".to_vec(), vec![]));
        assert!(!update_verify_release_signature(
            b"hello".to_vec(),
            vec![0u8; 8]
        ));
        assert!(!update_verify_release_signature(
            b"hello".to_vec(),
            vec![0u8; 64]
        ));
    }

    #[test]
    fn random_signature_against_random_message_returns_false() {
        // Cryptographically negligible chance a random 64-byte
        // string verifies under the pinned public key — verify
        // closes that branch deterministically.
        let msg = b"arbitrary update manifest bytes".to_vec();
        let sig: Vec<u8> = (0u8..64).collect();
        assert!(!update_verify_release_signature(msg, sig));
    }

    #[test]
    fn empty_message_with_empty_signature_returns_false() {
        assert!(!update_verify_release_signature(vec![], vec![]));
    }
}
