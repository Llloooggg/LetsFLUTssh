//! Catastrophic-reset keychain purge — the OS-secure-storage half
//! of "wipe every piece of app state this install holds".
//!
//! Owns the canonical [`MANAGED_KEYS`] list (every keychain slot
//! the app writes) and an actor command that issues a delete per
//! key directly through [`lfs_os_security::secure_key_storage`],
//! returning a per-key outcome report. Pairs with
//! [`crate::security::wipe`] (the file-half sweep) and the Dart
//! `WipeAllService.wipeAll` orchestrator.
//!
//! Why a canonical list rather than `*::delete_all`: the platform
//! "delete everything" surface is a black box — any platform-side
//! behavioural drift (Android EncryptedSharedPrefs deleting only
//! the current scope, Linux libsecret being prefix-matched, etc.)
//! is invisible until a forgotten key surfaces in a forensic dump.
//! Enumerating every key the app writes lets a reviewer audit the
//! wipe surface in one place; a new key gets caught at code review
//! when its consumer doesn't add to the list.
//!
//! Plaintext discipline: the delete operation does not move
//! pepper / DB-key bytes across FRB; only the key names cross.

use serde_json::{json, Value};

/// Every flutter_secure_storage slot the app writes. New keys MUST
/// be added here so the wipe stays total. The list is versioned
/// alongside the vault — bumping a slot's name is a wipe-format
/// change and gets the same migration discipline as a disk
/// artefact rename.
pub const MANAGED_KEYS: &[&str] = &[
    // T1 / L2 DB encryption key (legacy slot — pre-tier-machine
    // installs keep using this one until the tier flip rotates it).
    "letsflutssh_encryption_key",
    // L2 biometric overlay encryption key.
    "letsflutssh_biometric_encryption_key",
    // Transient probe key — `SecureKeyStorage.probe()` writes,
    // reads, deletes; included for safety against a crash mid-probe
    // leaving the slot orphaned.
    "letsflutssh_keychain_probe",
    // L2 password gate pepper.
    "letsflutssh_l2_pepper",
    // BiometricKeyVault DB key (T2 biometric path).
    "letsflutssh_bio_db_key",
];

/// Per-key wipe outcome. Aggregated into [`run`]'s report so a
/// caller can log which slots failed without losing the rest of
/// the report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyWipeOutcome {
    /// Backend reported success.
    Deleted,
    /// Backend reported an error (libsecret unreachable, keychain
    /// locked, JNI exception, etc.). The wipe continues with the
    /// next key — best-effort is preferable to abort-on-first-failure
    /// for the wipe path.
    Failed { detail: String },
}

impl KeyWipeOutcome {
    pub fn is_success(&self) -> bool {
        matches!(self, KeyWipeOutcome::Deleted)
    }
}

/// Walk [`MANAGED_KEYS`] and issue a delete per key directly via
/// [`lfs_os_security::secure_key_storage::delete`]. Returns a
/// `(key, outcome)` pair per slot; caller surfaces the per-key
/// result in the `WipeReport`.
///
/// Deletes run sequentially rather than in parallel — the
/// libsecret backend on Linux serialises requests internally, so
/// concurrent dispatch buys nothing and a serial loop keeps the
/// trace readable in a support archive.
pub async fn run() -> Vec<(String, KeyWipeOutcome)> {
    let mut report = Vec::with_capacity(MANAGED_KEYS.len());
    for key in MANAGED_KEYS {
        let outcome = match lfs_os_security::secure_key_storage::delete(key).await {
            Ok(()) => KeyWipeOutcome::Deleted,
            Err(e) => KeyWipeOutcome::Failed {
                detail: e.to_string(),
            },
        };
        report.push(((*key).to_string(), outcome));
    }
    report
}

/// Render the per-key report as a JSON object — `{ "key": "deleted"
/// | "failed: <msg>" | "cancelled" }` — for the FRB caller that
/// just wants a printable diagnostic blob in the support log.
/// Keep the shape flat so a `jq` over a support archive can
/// pinpoint a stuck key without parsing nested structures.
pub fn report_to_json(report: &[(String, KeyWipeOutcome)]) -> Value {
    let mut map = serde_json::Map::new();
    for (key, outcome) in report {
        let s = match outcome {
            KeyWipeOutcome::Deleted => "deleted".to_string(),
            KeyWipeOutcome::Failed { detail } => format!("failed: {detail}"),
        };
        map.insert(key.clone(), json!(s));
    }
    Value::Object(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_keys_no_duplicates() {
        let mut seen = std::collections::HashSet::new();
        for k in MANAGED_KEYS {
            assert!(seen.insert(*k), "duplicate key in MANAGED_KEYS: {k}");
        }
    }

    #[test]
    fn managed_keys_all_namespaced() {
        // Defensive check — a key without the `letsflutssh_` prefix
        // would risk colliding with another app's slot on shared
        // platforms (libsecret on Linux). Caught at test time so a
        // typo in a new slot never reaches the wipe surface.
        for k in MANAGED_KEYS {
            assert!(
                k.starts_with("letsflutssh_"),
                "MANAGED_KEYS entry missing namespace: {k}"
            );
        }
    }

    #[test]
    fn report_to_json_emits_per_key_status() {
        let report = vec![
            ("a".into(), KeyWipeOutcome::Deleted),
            ("b".into(), KeyWipeOutcome::Failed { detail: "x".into() }),
        ];
        let v = report_to_json(&report);
        assert_eq!(v.get("a").and_then(|x| x.as_str()), Some("deleted"));
        assert_eq!(v.get("b").and_then(|x| x.as_str()), Some("failed: x"));
    }
}
