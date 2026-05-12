//! Mobile (`target_os = "android"` / `target_os = "ios"`) stub.
//!
//! No SSH client on Android or iOS reads a host-local agent socket;
//! the system app sandboxes deny the cross-process IPC the agent
//! protocol depends on, and there is no `ssh` / `git` shell on the
//! end-user device to consume it. Surface a single `Unsupported`
//! error variant so the FRB layer can render the Settings row
//! disabled-with-reason instead of attempting a transport open
//! that would fail with a less-actionable OS error.

use crate::error::Error;

/// Aggregated status. Always `Stopped { unsupported: true }` on
/// mobile.
#[derive(Debug, Clone)]
pub struct AgentStatus {
    pub running: bool,
    pub socket_path: Option<String>,
    pub unsupported: bool,
}

/// Mobile-side handle. Never constructed; included so the FRB API
/// surface compiles cross-platform without per-platform shims at
/// every call site.
#[derive(Debug)]
pub struct AgentHandle;

/// Always returns `Err(Error::Unsupported)` on mobile.
pub fn start_endpoint() -> Result<AgentHandle, Error> {
    Err(Error::Unsupported(
        "ssh-agent endpoint is not available on mobile targets".into(),
    ))
}

/// No-op on mobile.
pub fn stop() {}
