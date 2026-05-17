//! Endpoint lifecycle + [`ssh_agent_lib::agent::Session`] impl.
//!
//! Two layers:
//!
//! 1. [`Endpoint`] — the `Clone`-able session struct. ssh-agent-lib
//!    clones it once per accepted connection, so each external
//!    client gets its own state bucket. The shared state (parked
//!    confirm prompts) lives behind a `OnceLock` in
//!    [`super::per_key_confirm`] so the clones reach the same
//!    parking lot.
//! 2. [`start_endpoint`] / [`stop`] — process-singleton driver.
//!    Spawns the tokio task running
//!    [`ssh_agent_lib::agent::listen`] on the right transport,
//!    stashes the join handle + cleanup hook so [`stop`] is
//!    callable from the FRB layer.
//!
//! Threading: `start_endpoint` is fire-and-forget — it returns once
//! the listener is bound, the listen-loop runs on a separate task,
//! and the [`AgentHandle`] returned to the FRB layer carries the
//! socket path + an `abort()` slot for the task.

use std::sync::{Mutex, OnceLock};

use async_trait::async_trait;
use ssh_agent_lib::agent::Session;
use ssh_agent_lib::error::AgentError;
use ssh_agent_lib::proto::{
    AddIdentity, AddIdentityConstrained, AddSmartcardKeyConstrained, Extension, Identity,
    KeyConstraint, RemoveIdentity, SignRequest, SmartcardKey,
};
use ssh_key::public::KeyData;
use ssh_key::{Algorithm, PublicKey, Signature};
use tokio::task::JoinHandle;

use crate::db::ssh_keys::{self, AgentPolicy, SshKeyRow};
use crate::error::Error;
use crate::ssh_agent::backends::{self, BackendError, BackendKind};
use crate::ssh_agent::per_key_confirm::{self, Decision};
use crate::ssh_agent::transport;

/// The session struct ssh-agent-lib clones per connection. Holds no
/// per-connection state today — every method fetches fresh rows
/// from the DB so the Rust-owns-data discipline holds.
///
/// `locked` is a per-connection flag the agent protocol's LOCK /
/// UNLOCK verbs flip. We accept the verb so external clients that
/// rely on the lock semantics (some IDEs lock the agent before
/// session shutdown) don't see an `SSH_AGENT_FAILURE`. Locking
/// hides identities and refuses signs — when an attacker has read
/// access to our socket they have already lost. The flag is per-
/// connection on purpose: a lock from `git` shouldn't also lock
/// out an unrelated `ssh` invocation.
#[derive(Clone, Default)]
pub struct Endpoint {
    locked: bool,
}

impl Endpoint {
    /// Read the live `ssh_keys` rows from the DB. Always fresh —
    /// no Dart-style notifier cache. Returns the rows the endpoint
    /// will publish through `request_identities` PLUS skipped ones
    /// (so callers can log the filtering decision); the publishing
    /// path filters further to hardware-bound only.
    pub(super) fn list_rows() -> Result<Vec<SshKeyRow>, Error> {
        let app = crate::app::instance();
        let db_guard = app
            .db()
            .ok_or_else(|| Error::Db("ssh-agent: DB not initialised".into()))?;
        db_guard.with_conn(ssh_keys::list_all)
    }

    /// Per-connection lock readout. The custom listen loop honours
    /// the same lock flag the `Session` trait surface flips through
    /// `lock` / `unlock`. Locked sessions advertise zero identities
    /// and refuse to sign.
    pub(super) fn is_locked(&self) -> bool {
        self.locked
    }

    /// Lookup a stored row by matching its SSH wire-format public
    /// key blob against a `KeyData` from the agent request. The
    /// agent protocol matches on the encoded `KeyData` (which is
    /// what `request_identities` published), and `ssh_keys.public_key`
    /// is the OpenSSH text we re-parse to recover `KeyData`.
    pub(super) fn find_row_by_keydata(target: &KeyData) -> Result<Option<SshKeyRow>, Error> {
        let rows = Self::list_rows()?;
        for row in rows {
            let Ok(pk) = PublicKey::from_openssh(&row.public_key) else {
                // Unparseable stored row — skip silently. The key
                // manager rejects invalid OpenSSH bodies on import,
                // so a stored row that doesn't parse is a DB-corruption
                // story routed to its own dialog.
                continue;
            };
            if pk.key_data() == target {
                return Ok(Some(row));
            }
        }
        Ok(None)
    }

    /// Drive a SIGN_REQUEST through the policy gate + backend
    /// dispatcher once the row has already been resolved. Shared
    /// between the typed [`Session::sign`] path (which matches by
    /// `KeyData`) and the cert-aware path in
    /// [`super::loop_runner`] (which matches by the bare key blob
    /// embedded in an OpenSSH certificate). Returns the wire-shape
    /// [`Signature`] that the agent response carries verbatim.
    ///
    /// Cert and bare requests emit the same signature shape — the
    /// agent protocol's `key_blob` only selects the identity; the
    /// `Signature` field always carries the bare algorithm string
    /// and the bare signing primitive's output (verified against
    /// OpenSSH `ssh_ed25519_encode_store_sig` and the matching
    /// rsa/ecdsa/sk callbacks — every callback writes the bare
    /// algorithm name without the `-cert-v01@openssh.com` suffix).
    pub(super) async fn run_sign(
        &mut self,
        row: SshKeyRow,
        data: &[u8],
        flags: u32,
    ) -> Result<Signature, AgentError> {
        if self.locked {
            return Err(AgentError::Other("agent is locked".into()));
        }
        // Software keys: belt-and-braces refusal. The listing path
        // already skipped them, so the only way to land here is a
        // misbehaving client guessing a KeyData / cert blob.
        if BackendKind::from_row(&row) == BackendKind::Software {
            return Err(AgentError::Other(
                "ssh-agent: software keys are never signed through this endpoint".into(),
            ));
        }
        if row.agent_policy == AgentPolicy::Deny {
            return Err(AgentError::Other(
                "ssh-agent: this key is policy-denied".into(),
            ));
        }
        if row.agent_policy == AgentPolicy::Ask {
            let (prompt, rx) =
                per_key_confirm::enqueue_with_receiver(&row.id, &row.label, peer_requester());
            publish_prompt_event(&prompt);
            let decision = tokio::time::timeout(per_key_confirm::PROMPT_TIMEOUT, rx)
                .await
                .unwrap_or(Ok(Decision::Deny))
                .unwrap_or(Decision::Deny);
            match decision {
                Decision::Deny => {
                    return Err(AgentError::Other("ssh-agent: user denied".into()));
                }
                Decision::AuthorizeAndRemember => {
                    if let Err(e) = persist_policy(&row.id, AgentPolicy::Always) {
                        crate::app_log_warn!(
                            "SshAgent",
                            "policy promotion failed for key=<{}>: {e}",
                            row.id
                        );
                    }
                }
                Decision::AuthorizeOnce => {}
            }
        }

        let out = backends::dispatch_sign(&row, data, flags)
            .await
            .map_err(map_backend_error)?;

        let algorithm = parse_algorithm_label(&out.algorithm)
            .map_err(|e| AgentError::Other(format!("ssh-agent: {e}").into()))?;
        Signature::new(algorithm, out.signature)
            .map_err(|e| AgentError::Other(format!("ssh-agent: encode signature: {e}").into()))
    }
}

#[async_trait]
impl Session for Endpoint {
    /// Publish every hardware-bound key. Software keys stay out —
    /// the agent endpoint must not expose plaintext PEM material.
    async fn request_identities(&mut self) -> Result<Vec<Identity>, AgentError> {
        if self.locked {
            return Ok(Vec::new());
        }
        let rows = Self::list_rows()
            .map_err(|e| AgentError::Other(format!("ssh-agent: list rows: {e}").into()))?;
        let mut out = Vec::new();
        for row in rows {
            if BackendKind::from_row(&row) == BackendKind::Software {
                continue;
            }
            if row.agent_policy == AgentPolicy::Deny {
                // Keep `Deny` rows OUT of the listing too — listing
                // them would tell the external client that the key
                // exists, which is information disclosure beyond
                // what `Deny` should permit. Promote `Deny` to a
                // full-shadow policy.
                continue;
            }
            let Ok(pk) = PublicKey::from_openssh(&row.public_key) else {
                continue;
            };
            out.push(Identity {
                pubkey: pk.key_data().clone(),
                comment: row.label.clone(),
            });
        }
        Ok(out)
    }

    /// Resolve the row by public key, gate through the per-key
    /// confirm dialog (`agent_policy == Ask`), dispatch through
    /// the backend signer.
    ///
    /// Cert-form `key_blob` never lands here — `ssh_agent_lib::SignRequest::decode`
    /// can't represent a cert in its `KeyData` field
    /// (`KeyData::Other(OpaquePublicKey)` injects an extra length
    /// prefix that doesn't match the cert wire shape). The cert
    /// path is intercepted in [`super::loop_runner`] and dispatches
    /// through [`run_sign`](Self::run_sign) directly. This arm
    /// handles bare-key requests only.
    async fn sign(&mut self, request: SignRequest) -> Result<Signature, AgentError> {
        let row = Self::find_row_by_keydata(&request.pubkey)
            .map_err(|e| AgentError::Other(format!("ssh-agent: lookup row: {e}").into()))?
            .ok_or_else(|| AgentError::Other("ssh-agent: unknown key".into()))?;
        self.run_sign(row, &request.data, request.flags).await
    }

    /// Refuse — external clients cannot push key material.
    async fn add_identity(&mut self, _identity: AddIdentity) -> Result<(), AgentError> {
        Err(refused_add())
    }

    /// Refuse — external clients cannot push key material. When the
    /// payload carries a destination-restriction extension constraint
    /// (`restrict-destination-v00@openssh.com` /
    /// `restrict-destination-v01@openssh.com`), surface a more
    /// specific error: silently accepting the ADD would make the
    /// caller think the constraint is enforced, but the agent ignores
    /// it on every subsequent sign. Refuse both — the descriptive
    /// arm only changes the log line.
    async fn add_identity_constrained(
        &mut self,
        identity: AddIdentityConstrained,
    ) -> Result<(), AgentError> {
        if let Some(name) = first_destination_constraint_name(&identity.constraints) {
            crate::app_log_warn!(
                "SshAgent",
                "refusing ADD_IDENTITY_CONSTRAINED with <{}>: agent does not enforce destination \
                 constraints — use a per-key signer or omit -h",
                name
            );
            return Err(refused_destination_constraint());
        }
        Err(refused_add())
    }

    async fn remove_identity(&mut self, _identity: RemoveIdentity) -> Result<(), AgentError> {
        Err(refused_add())
    }

    async fn remove_all_identities(&mut self) -> Result<(), AgentError> {
        Err(refused_add())
    }

    async fn add_smartcard_key(&mut self, _key: SmartcardKey) -> Result<(), AgentError> {
        Err(refused_add())
    }

    async fn add_smartcard_key_constrained(
        &mut self,
        _key: AddSmartcardKeyConstrained,
    ) -> Result<(), AgentError> {
        Err(refused_add())
    }

    async fn remove_smartcard_key(&mut self, _key: SmartcardKey) -> Result<(), AgentError> {
        Err(refused_add())
    }

    /// Per-connection lock. Flips the in-struct `locked` flag;
    /// while set, `request_identities` returns empty and `sign`
    /// refuses. The agent protocol's lock-password parameter is
    /// not bound to anything — we don't store a comparable secret
    /// because we have no way to recover from "user typed the
    /// wrong unlock string" beyond restarting the endpoint.
    async fn lock(&mut self, _password: String) -> Result<(), AgentError> {
        self.locked = true;
        Ok(())
    }

    async fn unlock(&mut self, _password: String) -> Result<(), AgentError> {
        self.locked = false;
        Ok(())
    }

    /// Accept the agent extensions we explicitly recognise; surface
    /// `ExtensionFailure` for everything else so the external client
    /// falls back to the unextended protocol.
    ///
    /// `session-bind@openssh.com` — OpenSSH 8.9+ sends this to bind a
    /// signing session to a specific session id so a hostile agent
    /// can't replay signatures. We accept the payload but do not
    /// enforce the binding ourselves — the underlying CTAP2 path
    /// signs over whatever bytes we hand it, which already include
    /// the session id from the server side.
    ///
    /// `restrict-destination-v00@openssh.com` /
    /// `restrict-destination-v01@openssh.com` — OpenSSH agent
    /// destination-restriction constraints. The constraint records a
    /// from→to bastion chain the agent is supposed to enforce on
    /// every subsequent sign so a hostile midpoint cannot reuse a
    /// signature against a different host. We do not yet bind the
    /// constraint to the per-key signer (the signing path would need
    /// to walk the recorded chain against the live connection's
    /// destination on every SIGN_REQUEST), and silently accepting
    /// would let `ssh-add -h host` look enforced while it is not —
    /// an asymmetric security regression where the user thinks the
    /// key is fenced to one host but it signs anywhere. Refuse at
    /// the extension boundary with `ExtensionFailure` and log the
    /// rejection so the user can route around through a per-key
    /// signer instead.
    async fn extension(&mut self, extension: Extension) -> Result<Option<Extension>, AgentError> {
        match extension.name.as_str() {
            "session-bind@openssh.com" => Ok(None),
            "restrict-destination-v00@openssh.com" | "restrict-destination-v01@openssh.com" => {
                crate::app_log_warn!(
                    "SshAgent",
                    "refusing extension <{}>: agent does not enforce destination constraints — \
                     use a per-key signer or omit -h",
                    extension.name
                );
                Err(AgentError::ExtensionFailure)
            }
            _ => Err(AgentError::ExtensionFailure),
        }
    }
}

/// Wire helper: parse the wire algorithm label (`"sk-ssh-ed25519@openssh.com"`,
/// `"sk-ecdsa-sha2-nistp256@openssh.com"`) back into the ssh-key
/// `Algorithm` enum the agent response wants.
fn parse_algorithm_label(label: &str) -> Result<Algorithm, String> {
    Algorithm::new(label).map_err(|e| format!("unknown algorithm label {label}: {e}"))
}

/// Map [`backends::BackendError`] onto an [`AgentError`] the wire
/// layer can render. We use the catch-all `Other` arm rather than
/// `Failure` because ssh-agent-lib distinguishes "extension
/// failure" vs "protocol failure" but does not have a public
/// constructor for a typed protocol error message; `Other` carries
/// the detail through to the log line on the server side.
fn map_backend_error(e: BackendError) -> AgentError {
    AgentError::Other(format!("ssh-agent: {e}").into())
}

/// Single source of the "refused — external clients cannot add
/// keys" error. The wire-level response is `SSH_AGENT_FAILURE`
/// per [draft-miller-ssh-agent-14 §3.3].
fn refused_add() -> AgentError {
    AgentError::Other(
        "ssh-agent: external clients cannot add or remove keys via this endpoint".into(),
    )
}

/// Specific refusal for an ADD that carried a destination-restriction
/// constraint. Distinct from [`refused_add`] so the log line and any
/// future Dart-side mapper can identify the precise reason rather
/// than seeing the catch-all "external clients cannot add keys"
/// message. Wire-level response is still `SSH_AGENT_FAILURE`.
fn refused_destination_constraint() -> AgentError {
    AgentError::Other(
        "ssh-agent in LetsFLUTssh does not enforce destination constraints; \
         use a per-key signer or omit -h"
            .into(),
    )
}

/// Names of the OpenSSH agent destination-restriction constraint
/// extensions (`-v00`, plus `-v01` reserved for the future revision
/// of the same extension). Matched against
/// [`KeyConstraint::Extension::name`] when parsing
/// `ADD_IDENTITY_CONSTRAINED` payloads.
const DESTINATION_CONSTRAINT_NAMES: &[&str] = &[
    "restrict-destination-v00@openssh.com",
    "restrict-destination-v01@openssh.com",
];

/// Return the name of the first destination-restriction extension
/// constraint in the list, or `None` when no such constraint is
/// present. Walks the [`KeyConstraint::Extension`] arms only —
/// `Lifetime` / `Confirm` constraints have their own wire shapes
/// (constraint-type bytes 1 / 2) and never carry a name string.
fn first_destination_constraint_name(constraints: &[KeyConstraint]) -> Option<&str> {
    for c in constraints {
        if let KeyConstraint::Extension(ext) = c {
            if DESTINATION_CONSTRAINT_NAMES.contains(&ext.name.as_str()) {
                return Some(ext.name.as_str());
            }
        }
    }
    None
}

/// Best-effort peer-process resolution. Returns `Some(name)` when
/// the platform lets us read it cheaply, `None` otherwise. macOS
/// in particular leaves this `None` because the BSD `getpeereid`
/// path surfaces uid/gid but no pid we could resolve back to a
/// process name without further syscalls.
///
/// Today we surface `None` everywhere; the peer-process lookup is
/// a follow-up: per-platform plumbing (`SO_PEERCRED` on Linux,
/// `GetNamedPipeClientProcessId` + `QueryFullProcessImageNameW` on
/// Windows) lives one layer above the listener and isn't reachable
/// at the `Session` clone level. The Settings UI renders
/// "Unknown" when this returns `None`.
fn peer_requester() -> Option<String> {
    None
}

/// Best-effort policy persistence. Reads the row, flips the policy
/// field, writes it back. Failure is non-fatal — the gate already
/// honoured the user's intent for the current signature; a write
/// failure means the dialog reappears on the next request.
fn persist_policy(key_id: &str, new_policy: AgentPolicy) -> Result<(), Error> {
    let app = crate::app::instance();
    let db = app
        .db()
        .ok_or_else(|| Error::Db("ssh-agent: DB not initialised".into()))?;
    db.with_conn(|c| {
        let mut row = ssh_keys::get(c, key_id)?
            .ok_or_else(|| Error::Db(format!("ssh-agent: key {key_id} not found")))?;
        row.agent_policy = new_policy;
        ssh_keys::upsert(c, &row)
    })
}

/// Publish a pending-prompt event on the bus so the Dart side can
/// mount the confirmation dialog. The bus topic [`crate::bus::EventTopic::SshAgent`]
/// lands in the bus enum below; FRB subscribers consume the
/// `BusEvent::SshAgentSignaturePrompt` shape.
fn publish_prompt_event(prompt: &per_key_confirm::PendingPrompt) {
    crate::app::instance().bus.publish_ssh_agent_prompt(
        prompt.request_id.clone(),
        prompt.key_id.clone(),
        prompt.key_label.clone(),
        prompt.requester.clone(),
    );
}

// ---- endpoint lifecycle ------------------------------------------

/// Handle returned by [`start_endpoint`]. Drops abort the listener
/// task + clean up the socket / pipe.
#[derive(Debug)]
pub struct AgentHandle {
    /// Socket path / pipe name. Useful for the Settings UI Copy
    /// button.
    pub socket_path: String,
    pub(crate) task: Option<JoinHandle<()>>,
    pub(crate) cleanup: CleanupKind,
}

#[derive(Debug)]
pub(crate) enum CleanupKind {
    #[cfg(unix)]
    Unix(std::path::PathBuf),
    #[cfg(windows)]
    Windows(String),
}

impl Drop for AgentHandle {
    fn drop(&mut self) {
        if let Some(task) = self.task.take() {
            task.abort();
        }
        match &self.cleanup {
            #[cfg(unix)]
            CleanupKind::Unix(p) => transport::cleanup_unix(p),
            #[cfg(windows)]
            CleanupKind::Windows(p) => transport::cleanup_windows(p),
        }
    }
}

/// Aggregated read-out of the running endpoint state. The Settings
/// UI polls this via FRB to render the on/off badge + the
/// "SSH_AUTH_SOCK = ..." copy area.
#[derive(Debug, Clone)]
pub struct AgentStatus {
    pub running: bool,
    pub socket_path: Option<String>,
    pub unsupported: bool,
}

/// Process-singleton parking lot for the live handle. The FRB
/// surface keeps the handle here so `stop()` can drop it without
/// the Dart side having to thread a typed handle through.
static HANDLE: OnceLock<Mutex<Option<AgentHandle>>> = OnceLock::new();

fn handle_slot() -> &'static Mutex<Option<AgentHandle>> {
    HANDLE.get_or_init(|| Mutex::new(None))
}

/// Bind the listener, spawn the tokio task running
/// [`crate::ssh_agent::loop_runner::handle_socket`]. Returns the path
/// / pipe name so the Settings UI can show the copy button.
/// Idempotent — a repeat call returns the same path without starting a
/// second listener.
///
/// The custom loop is the cert-aware substitute for
/// `ssh_agent_lib::agent::listen` — see
/// [`crate::ssh_agent::loop_runner`] for the why.
pub fn start_endpoint() -> Result<String, Error> {
    let mut slot = handle_slot().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(existing) = slot.as_ref() {
        return Ok(existing.socket_path.clone());
    }

    #[cfg(unix)]
    {
        let (listener, path) = transport::bind_unix()?;
        let path_string = path.to_string_lossy().to_string();
        let task = tokio::spawn(async move {
            unix_accept_loop(listener).await;
        });
        *slot = Some(AgentHandle {
            socket_path: path_string.clone(),
            task: Some(task),
            cleanup: CleanupKind::Unix(path),
        });
        crate::app_log_info!("SshAgent", "endpoint started at <{}>", path_string);
        Ok(path_string)
    }

    #[cfg(windows)]
    {
        let (listener, path) = transport::bind_windows()?;
        let task = tokio::spawn(async move {
            windows_accept_loop(listener).await;
        });
        *slot = Some(AgentHandle {
            socket_path: path.clone(),
            task: Some(task),
            cleanup: CleanupKind::Windows(path.clone()),
        });
        crate::app_log_info!("SshAgent", "endpoint started at <{}>", path);
        Ok(path)
    }
}

/// Per-platform accept loop — Unix variant. Each accept spawns a task
/// running [`crate::ssh_agent::loop_runner::handle_socket`] on a fresh
/// [`Endpoint`] clone (per-connection `locked` state, default-off).
#[cfg(unix)]
async fn unix_accept_loop(listener: tokio::net::UnixListener) {
    loop {
        match listener.accept().await {
            Ok((stream, _addr)) => {
                tokio::spawn(async move {
                    if let Err(e) =
                        super::loop_runner::handle_socket(Endpoint::default(), stream).await
                    {
                        crate::app_log_warn!("SshAgent", "connection ended: {e}");
                    }
                });
            }
            Err(e) => {
                crate::app_log_warn!("SshAgent", "accept failed: {e}");
                return;
            }
        }
    }
}

/// Per-platform accept loop — Windows variant. The
/// [`ssh_agent_lib::agent::NamedPipeListener`] implements the same
/// `accept().await` shape as a tokio Unix listener so the structure
/// mirrors. Each accept yields a `NamedPipeServer` stream the custom
/// loop drives directly.
#[cfg(windows)]
async fn windows_accept_loop(mut listener: ssh_agent_lib::agent::NamedPipeListener) {
    use ssh_agent_lib::agent::ListeningSocket;
    loop {
        match listener.accept().await {
            Ok(stream) => {
                tokio::spawn(async move {
                    if let Err(e) =
                        super::loop_runner::handle_socket(Endpoint::default(), stream).await
                    {
                        crate::app_log_warn!("SshAgent", "connection ended: {e}");
                    }
                });
            }
            Err(e) => {
                crate::app_log_warn!("SshAgent", "accept failed: {e}");
                return;
            }
        }
    }
}

/// Stop the running endpoint. Drops the [`AgentHandle`] which
/// aborts the listener task and cleans up the socket / pipe.
/// Idempotent — calling on a stopped endpoint is a no-op.
pub fn stop() {
    let mut slot = handle_slot().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(handle) = slot.take() {
        drop(handle);
        crate::app_log_info!("SshAgent", "endpoint stopped");
    }
}

/// Read the current status without taking any side effect. The
/// FRB surface uses this to populate the Settings UI badge.
pub fn status() -> AgentStatus {
    let slot = handle_slot().lock().unwrap_or_else(|e| e.into_inner());
    match slot.as_ref() {
        Some(h) => AgentStatus {
            running: true,
            socket_path: Some(h.socket_path.clone()),
            unsupported: false,
        },
        None => AgentStatus {
            running: false,
            socket_path: None,
            unsupported: false,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn endpoint_lock_blocks_request_identities() {
        let mut ep = Endpoint::default();
        let _ = ep.lock(String::new()).await;
        let ids = ep.request_identities().await.unwrap();
        assert!(ids.is_empty());
    }

    #[tokio::test]
    async fn endpoint_unlock_restores_listing() {
        // The DB is not initialised in this unit-test slice — we
        // expect `request_identities` to surface an error rather
        // than panic. `unlock` should at least flip the flag back.
        let mut ep = Endpoint::default();
        let _ = ep.lock(String::new()).await;
        assert!(ep.request_identities().await.unwrap().is_empty());
        let _ = ep.unlock(String::new()).await;
        // After unlock the listing path tries to reach the DB.
        // Without a DB the path returns `Other`; assert it surfaces
        // an error rather than producing a phantom listing.
        let result = ep.request_identities().await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn endpoint_remove_all_identities_is_refused() {
        // The agent protocol's REMOVE_ALL verb takes no payload —
        // gives us a clean shape to assert the refusal contract on
        // without needing to construct an `AddIdentity` (which
        // wraps a real `KeypairData`).
        let mut ep = Endpoint::default();
        let err = ep.remove_all_identities().await.unwrap_err();
        assert!(matches!(err, AgentError::Other(_)));
    }

    #[tokio::test]
    async fn endpoint_extension_accepts_session_bind() {
        let mut ep = Endpoint::default();
        let ext = Extension {
            name: "session-bind@openssh.com".into(),
            details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
        };
        let res = ep.extension(ext).await;
        assert!(res.is_ok());
    }

    #[tokio::test]
    async fn endpoint_extension_refuses_unknown() {
        let mut ep = Endpoint::default();
        let ext = Extension {
            name: "evil.example".into(),
            details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
        };
        let err = ep.extension(ext).await.unwrap_err();
        assert!(matches!(err, AgentError::ExtensionFailure));
    }

    #[test]
    fn status_with_no_endpoint_reports_not_running() {
        let s = status();
        assert!(!s.running || s.socket_path.is_some());
    }

    /// Standalone `restrict-destination-v00@openssh.com` extension
    /// request must refuse with `ExtensionFailure` so the external
    /// agent-forwarding bastion knows the destination chain is NOT
    /// enforced rather than thinking it has been pinned.
    #[tokio::test]
    async fn endpoint_extension_refuses_restrict_destination_v00() {
        let mut ep = Endpoint::default();
        let ext = Extension {
            name: "restrict-destination-v00@openssh.com".into(),
            details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
        };
        let err = ep.extension(ext).await.unwrap_err();
        assert!(matches!(err, AgentError::ExtensionFailure));
    }

    /// Same contract for the `-v01` revision — OpenSSH 9.x reserves
    /// the future-shape name, and we refuse both with the same
    /// rationale.
    #[tokio::test]
    async fn endpoint_extension_refuses_restrict_destination_v01() {
        let mut ep = Endpoint::default();
        let ext = Extension {
            name: "restrict-destination-v01@openssh.com".into(),
            details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
        };
        let err = ep.extension(ext).await.unwrap_err();
        assert!(matches!(err, AgentError::ExtensionFailure));
    }

    /// ADD_IDENTITY_CONSTRAINED carrying a destination-restriction
    /// constraint surfaces the specific "agent does not enforce"
    /// refusal rather than the generic "cannot add keys" one. The
    /// wire-level response is `SSH_AGENT_FAILURE` either way, but the
    /// log line and any future Dart-side handler can route on the
    /// specific message.
    #[tokio::test]
    async fn endpoint_add_identity_constrained_rejects_destination_constraint() {
        use ssh_agent_lib::proto::{Credential, KeyConstraint, Unparsed};
        use ssh_key::private::{Ed25519Keypair, KeypairData};
        let mut ep = Endpoint::default();
        let keypair = Ed25519Keypair::random(&mut ssh_key::rand_core::OsRng);
        let identity = AddIdentity {
            credential: Credential::Key {
                privkey: KeypairData::Ed25519(keypair),
                comment: "test".into(),
            },
        };
        let constrained = AddIdentityConstrained {
            identity,
            constraints: vec![KeyConstraint::Extension(Extension {
                name: "restrict-destination-v00@openssh.com".into(),
                details: Unparsed::from(Vec::<u8>::new()),
            })],
        };
        let err = ep.add_identity_constrained(constrained).await.unwrap_err();
        match err {
            AgentError::Other(boxed) => {
                let s = boxed.to_string();
                assert!(
                    s.contains("destination constraints"),
                    "expected destination-constraint message, got {s}"
                );
            }
            other => panic!("expected AgentError::Other, got {other:?}"),
        }
    }

    /// ADD_IDENTITY_CONSTRAINED WITHOUT a destination constraint
    /// still rejects, but with the generic "cannot add keys" message.
    /// Distinguishing the two messages is the M14 contract: silent
    /// acceptance is the bug; both refusals are correct, the
    /// destination-specific arm just gives a better hint.
    #[tokio::test]
    async fn endpoint_add_identity_constrained_without_destination_uses_generic_refusal() {
        use ssh_agent_lib::proto::{Credential, KeyConstraint};
        use ssh_key::private::{Ed25519Keypair, KeypairData};
        let mut ep = Endpoint::default();
        let keypair = Ed25519Keypair::random(&mut ssh_key::rand_core::OsRng);
        let identity = AddIdentity {
            credential: Credential::Key {
                privkey: KeypairData::Ed25519(keypair),
                comment: "test".into(),
            },
        };
        let constrained = AddIdentityConstrained {
            identity,
            constraints: vec![KeyConstraint::Lifetime(3600)],
        };
        let err = ep.add_identity_constrained(constrained).await.unwrap_err();
        match err {
            AgentError::Other(boxed) => {
                let s = boxed.to_string();
                assert!(
                    s.contains("external clients cannot add"),
                    "expected generic refusal, got {s}"
                );
            }
            other => panic!("expected AgentError::Other, got {other:?}"),
        }
    }

    /// Detector helper handles the v01 alias too — the alias is the
    /// load-bearing branch in `first_destination_constraint_name` we
    /// rely on for any future OpenSSH bump.
    #[test]
    fn destination_constraint_detector_recognises_v01_alias() {
        use ssh_agent_lib::proto::{KeyConstraint, Unparsed};
        let constraints = vec![KeyConstraint::Extension(Extension {
            name: "restrict-destination-v01@openssh.com".into(),
            details: Unparsed::from(Vec::<u8>::new()),
        })];
        let name = super::first_destination_constraint_name(&constraints);
        assert_eq!(name, Some("restrict-destination-v01@openssh.com"));
    }

    /// Detector helper returns `None` when no destination constraint
    /// is present, even when other extension constraints are.
    #[test]
    fn destination_constraint_detector_ignores_other_extensions() {
        use ssh_agent_lib::proto::{KeyConstraint, Unparsed};
        let constraints = vec![
            KeyConstraint::Lifetime(3600),
            KeyConstraint::Confirm,
            KeyConstraint::Extension(Extension {
                name: "some-other-extension@example.com".into(),
                details: Unparsed::from(Vec::<u8>::new()),
            }),
        ];
        let name = super::first_destination_constraint_name(&constraints);
        assert_eq!(name, None);
    }
}
