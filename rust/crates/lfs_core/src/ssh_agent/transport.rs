//! Per-platform listener setup for the in-process ssh-agent endpoint.
//!
//! Two transports, one trait — [`ssh_agent_lib::agent::ListeningSocket`]:
//!
//! - **Linux / macOS**: Unix domain socket at
//!   `${XDG_RUNTIME_DIR:-/tmp}/letsflutssh-agent.<pid>/agent.sock`.
//!   The parent directory mode is `0o700` so only the owning user
//!   can `cd` into it. The socket file itself inherits the parent
//!   directory's perms but kernels enforce SO_PEERCRED-based access
//!   regardless: any connect requires the connecting process's
//!   filesystem path-walk to reach the socket inode, which the 0o700
//!   parent forbids for non-owners.
//! - **Windows**: named pipe at `\\.\pipe\letsflutssh-agent.<pid>`.
//!   `tokio::net::windows::named_pipe::ServerOptions::first_pipe_instance(true)`
//!   creates the pipe with the default security descriptor, which
//!   already grants only the current user SID + SYSTEM. We do not
//!   widen the DACL.
//!
//! `<pid>` in the path makes parallel app instances coexist:
//! two-runner debug builds, the rare second instance launched
//! before the single-instance lock kicks in, the future
//! multi-profile fork.
//!
//! ## Path discovery
//!
//! [`endpoint_path`] returns the socket / pipe path. The Settings UI
//! shows this verbatim with a Copy button so the user can
//! `export SSH_AUTH_SOCK=...` (Unix) or paste the pipe name into
//! OpenSSH-on-Windows `IdentityAgent` (Windows). The path is
//! cfg-gated to the platform; mobile builds return `Err(Unsupported)`
//! via the stub module.

#[cfg(unix)]
use std::path::PathBuf;

use crate::error::Error;

/// Compose the Unix domain socket path.
///
/// `${XDG_RUNTIME_DIR:-/tmp}/letsflutssh-agent.<pid>/agent.sock`
///
/// The parent directory is per-pid so multiple instances coexist.
/// On macOS XDG_RUNTIME_DIR is unset by default; we fall back to
/// `/tmp` which matches Apple's own `Library/Application Support`
/// convention being inappropriate for ephemeral sockets (it's
/// backed up by Time Machine).
#[cfg(unix)]
pub fn unix_socket_path() -> PathBuf {
    let base = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into());
    let pid = std::process::id();
    let mut p = PathBuf::from(base);
    p.push(format!("letsflutssh-agent.{pid}"));
    p.push("agent.sock");
    p
}

/// Compose the Windows named pipe path:
/// `\\.\pipe\letsflutssh-agent.<pid>`
#[cfg(windows)]
pub fn windows_pipe_path() -> String {
    let pid = std::process::id();
    format!(r"\\.\pipe\letsflutssh-agent.{pid}")
}

/// Bind a Unix listener at [`unix_socket_path`], creating the
/// parent directory with mode `0o700` first.
///
/// Idempotent on the parent directory — the per-pid name keeps
/// repeat invocations against the same pid rare, and SO_REUSEADDR
/// is not a thing for unix-domain stream sockets, so we explicitly
/// remove a stale `agent.sock` file before binding. The remove is
/// safe-by-construction: a stale file at this exact path can only
/// have been left by a previous run of OUR process at this PID, and
/// the PID space wraps slowly enough that a foreign process owning
/// the file would be a separate audit story.
#[cfg(unix)]
pub fn bind_unix() -> Result<(tokio::net::UnixListener, PathBuf), Error> {
    use std::os::unix::fs::PermissionsExt;

    let path = unix_socket_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| Error::Io(format!("ssh-agent: create parent dir: {e}")))?;
        // Owner-only on the parent. POSIX rejects setting perms on a
        // symlink target with `set_permissions`; we are creating the
        // dir, so the path is guaranteed to be a directory inode.
        let mut perms = std::fs::metadata(parent)
            .map_err(|e| Error::Io(format!("ssh-agent: stat parent dir: {e}")))?
            .permissions();
        perms.set_mode(0o700);
        std::fs::set_permissions(parent, perms)
            .map_err(|e| Error::Io(format!("ssh-agent: chmod parent dir: {e}")))?;
    }
    if path.exists() {
        let _ = std::fs::remove_file(&path);
    }
    let listener = tokio::net::UnixListener::bind(&path)
        .map_err(|e| Error::Io(format!("ssh-agent: bind unix socket: {e}")))?;
    Ok((listener, path))
}

/// Bind the Windows named pipe. The first instance gets created
/// here; subsequent client connects roll the pipe instance over
/// inside `NamedPipeListener::accept`.
#[cfg(windows)]
pub fn bind_windows() -> Result<(ssh_agent_lib::agent::NamedPipeListener, String), Error> {
    let path = windows_pipe_path();
    let listener = ssh_agent_lib::agent::NamedPipeListener::bind(path.clone())
        .map_err(|e| Error::Io(format!("ssh-agent: bind named pipe: {e}")))?;
    Ok((listener, path))
}

/// Best-effort cleanup. Removes the socket file and the per-pid
/// parent directory on Unix; named pipes self-clean on the last
/// handle drop, so this is a no-op on Windows.
#[cfg(unix)]
pub fn cleanup_unix(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    if let Some(parent) = path.parent() {
        // `remove_dir` only succeeds when the directory is empty —
        // exactly what we want. A foreign process that dropped a
        // file in there keeps it alive.
        let _ = std::fs::remove_dir(parent);
    }
}

#[cfg(windows)]
pub fn cleanup_windows(_path: &str) {
    // Named pipe instances die when the server side drops them; the
    // ServerOptions handle inside NamedPipeListener manages that for
    // us. Nothing to do here.
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn unix_socket_path_uses_pid_suffix() {
        let path = unix_socket_path();
        let s = path.to_string_lossy();
        assert!(s.contains("letsflutssh-agent."));
        assert!(s.ends_with("agent.sock"));
    }

    /// Both bind_unix tests run inside the same `cargo test`
    /// process, sharing the per-pid path. Serialise so they don't
    /// race for the same socket file. A `Mutex<()>` is enough —
    /// the test runner schedules tests across threads but never
    /// against the same lock concurrently.
    static UNIX_BIND_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[tokio::test]
    async fn bind_unix_creates_owner_only_parent() {
        use std::os::unix::fs::PermissionsExt;
        let _g = UNIX_BIND_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let (listener, path) = bind_unix().unwrap();
        let parent = path.parent().unwrap();
        let perms = std::fs::metadata(parent).unwrap().permissions();
        // The low 12 bits encode the unix mode.
        assert_eq!(perms.mode() & 0o777, 0o700);
        drop(listener);
        cleanup_unix(&path);
    }

    #[tokio::test]
    async fn bind_unix_replaces_stale_socket() {
        let _g = UNIX_BIND_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let (l1, path) = bind_unix().unwrap();
        // Drop the listener so the second bind can claim the path.
        drop(l1);
        // Recreate the listener — the implementation removes the
        // stale file first, so the second bind must succeed.
        let (l2, _) = bind_unix().unwrap();
        drop(l2);
        cleanup_unix(&path);
    }
}
