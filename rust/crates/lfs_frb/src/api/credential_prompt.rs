//! FRB adapter for `lfs_core::security::credential_prompt`
//! (Decision 1 / A3 in `docs/RUST_MIGRATION_REMAINING.md`).
//!
//! Sync — every op is a small mutex acquire + oneshot send.
//! Dart subscriber renders the password / passphrase dialog
//! after seeing `BusEvent::CredentialPromptRequest`, then
//! dispatches the user's response via this shim.
//!
//! Plaintext discipline: `secret_bytes` crosses the FRB
//! boundary once on resolve. The Rust caller stages the bytes
//! into the SecretStore + zeroes the local `Vec` after use,
//! so the Dart heap drops the plaintext as soon as the FRB
//! call returns.

use lfs_core::security::credential_prompt::{self, CredentialResponse};

/// Resolve a pending credential prompt with the user's
/// Submit response. `secret_bytes` is the password /
/// passphrase the user typed. `remember_for_session` mirrors
/// the dialog checkbox — true = cache in the per-session
/// SecretStore slot so reconnects skip the dialog.
///
/// Returns `true` when a receiver was actually woken; `false`
/// for an unknown / already-resolved prompt id.
#[flutter_rust_bridge::frb(sync)]
pub fn credential_prompt_resolve_submit(
    prompt_id: String,
    secret_bytes: Vec<u8>,
    remember_for_session: bool,
) -> bool {
    credential_prompt::instance().resolve(
        &prompt_id,
        CredentialResponse::Submit {
            secret: secret_bytes,
            remember_for_session,
        },
    )
}

/// Resolve a pending credential prompt with a Cancel — user
/// dismissed the dialog or tapped Cancel. The connection
/// actor drops the connect attempt with a localised "auth
/// cancelled" error.
#[flutter_rust_bridge::frb(sync)]
pub fn credential_prompt_resolve_cancel(prompt_id: String) -> bool {
    credential_prompt::instance().resolve(&prompt_id, CredentialResponse::Cancel)
}

/// Cancel a pending prompt without resolving — the
/// connection actor side abandoned the await (peer drop,
/// shutdown). Idempotent on a missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn credential_prompt_cancel(prompt_id: String) {
    credential_prompt::instance().cancel(&prompt_id);
}
