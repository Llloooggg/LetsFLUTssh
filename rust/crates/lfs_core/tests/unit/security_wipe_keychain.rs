/// Unit tests extracted from security/wipe_keychain.rs
/// Declared via `#[path] mod tests;` in the source file.
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
