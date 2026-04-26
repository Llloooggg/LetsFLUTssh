//! Ed25519 verification of release artefact signatures.
//!
//! Goal: defend the auto-updater against the threat that an
//! attacker can rewrite both the binary AND its declared SHA-256
//! (the SHA comes from the same GitHub Release JSON the binary
//! does, so on its own it is not authentication).
//!
//! Verification is local: the public key is compiled into the
//! crate, and the signature is fetched from the GitHub release
//! alongside the binary. No external service is consulted at
//! verify time, so the updater works even if Sigstore / a CA /
//! DNS is compromised.
//!
//! ## Single-pin layout
//!
//! We embed **one** release-signing public key. CI signs with the
//! matching private key, held in the `RELEASE_SIGNING_KEY` GitHub
//! secret plus an offline copy in the maintainer's password manager.
//!
//! If the private key ever leaks, the auto-update channel is
//! effectively dead for existing installs — any new release would
//! have to be signed by a key the app already trusts, and the
//! only pinned key is now the compromised one. The recovery path
//! is to publish a new release branch with a fresh pubkey pair
//! and ask users to reinstall manually from the website. There is
//! no key-rotation ceremony.
//!
//! This is a deliberate simplification: a backup pin buys one
//! rotation at the cost of permanent ceremony (generate a second
//! key, keep it offline, embed it, document the rotation flow).
//! For a solo-dev repo where "dump the install and grab the
//! fresh one" is a reasonable incident playbook, the single-pin
//! design removes the whole two-key maintenance burden.

use crate::crypto::ed25519_verify;

/// Trusted Ed25519 release-signing public keys. Raw 32 bytes of
/// the Edwards-curve public point each, captured with:
///
/// ```text
/// openssl pkey -in release-key-current.pem -pubout -outform DER | tail -c 32
/// ```
///
/// One entry today; a slice so a future hardened-rotation path
/// can pin two keys (current + previous) without changing this
/// API shape.
pub const PINNED_PUBLIC_KEYS: &[[u8; 32]] = &[
    // Current — `release-key-current.pem` (generated 2026-04-17)
    [
        0x15, 0x6a, 0x7d, 0x78, 0xe6, 0x28, 0x52, 0xbd, 0x3e, 0xf8, 0x60, 0x71, 0x7f, 0xcb, 0x8d,
        0xde, 0xad, 0x1b, 0x2d, 0x75, 0xe3, 0x86, 0x95, 0x8f, 0xec, 0x3c, 0xa8, 0x12, 0x30, 0x57,
        0x32, 0x03,
    ],
];

/// Verify `signature` (raw 64-byte Ed25519 signature) over `message`
/// against any pinned public key. Returns `true` only on a valid
/// signature — wrong-length signature, malformed input, or no
/// pinned key matching all return `false` (fail-closed).
///
/// `verify_strict` semantics inherited from
/// [`crate::crypto::ed25519_verify`] — signatures that pass the
/// lax check but would be malleable are rejected.
pub fn verify_release_signature(message: &[u8], signature: &[u8]) -> bool {
    if signature.len() != 64 {
        return false;
    }
    PINNED_PUBLIC_KEYS
        .iter()
        .any(|pk| ed25519_verify(pk, message, signature))
}

#[cfg(test)]
mod tests {
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
    fn pinned_keys_each_thirty_two_bytes() {
        for pk in PINNED_PUBLIC_KEYS {
            assert_eq!(pk.len(), 32);
        }
    }
}
