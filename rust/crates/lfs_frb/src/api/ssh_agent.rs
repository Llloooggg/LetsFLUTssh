//! FRB adapter for the in-process ssh-agent endpoint
//! (`lfs_core::ssh_agent`). The Settings UI calls into these
//! shims to start / stop the listener, query status, and resolve
//! per-key confirmation prompts that arrive on
//! [`crate::api::bus::BusTopic::SshAgent`].

use crate::api::frb_err;

/// FRB mirror of [`lfs_core::ssh_agent::AgentStatus`]. Read-only
/// snapshot the Settings UI polls to render the on/off badge +
/// "SSH_AUTH_SOCK" copy area.
#[derive(Debug, Clone)]
pub struct DbAgentStatus {
    /// True when the listener task is bound + accepting
    /// connections.
    pub running: bool,
    /// UDS path on Linux/macOS, named pipe name on Windows.
    /// `None` when the endpoint is stopped or unsupported.
    pub socket_path: Option<String>,
    /// `true` on mobile (Android/iOS) builds — the platform
    /// fundamentally cannot host an agent socket. The Settings UI
    /// renders the toggle disabled with a reason rather than
    /// trying to start the endpoint.
    pub unsupported: bool,
}

impl From<lfs_core::ssh_agent::AgentStatus> for DbAgentStatus {
    fn from(s: lfs_core::ssh_agent::AgentStatus) -> Self {
        Self {
            running: s.running,
            socket_path: s.socket_path,
            unsupported: s.unsupported,
        }
    }
}

/// FRB mirror of [`lfs_core::ssh_agent::per_key_confirm::Decision`].
/// Wire-serialised as a String so the Dart side maps it onto an
/// enum without an extra generated mirror. Values: `"once"` /
/// `"always"` / `"deny"`.
#[derive(Debug, Clone)]
pub struct DbAgentDecision {
    pub kind: String,
}

/// Start the listener. Returns the socket path / pipe name so the
/// Settings UI can show the Copy button. Idempotent — a repeat
/// call returns the same path without spawning a second listener.
pub async fn ssh_agent_start() -> Result<String, String> {
    tokio::task::spawn_blocking(lfs_core::ssh_agent::start_endpoint)
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("spawn_blocking: {e}")))?
        .map_err(|e| frb_err::from_core(&e))
}

/// Stop the running listener. No-op when the endpoint is not
/// running.
pub async fn ssh_agent_stop() -> Result<(), String> {
    tokio::task::spawn_blocking(lfs_core::ssh_agent::stop)
        .await
        .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("spawn_blocking: {e}")))
}

/// Read the live endpoint status. Synchronous — the inner state is
/// behind a Mutex and the read is microseconds.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn ssh_agent_status() -> DbAgentStatus {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        DbAgentStatus::from(lfs_core::ssh_agent::status())
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        DbAgentStatus {
            running: false,
            socket_path: None,
            unsupported: true,
        }
    }
}

/// Resolve a pending signature prompt. Called by the Settings UI's
/// `AgentSignatureRequestDialog` once the user picks
/// `Authorize once` / `Authorize and remember` / `Deny`.
///
/// `decision` is one of the strings `DbAgentDecision::kind` carries:
/// `"once"` -> [`lfs_core::ssh_agent::per_key_confirm::Decision::AuthorizeOnce`],
/// `"always"` -> `AuthorizeAndRemember`, anything else (including
/// `"deny"`) -> `Deny`. Errors when the id doesn't match a parked
/// prompt — typically because the external client disconnected
/// first and the gate already timed out.
pub fn ssh_agent_respond_to_signature_request(
    request_id: String,
    decision: DbAgentDecision,
) -> Result<(), String> {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        use lfs_core::ssh_agent::per_key_confirm::{respond_to_request, Decision};
        let d = match decision.kind.as_str() {
            "always" => Decision::AuthorizeAndRemember,
            "once" => Decision::AuthorizeOnce,
            _ => Decision::Deny,
        };
        respond_to_request(&request_id, d).map_err(|e| frb_err::wire(frb_err::kind::GENERIC, e))
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        let _ = (request_id, decision);
        Err(frb_err::wire(
            frb_err::kind::UNSUPPORTED,
            "ssh-agent endpoint is not available on mobile targets",
        ))
    }
}

/// Drop a parked prompt without resolving. Called by the Settings
/// UI when the dialog dismisses (Escape / route pop / sign-in
/// timeout dismissed) — distinct from `respond(Deny)` so telemetry
/// can differentiate "user actively denied" from "user walked
/// away".
pub fn ssh_agent_cancel_signature_request(request_id: String) {
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    {
        lfs_core::ssh_agent::per_key_confirm::cancel_request(&request_id);
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        let _ = request_id;
    }
}

/// Update the persisted per-key dispatch policy. The Settings UI
/// surfaces a per-key dropdown (`Always` / `Ask` / `Deny`) in the
/// key manager + each in-prompt "remember this" choice flips here.
pub async fn ssh_agent_update_key_policy(key_id: String, policy: String) -> Result<(), String> {
    use lfs_core::db::ssh_keys::AgentPolicy;
    let p = AgentPolicy::from_db(&policy);
    let key_id_clone = key_id.clone();
    let res = tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let db = app
            .db()
            .ok_or_else(|| lfs_core::error::Error::Db("DB not initialised".into()))?;
        db.with_conn(|c| {
            let mut row = lfs_core::db::ssh_keys::get(c, &key_id_clone)?.ok_or_else(|| {
                lfs_core::error::Error::Db(format!("key {key_id_clone} not found"))
            })?;
            row.agent_policy = p;
            lfs_core::db::ssh_keys::upsert(c, &row)
        })
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::GENERIC, &format!("spawn_blocking: {e}")))?
    .map_err(|e| frb_err::from_core(&e));
    if res.is_ok() {
        // Policy update flips `ssh_keys.agent_policy` — publish so the
        // key-manager dropdown re-renders against the canonical row.
        lfs_core::keys::notify_changed(&lfs_core::app::instance());
    }
    res
}
