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
//! Exactly one trusted public key — [`PRIMARY_PUBLIC_KEY`]. CI
//! signs with the matching private key, held in the
//! `RELEASE_SIGNING_KEY` GitHub secret plus an offline copy in
//! the maintainer's password manager.
//!
//! ## Rotation
//!
//! Rotation is a manual-reinstall ceremony, not an in-app
//! hot-swap. When the primary key is leaked or due for rotation:
//!
//! 1. Generate a fresh keypair offline (`openssl genpkey
//!    -algorithm Ed25519 -out release-key-new.pem`).
//! 2. Update the GitHub `RELEASE_SIGNING_KEY` secret + the
//!    offline backup copy.
//! 3. Embed the new pubkey by editing [`PRIMARY_PUBLIC_KEY`]
//!    below and shipping a new release.
//! 4. Announce the rotation via the README + website banner;
//!    existing installs whose auto-update breaks (because their
//!    embedded pubkey doesn't match the new signature) follow
//!    the manual-reinstall flow documented in
//!    [`SECURITY.md`](../../../../SECURITY.md).
//!
//! Why no hot-swap backup slot: shipping an `Option<[u8; 32]>`
//! that is `None` until a real rotation ceremony populates it
//! costs API surface for zero today-value. When (if) a rotation
//! is actually planned, the slot can be re-added in the same PR
//! that generates the keypair and embeds the bytes — atomic
//! infrastructure + use rather than indefinite scaffolding.

use crate::crypto::ed25519_verify;

/// Trusted Ed25519 release-signing public key. Raw 32 bytes of
/// the Edwards-curve public point, captured with:
///
/// ```text
/// openssl pkey -in release-key-current.pem -pubout -outform DER | tail -c 32
/// ```
///
/// CI signs every release artefact with the matching private key.
pub const PRIMARY_PUBLIC_KEY: [u8; 32] = [
    // Current — `release-key-current.pem` (generated 2026-04-17)
    0x15, 0x6a, 0x7d, 0x78, 0xe6, 0x28, 0x52, 0xbd, 0x3e, 0xf8, 0x60, 0x71, 0x7f, 0xcb, 0x8d, 0xde,
    0xad, 0x1b, 0x2d, 0x75, 0xe3, 0x86, 0x95, 0x8f, 0xec, 0x3c, 0xa8, 0x12, 0x30, 0x57, 0x32, 0x03,
];

/// Verify `signature` (raw 64-byte Ed25519 signature) over `message`
/// against [`PRIMARY_PUBLIC_KEY`]. Returns `true` only on a valid
/// signature — wrong-length signature, malformed input, or
/// non-matching pin all return `false` (fail-closed).
///
/// `verify_strict` semantics inherited from
/// [`crate::crypto::ed25519_verify`] — signatures that pass the
/// lax check but would be malleable are rejected.
pub fn verify_release_signature(message: &[u8], signature: &[u8]) -> bool {
    if signature.len() != 64 {
        return false;
    }
    ed25519_verify(&PRIMARY_PUBLIC_KEY, message, signature)
}
#[cfg(test)]
#[path = "../../tests/unit/update_signing.rs"]
mod tests;
