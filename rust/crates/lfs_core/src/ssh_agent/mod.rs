//! In-process ssh-agent endpoint.
//!
//! Exposes the host's hardware-bound SSH keys (FIDO2 today; future
//! PKCS#11 / TPM / Secure Enclave / Windows NCrypt / Android Hardware
//! Keystore as those backends land) to every SSH-protocol-speaking
//! application running on the same machine — `git`, OpenSSH `ssh` /
//! `scp` / `sftp`, VS Code Remote-SSH, JetBrains Gateway, PuTTY 0.78+,
//! IDE plugins, CI runners.
//!
//! ## Why an in-process agent
//!
//! Without this endpoint a key imported through our key manager is
//! reachable only to our own connect path. Corporate workflows expect
//! a hardware-bound key on a host to work everywhere on that host:
//! `git push`, `scp`, IDE tooling all read `SSH_AUTH_SOCK` /
//! `\\.\pipe\openssh-ssh-agent` and dispatch through whatever agent
//! the user picked. Implementing the standard agent protocol lets our
//! keys plug into that ecosystem without us shipping a per-client
//! plugin per IDE.
//!
//! Symmetric position to the existing `connect_default_agent` path
//! (`crate::ssh::connect_default_agent`): we consume external agents
//! today; this module lets us BE an agent too.
//!
//! ## Architecture
//!
//! ```text
//!  external client (git / ssh / IDE)
//!         |
//!         |  ssh-agent wire protocol
//!         v
//!  ListeningSocket (UDS on Linux/macOS, NamedPipe on Windows)
//!         |
//!         v
//!  ssh_agent_lib::agent::listen()
//!         |
//!         v
//!  impl Session for Endpoint    [this module]
//!         |
//!         v
//!  backends::dispatch_sign(ssh_keys.backend)
//!         |
//!         +-> FidoSigner ............. (T-1, shipped)
//!         +-> Pkcs11Signer ........... (T-3)
//!         +-> TpmSigner .............. (T-4)
//!         +-> EnclaveSigner .......... (T-5)
//!         +-> HelloSigner ............ (T-6)
//!         +-> KeystoreSigner ......... (T-7)
//! ```
//!
//! The trait we implement is [`ssh_agent_lib::agent::Session`]. Its
//! method surface is the wire-protocol surface; we map the verbs we
//! support, refuse the verbs that would let an external client push
//! key material in, and translate sign requests through the per-
//! backend dispatcher in [`backends`].
//!
//! ## Security posture
//!
//! - **No add / remove**: `add_identity`, `add_identity_constrained`,
//!   `remove_identity`, `remove_all_identities`, `add_smartcard_key`,
//!   `add_smartcard_key_constrained`, `remove_smartcard_key` all
//!   return `SSH_AGENT_FAILURE`. Key material is added through our
//!   import flow, not the agent socket.
//! - **Software keys are never published**: only rows with
//!   `backend != 'software'` (initially `backend == 'fido2'`) appear
//!   in `request_identities`. Software-key signing keeps its own
//!   in-process path; exposing plaintext PEM-backed keys through the
//!   socket would be a regression on the security model.
//! - **Per-key confirm dialog**: every SIGN_REQUEST routes through
//!   [`per_key_confirm`] when the row's `agent_policy` is `'ask'`;
//!   `'always'` skips the dialog, `'deny'` returns failure outright.
//!   Mirrors `ssh-add -c` semantics.
//! - **UDS perms / pipe DACL**: the socket lives in a `0o700`
//!   parent directory on Linux/macOS; the named pipe is created
//!   with the default `first_pipe_instance(true)` DACL on Windows
//!   (current user SID + SYSTEM). See [`transport`].
//! - **Refuses ADD_IDENTITY** but accepts `session-bind@openssh.com`
//!   and `restrict-destination-v00@openssh.com` extensions (parsed
//!   by ssh-agent-lib transparently; we accept the payload).
//!
//! ## Lifecycle
//!
//! [`start_endpoint`] spawns a Tokio task running
//! [`ssh_agent_lib::agent::listen`]. The returned [`AgentHandle`]
//! owns the socket / pipe and a `JoinHandle` for the listener task.
//! Dropping the handle unlinks the UDS file + parent directory, or
//! closes the pipe instance, and aborts the listener.
//!
//! The Dart Settings UI is the only authorised driver of
//! [`start_endpoint`] / [`stop`]: the endpoint is off by default
//! (security-first) and the user opts in explicitly via the
//! "Expose hardware-bound keys to system SSH clients" toggle.
//!
//! ## Mobile
//!
//! No agent endpoint on Android / iOS — every type in this module is
//! `#[cfg(any(target_os = "linux", target_os = "macos", target_os =
//! "windows"))]`. The FRB layer surfaces `Err(Unsupported)` to Dart
//! callers on mobile so the Settings UI can render the row disabled.

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod backends;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod endpoint;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod identities;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod loop_runner;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod per_key_confirm;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod transport;

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub use endpoint::{start_endpoint, status, stop, AgentHandle, AgentStatus, Endpoint};

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
mod stub;

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
pub use stub::{start_endpoint, stop, AgentStatus};
