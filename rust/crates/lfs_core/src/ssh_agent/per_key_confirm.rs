//! Per-key confirmation gate.
//!
//! Routes every agent SIGN_REQUEST that hits a key with
//! `agent_policy = 'ask'` through a Flutter confirmation dialog,
//! mirroring `ssh-add -c` semantics. Three policy values cover the
//! whole matrix:
//!
//! - `'always'` — skip the gate; sign directly. The hardware
//!   backend's own touch / PIN prompt still fires when the
//!   credential carries a user-verification bit.
//! - `'ask'` — default. Park a oneshot, dispatch a `Pending` record
//!   through the [`crate::bus::EventBus`] under the
//!   [`crate::bus::EventTopic::SshAgent`] topic, wait for the Dart
//!   side to resolve via [`respond_to_request`].
//! - `'deny'` — refuse without prompting. The endpoint surfaces
//!   `SSH_AGENT_FAILURE` so the external client gives up cleanly.
//!
//! ## Where the dialog runs
//!
//! Pure orchestration here. The Dart side mounts a sibling of
//! `HardwareKeyPromptDialog` (`AgentSignatureRequestDialog`) when
//! it sees a new event on the bus topic, calls
//! [`crate::ssh_agent::per_key_confirm::respond_to_request`]
//! through the FRB shim with the user's verdict, and we route the
//! verdict back to the parked oneshot. The Rust side stays
//! UI-agnostic — running on a headless target (CI, integration
//! tests) drops the bus event on the floor and the gate defaults
//! to `Decision::Deny` after [`PROMPT_TIMEOUT`].
//!
//! ## Cancellation
//!
//! External client disconnects mid-prompt -> the sign future
//! drops, the oneshot is dropped, the awaiting half observes a
//! channel-closed error and reports `Decision::Deny`. The Dart
//! side gets a separate `Cancelled` event so the dialog can close
//! itself without the user having to click anything.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use tokio::sync::oneshot;
use uuid::Uuid;

/// Maximum time the gate parks the signer before defaulting to
/// `Deny`. Conservative: external SSH clients have their own
/// connect timeouts (OpenSSH default 120s); we want to be the
/// shorter of the two so the dialog never sits in front of the
/// user after the client already moved on.
pub const PROMPT_TIMEOUT: Duration = Duration::from_secs(60);

/// Three possible verdicts the gate can surface.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    /// Sign this one request. Don't change the stored policy.
    AuthorizeOnce,
    /// Sign this request AND flip the stored policy on the key row
    /// to `'always'` so future requests skip the prompt. The
    /// caller is responsible for persisting the policy update.
    AuthorizeAndRemember,
    /// Refuse this request. Don't change the stored policy. The
    /// next request prompts again unless the user opens Settings
    /// to flip the policy to `'deny'`.
    Deny,
}

/// One pending request waiting on the user. The endpoint mints an
/// id, posts this record on the bus topic, then awaits the
/// matching response on the parked oneshot.
#[derive(Debug, Clone)]
pub struct PendingPrompt {
    /// Opaque correlation id. Returned by [`enqueue`] so the
    /// endpoint can route the Dart response back to the right
    /// oneshot, and serialised onto the bus event so the dialog
    /// knows which request it is rendering.
    pub request_id: String,
    /// Stored key id (`ssh_keys.id`). Drives the "key label"
    /// rendered in the dialog header.
    pub key_id: String,
    /// Human-readable label captured at import. Goes verbatim
    /// into the dialog body.
    pub key_label: String,
    /// Best-effort name of the external SSH client that issued
    /// the request. `Some("git")` / `Some("ssh")` /
    /// `Some("code")` on platforms that expose peer-process info
    /// (Linux SO_PEERCRED, Windows `GetNamedPipeClientProcessId`);
    /// `None` on macOS — the BSD `getpeereid` returns uid/gid only,
    /// not a pid we could resolve back to a process name.
    pub requester: Option<String>,
}

/// Process-singleton parking lot for in-flight prompts.
///
/// Entries land here when the agent endpoint awaits a verdict and
/// leave when the Dart side resolves through
/// [`respond_to_request`]. We keep the lot in a plain `Mutex<...>`
/// — tokio `RwLock` adds no value at this contention level (one
/// SIGN_REQUEST at a time per external client, and humans don't
/// click faster than the lock can spin) and the explicit lock keeps
/// the synchronous Dart-resolved path off the async runtime.
struct PromptLot {
    pending: HashMap<String, oneshot::Sender<Decision>>,
}

static LOT: OnceLock<Mutex<PromptLot>> = OnceLock::new();

fn lot() -> &'static Mutex<PromptLot> {
    LOT.get_or_init(|| {
        Mutex::new(PromptLot {
            pending: HashMap::new(),
        })
    })
}

/// Park a new prompt. Returns the request id (for serialising
/// onto the bus event) and the receiver the endpoint awaits on.
///
/// The caller is responsible for dropping the receiver if the
/// upstream signer future is cancelled — the matching sender
/// will then resolve to `Err(RecvError)` which the receive side
/// treats as `Decision::Deny`.
pub fn enqueue(key_id: &str, key_label: &str, requester: Option<String>) -> PendingPrompt {
    let request_id = Uuid::new_v4().to_string();
    let (tx, _rx) = oneshot::channel::<Decision>();
    // Stash the sender — the receiver half is handed to the
    // caller through [`await_decision`], not this struct, so the
    // endpoint can pick up the wait without holding the lot's
    // mutex across an await.
    let mut g = lot().lock().unwrap_or_else(|e| e.into_inner());
    g.pending.insert(request_id.clone(), tx);
    PendingPrompt {
        request_id,
        key_id: key_id.to_string(),
        key_label: key_label.to_string(),
        requester,
    }
}

/// Park a prompt and return the matching receiver in one shot.
/// Convenience for the agent endpoint — `enqueue` separates the
/// observable record (what goes on the bus) from the side-channel
/// (the oneshot), but the endpoint always wants both, so it
/// reaches for this helper.
pub fn enqueue_with_receiver(
    key_id: &str,
    key_label: &str,
    requester: Option<String>,
) -> (PendingPrompt, oneshot::Receiver<Decision>) {
    let request_id = Uuid::new_v4().to_string();
    let (tx, rx) = oneshot::channel::<Decision>();
    let mut g = lot().lock().unwrap_or_else(|e| e.into_inner());
    g.pending.insert(request_id.clone(), tx);
    (
        PendingPrompt {
            request_id,
            key_id: key_id.to_string(),
            key_label: key_label.to_string(),
            requester,
        },
        rx,
    )
}

/// Resolve a pending prompt. Called by the FRB shim once Dart
/// hands back the user's verdict. `Ok(())` if a matching entry
/// was found and the verdict landed; `Err` if the id never
/// existed or the awaiting half already dropped (typical when the
/// external client disconnected mid-prompt and the gate timed
/// out).
pub fn respond_to_request(request_id: &str, decision: Decision) -> Result<(), &'static str> {
    let mut g = lot().lock().unwrap_or_else(|e| e.into_inner());
    let Some(tx) = g.pending.remove(request_id) else {
        return Err("no pending request with this id");
    };
    tx.send(decision)
        .map_err(|_| "awaiting half dropped (caller disconnected)")
}

/// Drop a parked prompt without resolving it. The FRB shim calls
/// this on a Dart-side cancel button — distinct from
/// `respond_to_request(Deny)` so the dialog UX can differentiate
/// "user pressed Deny" from "external client gave up first" in
/// telemetry.
pub fn cancel_request(request_id: &str) {
    let mut g = lot().lock().unwrap_or_else(|e| e.into_inner());
    g.pending.remove(request_id);
}

/// Snapshot count of pending prompts. Test-only — the endpoint
/// surfaces no count to Dart (each event drives its own dialog).
#[cfg(test)]
pub fn pending_count() -> usize {
    let g = lot().lock().unwrap_or_else(|e| e.into_inner());
    g.pending.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn enqueue_then_respond_resolves_receiver() {
        let (prompt, rx) = enqueue_with_receiver("k1", "Lab key", Some("git".into()));
        assert_eq!(prompt.key_id, "k1");
        respond_to_request(&prompt.request_id, Decision::AuthorizeOnce).unwrap();
        let decision = rx.await.unwrap();
        assert_eq!(decision, Decision::AuthorizeOnce);
    }

    #[tokio::test]
    async fn cancel_drops_pending_entry() {
        let prompt = enqueue("k2", "Lab key", None);
        assert!(pending_count() >= 1);
        cancel_request(&prompt.request_id);
        // Re-responding now fails — entry is gone.
        let res = respond_to_request(&prompt.request_id, Decision::AuthorizeOnce);
        assert!(res.is_err());
    }

    #[tokio::test]
    async fn dropping_receiver_makes_respond_fail() {
        let (prompt, rx) = enqueue_with_receiver("k3", "Lab key", None);
        drop(rx);
        let res = respond_to_request(&prompt.request_id, Decision::AuthorizeOnce);
        assert!(res.is_err());
    }

    #[test]
    fn respond_unknown_id_fails() {
        let res = respond_to_request("not-a-real-uuid", Decision::Deny);
        assert!(res.is_err());
    }
}
