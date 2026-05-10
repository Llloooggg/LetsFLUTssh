//! FRB adapter for `lfs_core::security::wipe_keychain`. Owns the
//! canonical OS-keychain alias list + actor command that fans out a
//! `KeychainOpKind::Delete` per key. Alias names share the external-
//! compat `FlutterSecureStorageKeyAlias_…` prefix pinned by
//! `lfs_os_security::android::keystore::KEY_ALIAS_PREFIX` (see its
//! docstring). Runtime path:
//! `lfs_os_security::secure_key_storage::delete` per platform.
//!
//! Async — the underlying actor walks the key list sequentially
//! and awaits each prompt round-trip; total time is O(N keys ×
//! plugin latency) which on Linux libsecret can run hundreds of
//! ms in aggregate. Surfacing async to FRB lets the Settings →
//! Reset all data dialog keep its spinner alive without blocking
//! the FRB worker thread.

use lfs_core::security::wipe_keychain;

/// Per-key wipe outcome, mirrored to FRB so the Dart `WipeReport`
/// can render which slots failed without re-parsing a flat string.
#[derive(Debug, Clone)]
pub struct DbKeychainKeyWipe {
    pub key: String,
    /// `"deleted"` on success, `"failed: <msg>"` on backend error.
    /// The wipe driver fans out one delete per key without any
    /// user-facing prompt, so cancellation never appears here —
    /// only success / failure shapes ship.
    pub status: String,
}

/// Aggregated result of a `wipe_keychain_run`. `succeeded_count` +
/// `failed_count` lets the Settings UI render a "wiped N of M
/// keychain entries" line without iterating `entries`.
#[derive(Debug, Clone)]
pub struct DbKeychainWipeReport {
    pub entries: Vec<DbKeychainKeyWipe>,
    pub succeeded_count: u32,
    pub failed_count: u32,
    /// Convenience flag — true when EVERY key wiped successfully.
    /// Mirrors the Dart `WipeReport.keychainPurged` bool.
    pub all_succeeded: bool,
}

/// Walk the canonical OS-keychain alias list and dispatch a delete
/// per key via `lfs_os_security::secure_key_storage::delete`
/// (libsecret on Linux, Keychain Services on Apple, Credential
/// Manager on Windows, AndroidKeyStore JNI on Android). Alias
/// prefix is fixed by `KEY_ALIAS_PREFIX` (external-compat
/// constant — see its docstring).
///
/// Best-effort: a failed delete on one key does not abort the
/// rest. The Dart wrapper surfaces partial failure in the UI.
pub async fn wipe_keychain_run() -> DbKeychainWipeReport {
    let report = wipe_keychain::run().await;
    let mut succeeded = 0u32;
    let mut failed = 0u32;
    let entries = report
        .into_iter()
        .map(|(key, outcome)| {
            let status = match outcome {
                wipe_keychain::KeyWipeOutcome::Deleted => {
                    succeeded += 1;
                    "deleted".to_string()
                }
                wipe_keychain::KeyWipeOutcome::Failed { detail } => {
                    failed += 1;
                    format!("failed: {detail}")
                }
            };
            DbKeychainKeyWipe { key, status }
        })
        .collect::<Vec<_>>();
    let all_succeeded = failed == 0;
    DbKeychainWipeReport {
        entries,
        succeeded_count: succeeded,
        failed_count: failed,
        all_succeeded,
    }
}

/// The canonical key list, exposed so the Dart-side fallback
/// (flutter_test contexts that don't load the FRB native lib)
/// can iterate the same set without re-listing the names. Pure
/// string list — Dart caller maps to its own delete loop.
#[flutter_rust_bridge::frb(sync)]
pub fn wipe_keychain_managed_keys() -> Vec<String> {
    wipe_keychain::MANAGED_KEYS
        .iter()
        .map(|s| (*s).to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // The `wipe_keychain_run` async path drives a per-key delete
    // prompt through the platform plugin via the bus; covered by
    // the Dart `wipe_keychain_test.dart` integration suite. The
    // standalone tests below pin the canonical key list contract +
    // the report-shape mirror.

    #[test]
    fn managed_keys_includes_every_known_key_and_is_unique() {
        let keys = wipe_keychain_managed_keys();
        assert!(!keys.is_empty(), "managed key list must not be empty");
        // Pin uniqueness — a duplicate would fan out two deletes
        // for the same slot, doubling the `failed_count` arithmetic.
        let mut deduped = keys.clone();
        deduped.sort();
        deduped.dedup();
        assert_eq!(deduped.len(), keys.len(), "managed keys must be unique");
    }

    #[test]
    fn managed_keys_mirrors_lfs_core_const() {
        // The Dart fallback (flutter_test contexts that don't load
        // the FRB native lib) iterates the lfs_core list verbatim;
        // pin the byte-for-byte mirror so a Rust-side bump can't
        // silently diverge.
        let frb_keys = wipe_keychain_managed_keys();
        let core_keys: Vec<String> = wipe_keychain::MANAGED_KEYS
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        assert_eq!(frb_keys, core_keys);
    }

    #[test]
    fn db_keychain_key_wipe_clone_round_trip() {
        let v = DbKeychainKeyWipe {
            key: "alpha".into(),
            status: "deleted".into(),
        };
        let c = v.clone();
        assert_eq!(c.key, "alpha");
        assert_eq!(c.status, "deleted");
    }

    #[test]
    fn db_keychain_wipe_report_clone_round_trip() {
        let v = DbKeychainWipeReport {
            entries: vec![DbKeychainKeyWipe {
                key: "x".into(),
                status: "deleted".into(),
            }],
            succeeded_count: 1,
            failed_count: 0,
            all_succeeded: true,
        };
        let c = v.clone();
        assert_eq!(c.entries.len(), 1);
        assert_eq!(c.succeeded_count, 1);
        assert!(c.all_succeeded);
    }
}
