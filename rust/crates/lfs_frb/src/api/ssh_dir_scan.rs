//! FRB adapter for `lfs_core::ssh_dir_scan`. Production callers
//! (settings → import keys from `~/.ssh`) hand a directory path
//! over and get back the candidate PEM bodies + suggested labels.
//! Sync since the underlying ops are bounded — small directory,
//! tiny per-file size cap, no network.

#[derive(Debug, Clone)]
pub struct DbScannedKey {
    pub path: String,
    pub pem: String,
    pub suggested_label: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn ssh_dir_scan(directory: String) -> Vec<DbScannedKey> {
    lfs_core::ssh_dir_scan::scan(&directory)
        .into_iter()
        .map(|k| DbScannedKey {
            path: k.path,
            pem: k.pem,
            suggested_label: k.suggested_label,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_missing_directory_returns_empty_list() {
        // Production callers hand the user's `~/.ssh` path through;
        // when the directory doesn't exist the scan must collapse
        // to an empty list, not panic. Same graceful-degrade
        // contract the file-listing surface follows.
        let scanned = ssh_dir_scan("/nonexistent/scan/path-7c8f".into());
        assert!(scanned.is_empty());
    }

    #[test]
    fn scan_empty_directory_returns_empty_list() {
        let tmp = tempfile::tempdir().expect("tmp dir");
        let path = tmp.path().to_str().expect("utf-8 tmp path").to_string();
        let scanned = ssh_dir_scan(path);
        assert!(scanned.is_empty());
    }

    #[test]
    fn scan_skips_obvious_non_keys() {
        // Drop a `config`, `known_hosts`, and a `*.pub` into the
        // tmp dir. None are private keys; the scanner must skip
        // every file via the obvious-non-key sniff and return
        // empty rather than feed them to the PEM parser.
        let tmp = tempfile::tempdir().expect("tmp dir");
        for name in &["config", "known_hosts", "id_ed25519.pub"] {
            std::fs::write(tmp.path().join(name), b"placeholder").expect("write fixture file");
        }
        let path = tmp.path().to_str().expect("utf-8 tmp path").to_string();
        let scanned = ssh_dir_scan(path);
        assert!(scanned.is_empty());
    }

    #[test]
    fn scanned_key_clone_round_trip() {
        // Defensive — ensure `DbScannedKey` clones value-wise so a
        // future refactor doesn't accidentally introduce a shared
        // reference field that the FRB marshaller can't handle.
        let k = DbScannedKey {
            path: "/home/alice/.ssh/id_ed25519".into(),
            pem: "...".into(),
            suggested_label: "alice".into(),
        };
        let c = k.clone();
        assert_eq!(c.path, "/home/alice/.ssh/id_ed25519");
        assert_eq!(c.suggested_label, "alice");
    }
}
