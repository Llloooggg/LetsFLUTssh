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
//! ## Pin layout — current + optional backup
//!
//! The verifier accepts a signature that validates against
//! [`PRIMARY_PUBLIC_KEY`] **or** [`BACKUP_PUBLIC_KEY`] (when
//! the latter is `Some`). Both keys are baked into the binary;
//! signatures come fetched alongside each release artefact via
//! the GitHub Releases API. No external service is consulted
//! at verify time, so the updater works even if Sigstore / a CA
//! / DNS is compromised.
//!
//! ### How rotation works
//!
//! Day 0 — only `PRIMARY_PUBLIC_KEY` is set; `BACKUP_PUBLIC_KEY`
//! is `None`. CI signs with the matching primary private key
//! (held in `RELEASE_SIGNING_KEY` secret + an offline copy in
//! the maintainer's password manager).
//!
//! Day N (planned rotation) — generate a fresh keypair offline,
//! ship a release that embeds the fresh pubkey as
//! `BACKUP_PUBLIC_KEY = Some([...])` while still signing with
//! the primary. Users who auto-update get the new build, which
//! now trusts both keys.
//!
//! Day N+1 (cutover) — flip CI to sign with the new private key
//! and ship the next release with `PRIMARY_PUBLIC_KEY` swapped
//! to the new pubkey + `BACKUP_PUBLIC_KEY = None` (or set to
//! the *previous* primary as a deprecation grace window). Stale
//! installs that skipped the day-N release land on the new
//! release, find the new primary key untrusted, but trust the
//! still-pinned previous primary as `BACKUP_PUBLIC_KEY` — they
//! follow the upgrade through.
//!
//! Day N+2 (full rotation complete) — drop the old key by
//! shipping the next release with `BACKUP_PUBLIC_KEY = None`.
//!
//! This sequence buys a hot-swappable rotation without bricking
//! the auto-update channel. Without the backup slot, a leaked
//! primary key forces a "publish from a fresh branch + manual
//! reinstall" recovery playbook documented in `SECURITY.md`.
//!
//! ### Compromise recovery
//!
//! If the primary key leaks **before** a backup pin lands — or
//! the leak invalidates trust in the backup too — the auto-
//! update channel cannot deliver a trustworthy fix to existing
//! installs. The recovery path is the manual reinstall flow in
//! [`SECURITY.md`](../../../../SECURITY.md): publish a fresh
//! release branch under a brand-new pubkey, announce the change
//! via the side-channel pinned in the README, and surface a
//! "please reinstall" notice through whatever non-update path
//! still works (about-screen check, website banner). The
//! `BACKUP_PUBLIC_KEY` slot exists to keep that fire drill rare,
//! not to replace it.

use crate::crypto::ed25519_verify;

/// Primary trusted Ed25519 release-signing public key. Raw 32
/// bytes of the Edwards-curve public point, captured with:
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

/// Optional backup Ed25519 release-signing public key. `None`
/// today — populated during a planned rotation to give existing
/// installs a hot-swappable upgrade path (see crate-level docs).
///
/// The verifier accepts a signature against this key in addition
/// to [`PRIMARY_PUBLIC_KEY`]. When set to `Some`, exactly one of
/// the two keys must validate — both fail-closed via
/// [`crate::crypto::ed25519_verify`]'s `verify_strict` semantics.
pub const BACKUP_PUBLIC_KEY: Option<[u8; 32]> = None;

/// Aggregate of every currently-trusted release-signing key.
/// Returns the active set as an iterator so a future rotation
/// step that needs to inspect both pins (rotation-ceremony
/// helper, key-fingerprint diagnostic) doesn't have to re-walk
/// the conditional logic.
pub fn pinned_public_keys() -> impl Iterator<Item = [u8; 32]> {
    std::iter::once(PRIMARY_PUBLIC_KEY).chain(BACKUP_PUBLIC_KEY)
}

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
    pinned_public_keys().any(|pk| ed25519_verify(&pk, message, signature))
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
        for pk in pinned_public_keys() {
            assert_eq!(pk.len(), 32);
        }
    }

    #[test]
    fn primary_key_is_listed_first() {
        // Iterator order matters for the `any()` short-circuit:
        // production releases sign with the primary, so the
        // primary check must come first to avoid a wasted
        // backup verification on every successful update.
        assert_eq!(pinned_public_keys().next(), Some(PRIMARY_PUBLIC_KEY));
    }

    #[test]
    fn backup_slot_appends_when_set() {
        // White-box: when BACKUP_PUBLIC_KEY is None the iterator
        // yields exactly one entry; when it's Some it yields two.
        // The current production constant is None.
        let count = pinned_public_keys().count();
        match BACKUP_PUBLIC_KEY {
            None => assert_eq!(count, 1),
            Some(_) => assert_eq!(count, 2),
        }
    }
}
