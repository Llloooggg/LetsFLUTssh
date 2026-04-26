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
