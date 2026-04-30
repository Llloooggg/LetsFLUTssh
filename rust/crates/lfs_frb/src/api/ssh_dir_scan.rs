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
