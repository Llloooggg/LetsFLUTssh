//! FRB adapter for `lfs_core::security::wipe_keychain`. Owns the
//! canonical flutter_secure_storage key list + actor command that
//! fans out a `KeychainOpKind::Delete` prompt per key.
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
    /// `"deleted"` on success, `"failed: <msg>"` on plugin error,
    /// `"cancelled"` when the prompt was abandoned.
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

/// Walk the canonical `flutter_secure_storage` key list and
/// dispatch a delete prompt per key. Returns a per-key outcome
/// report; the Dart subscriber for `KeychainOpPromptRequest`
/// executes each delete via the keychain plugin.
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
                wipe_keychain::KeyWipeOutcome::Cancelled => {
                    failed += 1;
                    "cancelled".to_string()
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
