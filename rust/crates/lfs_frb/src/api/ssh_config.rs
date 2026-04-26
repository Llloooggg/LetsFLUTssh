//! FRB adapter for `lfs_core::ssh_config`.
//!
//! Surfaces the OpenSSH config parser as a synchronous one-shot.
//! `Include` directives are NOT expanded Rust-side — the FRB
//! boundary cannot easily marshal a callback for the include
//! reader. Callers either pre-expand includes Dart-side and pass
//! the fully-expanded content here, or rely on the Dart parser
//! for now.

/// FRB-visible mirror of `lfs_core::ssh_config::AuthType`.
#[derive(Debug, Clone, Copy)]
pub enum DbOpenSshAuthType {
    Password,
    Key,
}

impl From<lfs_core::ssh_config::AuthType> for DbOpenSshAuthType {
    fn from(a: lfs_core::ssh_config::AuthType) -> Self {
        match a {
            lfs_core::ssh_config::AuthType::Password => DbOpenSshAuthType::Password,
            lfs_core::ssh_config::AuthType::Key => DbOpenSshAuthType::Key,
        }
    }
}

/// FRB-visible mirror of `lfs_core::ssh_config::HostEntry`.
#[derive(Debug, Clone)]
pub struct DbOpenSshHostEntry {
    pub host: String,
    pub host_name: Option<String>,
    pub user: Option<String>,
    pub port: Option<u32>,
    pub identity_files: Vec<String>,
    pub preferred_auth_types: Option<Vec<DbOpenSshAuthType>>,
}

impl From<lfs_core::ssh_config::HostEntry> for DbOpenSshHostEntry {
    fn from(e: lfs_core::ssh_config::HostEntry) -> Self {
        DbOpenSshHostEntry {
            host: e.host,
            host_name: e.host_name,
            user: e.user,
            port: e.port.map(|p| p as u32),
            identity_files: e.identity_files,
            preferred_auth_types: e
                .preferred_auth_types
                .map(|v| v.into_iter().map(DbOpenSshAuthType::from).collect()),
        }
    }
}

/// Parse OpenSSH config content. The caller MUST have expanded
/// `Include` directives before calling — the synchronous
/// boundary takes a single string. Returns one entry per
/// concrete host (wildcard / negation blocks fold into the
/// concretes).
#[flutter_rust_bridge::frb(sync)]
pub fn parse_openssh_config(content: String) -> Vec<DbOpenSshHostEntry> {
    // The base_dir / depth args are irrelevant when the include
    // reader returns nothing — pass a no-op reader so the parser
    // only runs the block + wildcard pipeline.
    let no_includes = |_: &str| -> Option<String> { None };
    lfs_core::ssh_config::parse_openssh_config(&content, &no_includes, "", 0)
        .into_iter()
        .map(DbOpenSshHostEntry::from)
        .collect()
}
