//! FRB adapter for `lfs_core::security::keychain_pepper_prompt`
//! (Decision 1 + Decision 2 in
//! `docs/RUST_MIGRATION_REMAINING.md`).
//!
//! Sync — every op is a small mutex acquire + oneshot send.
//! The Dart subscriber executes the
//! `flutter_secure_storage.read('letsflutssh_l2_pepper')`
//! plugin call after seeing
//! `BusEvent::KeychainPepperPromptRequest`, then dispatches
//! the response via this shim. Decision 2: keychain access
//! stays Dart-side (existing audit perimeter, no new native
//! crate per platform).

use lfs_core::security::keychain_pepper_prompt;

/// Resolve a pending L2 keychain pepper read with the bytes
/// the Dart subscriber pulled from
/// `flutter_secure_storage`. Pass an empty `Vec` to mean
/// "entry missing / read failed" — same shape the Rust caller
/// routes through the L2 reset path.
///
/// Returns `true` when a receiver was actually woken; `false`
/// for an unknown / already-resolved prompt id (caller can
/// log the orphan).
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_pepper_prompt_resolve(prompt_id: String, pepper_bytes: Vec<u8>) -> bool {
    let response = if pepper_bytes.is_empty() {
        None
    } else {
        Some(pepper_bytes)
    };
    keychain_pepper_prompt::instance().resolve(&prompt_id, response)
}

/// Cancel a pending prompt without resolving — used by the
/// Dart subscriber when it can't dispatch the keychain read
/// (e.g. the user interrupted the flow with a tier reset
/// from the lock screen). Idempotent on a missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_pepper_prompt_cancel(prompt_id: String) {
    keychain_pepper_prompt::instance().cancel(&prompt_id);
}
