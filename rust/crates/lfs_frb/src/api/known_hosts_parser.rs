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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_line_extracts_simple_host_entry() {
        let line = "edge.example.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5".to_string();
        let entries = known_hosts_parse_line(line);
        assert_eq!(entries.len(), 1);
        let e = &entries[0];
        assert!(e.host_port.contains("edge.example.com"));
        assert_eq!(e.key_type, "ssh-ed25519");
        assert!(e.key_base64.starts_with("AAAA"));
    }

    #[test]
    fn parse_line_drops_blank_and_comment() {
        // Blank lines + `#`-prefixed comments produce no entries.
        // The importer's per-line walk relies on this so it can
        // count "valid" rows accurately.
        assert!(known_hosts_parse_line("".into()).is_empty());
        assert!(known_hosts_parse_line("   ".into()).is_empty());
        assert!(known_hosts_parse_line("# some comment".into()).is_empty());
    }

    #[test]
    fn is_hashed_line_recognises_hashed_prefix() {
        // OpenSSH HashKnownHosts shape: `|1|<base64-salt>|<base64-hash>`.
        assert!(known_hosts_is_hashed_line(
            "|1|salt|hash ssh-ed25519 AAAA".into()
        ));
    }

    #[test]
    fn is_hashed_line_passes_plain_host_lines() {
        assert!(!known_hosts_is_hashed_line(
            "edge.example.com ssh-ed25519 AAAA".into()
        ));
    }
}
