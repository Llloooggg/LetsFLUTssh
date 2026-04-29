//! FRB adapter for `lfs_core::security::keychain_pepper_prompt`.
//!
//! Sync — every op is a small mutex acquire + oneshot send.
//! The Dart subscriber executes the
//! `flutter_secure_storage.read('letsflutssh_l2_pepper')`
//! plugin call after seeing
//! `BusEvent::KeychainPepperPromptRequest`, then dispatches
//! the response via this shim. Keychain access stays Dart-side
//! because the Flutter plugin already audits that entry point
//! and there is no native Rust crate covering every target
//! platform's keychain backend.

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

/// L2 keychain-password gate verify — composes disk-blob
/// read + keychain-pepper prompt round-trip + HMAC compare
/// into one async FRB call. Returns `Ok(true)` on a match,
/// `Ok(false)` for every other outcome (file missing /
/// corrupt blob / pepper missing / HMAC mismatch / cancelled
/// prompt). `Err` is reserved for unrecoverable filesystem
/// errors.
///
/// Caller is the Dart unlock dialog; the Dart subscriber for
/// `BusEvent::KeychainPepperPromptRequest` performs the
/// `flutter_secure_storage.read` call after seeing the
/// request and dispatches the response via
/// [`keychain_pepper_prompt_resolve`].
pub async fn keychain_password_gate_verify(
    support_dir: String,
    password: String,
) -> Result<bool, String> {
    use lfs_core::security::keychain_password_gate_actor::verify_password;
    let path = std::path::PathBuf::from(support_dir);
    verify_password(&path, &password).await
}
