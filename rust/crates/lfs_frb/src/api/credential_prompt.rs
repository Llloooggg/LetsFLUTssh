//! FRB adapter for `lfs_core::security::credential_prompt`.
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_submit_on_unknown_id_returns_false() {
        // No registered prompt for this id — the resolve must
        // surface `false` rather than panic so the Dart wrapper's
        // "best-effort dispatch" call doesn't crash on a stale
        // prompt id.
        assert!(!credential_prompt_resolve_submit(
            "ghost-prompt-id".into(),
            b"secret".to_vec(),
            false
        ));
    }

    #[test]
    fn resolve_cancel_on_unknown_id_returns_false() {
        assert!(!credential_prompt_resolve_cancel("ghost-prompt-id".into()));
    }

    #[test]
    fn cancel_on_unknown_id_is_idempotent() {
        // Cancel-without-resolve is fire-and-forget; a missing id
        // must not panic.
        credential_prompt_cancel("ghost-prompt-id".into());
    }
}
