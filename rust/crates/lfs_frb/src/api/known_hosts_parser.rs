//! FRB adapter for `lfs_core::known_hosts_parser`. Synchronous —
//! the work is small string parsing, no IO. Used by the Dart
//! `KnownHostsManager.importFromString` to walk a pasted /
//! file-loaded blob without rebuilding the OpenSSH host-spec
//! parser in two languages.

#[derive(Debug, Clone)]
pub struct DbParsedHostEntry {
    pub host_port: String,
    pub key_type: String,
    pub key_base64: String,
}

impl From<lfs_core::known_hosts_parser::ParsedHostEntry> for DbParsedHostEntry {
    fn from(p: lfs_core::known_hosts_parser::ParsedHostEntry) -> Self {
        Self {
            host_port: p.host_port,
            key_type: p.key_type,
            key_base64: p.key_base64,
        }
    }
}

/// Parse a single known_hosts line into zero or more entries.
#[flutter_rust_bridge::frb(sync)]
pub fn known_hosts_parse_line(line: String) -> Vec<DbParsedHostEntry> {
    lfs_core::known_hosts_parser::parse_line(&line)
        .into_iter()
        .map(DbParsedHostEntry::from)
        .collect()
}

/// True when `line` is an OpenSSH `HashKnownHosts yes` row
/// (`|1|salt|hash <keytype> <b64>`). Used by the importer's
/// "skipped N hashed entries" warning.
#[flutter_rust_bridge::frb(sync)]
pub fn known_hosts_is_hashed_line(line: String) -> bool {
    lfs_core::known_hosts_parser::is_hashed_hosts_line(&line)
}
