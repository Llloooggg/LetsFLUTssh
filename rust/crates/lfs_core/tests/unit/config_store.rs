/// Unit tests extracted from config_store.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use tempfile::TempDir;

fn fresh_dir() -> TempDir {
    TempDir::new().unwrap()
}

#[test]
fn init_returns_defaults_for_empty_dir() {
    let dir = fresh_dir();
    let store = Store::for_tests();
    let json = store.init(dir.path().to_path_buf()).unwrap();
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    // Default AppConfig emits flat top-level keys (terminal
    // / ssh / ui / behavior fields all there).
    assert!(value.get("font_size").is_some());
    assert!(value.get("default_port").is_some());
}

#[test]
fn init_loads_existing_file() {
    let dir = fresh_dir();
    let path = dir.path().join("config.json");
    std::fs::write(&path, r#"{"font_size":18.0}"#).unwrap();
    let store = Store::for_tests();
    let json = store.init(dir.path().to_path_buf()).unwrap();
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(
        value.get("font_size").and_then(serde_json::Value::as_f64),
        Some(18.0),
    );
}

#[test]
fn init_returns_err_for_corrupt_file() {
    // Pre-fix: silently dropped the corrupt file's contents and
    // seeded `AppConfig::default()`; the next `update` would
    // flush those defaults over the on-disk content and lose
    // the user's settings. The Dart-side `loadAppConfigFromDisk`
    // catches the matching `AppConfigParseException` and routes
    // the user to the fatal-error screen so they can recover
    // the file manually.
    let dir = fresh_dir();
    let path = dir.path().join("config.json");
    std::fs::write(&path, "{not json").unwrap();
    let store = Store::for_tests();
    let err = store.init(dir.path().to_path_buf()).unwrap_err();
    assert!(err.contains("parse"), "unexpected error tag: {err}");
}

#[test]
fn init_seeds_defaults_when_file_absent() {
    // Absent file is the legitimate first-launch path — seed
    // defaults silently so a fresh install does not surface
    // the fatal-error screen.
    let dir = fresh_dir();
    let store = Store::for_tests();
    let json = store.init(dir.path().to_path_buf()).unwrap();
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(
        value.get("font_size").and_then(serde_json::Value::as_f64),
        Some(14.0),
    );
}

#[test]
fn get_json_returns_none_before_init() {
    let store = Store::for_tests();
    assert!(store.get_json().is_none());
}

#[test]
fn set_json_updates_in_memory_state_synchronously() {
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    store.set_json(r#"{"font_size":20.0}"#).unwrap();
    let snapshot: serde_json::Value = serde_json::from_str(&store.get_json().unwrap()).unwrap();
    assert_eq!(
        snapshot
            .get("font_size")
            .and_then(serde_json::Value::as_f64),
        Some(20.0),
    );
}

#[test]
fn set_json_errors_when_not_initialised() {
    let store = Store::for_tests();
    let result = store.set_json(r#"{}"#);
    assert!(result.is_err());
}

#[test]
fn set_json_errors_on_malformed_json() {
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    let result = store.set_json("{not json");
    assert!(result.is_err());
}

#[test]
fn flush_persists_pending_state_to_disk() {
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    store.set_json(r#"{"font_size":24.0}"#).unwrap();
    store.flush().unwrap();
    let on_disk = std::fs::read_to_string(dir.path().join("config.json")).unwrap();
    let value: serde_json::Value = serde_json::from_str(&on_disk).unwrap();
    assert_eq!(
        value.get("font_size").and_then(serde_json::Value::as_f64),
        Some(24.0),
    );
}

#[test]
fn flush_with_no_pending_writes_current_state() {
    // Fresh init — current is the loaded/default state, no
    // pending. Flush still writes the current snapshot so
    // callers can use it as "ensure on disk now".
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    store.flush().unwrap();
    assert!(dir.path().join("config.json").exists());
}

#[test]
fn flush_returns_none_before_init() {
    let store = Store::for_tests();
    assert!(store.flush().unwrap().is_none());
}

#[test]
fn tick_if_due_returns_false_within_debounce_window() {
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    store.set_json(r#"{"font_size":24.0}"#).unwrap();
    // pending_at is set to now + DEBOUNCE; tick immediately
    // should be a no-op.
    assert!(!store.tick_if_due().unwrap());
    assert!(!std::fs::read_to_string(dir.path().join("config.json"))
        .map(|c| c.contains("24.0"))
        .unwrap_or(false));
}

#[test]
fn back_to_back_set_calls_collapse_into_one_pending() {
    // Three rapid set_json calls — only the last value
    // should land on disk after flush. Pending replaces in
    // place.
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    store.set_json(r#"{"font_size":14.0}"#).unwrap();
    store.set_json(r#"{"font_size":18.0}"#).unwrap();
    store.set_json(r#"{"font_size":24.0}"#).unwrap();
    store.flush().unwrap();
    let on_disk = std::fs::read_to_string(dir.path().join("config.json")).unwrap();
    let value: serde_json::Value = serde_json::from_str(&on_disk).unwrap();
    assert_eq!(
        value.get("font_size").and_then(serde_json::Value::as_f64),
        Some(24.0),
    );
}

#[test]
fn was_loaded_from_disk_is_false_before_init() {
    // Fresh actor — no init has run yet. The flag stays false so
    // a Dart caller that reads the value before `config_store_init`
    // returns gets a deterministic "no file adopted" signal.
    let store = Store::for_tests();
    assert!(!store.was_loaded_from_disk());
}

#[test]
fn was_loaded_from_disk_is_false_when_file_absent() {
    // Fresh-install path: empty support dir → defaults seeded.
    // The flag must stay false so the SecurityInitController routes
    // the user through the first-launch wizard.
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    assert!(!store.was_loaded_from_disk());
}

#[test]
fn was_loaded_from_disk_is_true_when_file_present_and_valid() {
    // Existing valid file → parsed + adopted. The flag flips true
    // so the SecurityInitController takes the resume-saved-tier
    // branch instead of re-running the first-launch wizard.
    let dir = fresh_dir();
    let path = dir.path().join("config.json");
    std::fs::write(&path, r#"{"font_size":18.0}"#).unwrap();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    assert!(store.was_loaded_from_disk());
}

#[test]
fn was_loaded_from_disk_resets_when_re_init_finds_no_file() {
    // Test reset path: a successful disk load followed by an init
    // against a fresh tempdir (no file) must roll the flag back
    // to false, otherwise the Dart wipe path would skip wizard
    // setup after a reset-and-relaunch.
    let dir1 = fresh_dir();
    std::fs::write(dir1.path().join("config.json"), r#"{"font_size":18.0}"#).unwrap();
    let store = Store::for_tests();
    store.init(dir1.path().to_path_buf()).unwrap();
    assert!(store.was_loaded_from_disk());
    let dir2 = fresh_dir();
    store.init(dir2.path().to_path_buf()).unwrap();
    assert!(!store.was_loaded_from_disk());
}

#[test]
fn re_init_drops_pending_without_flush() {
    // Test reset path: re-init under a different dir
    // discards the previous in-memory state without writing.
    let dir1 = fresh_dir();
    let store = Store::for_tests();
    store.init(dir1.path().to_path_buf()).unwrap();
    store.set_json(r#"{"font_size":99.0}"#).unwrap();
    let dir2 = fresh_dir();
    store.init(dir2.path().to_path_buf()).unwrap();
    // Original dir never received the 99.0 write.
    assert!(!dir1.path().join("config.json").exists());
}

#[test]
fn update_security_probe_cache_round_trips_some_then_none() {
    // The Rust-side persister actor (security::capabilities_persister)
    // is the only caller in production; this pin guards the
    // partial-update contract — value lands in `get_app_config`,
    // None clears the slot — without going through the bus.
    use crate::security::capabilities::{KeyringProbeResult, SecurityCapabilities};
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();

    let snapshot = SecurityCapabilities {
        keychain_available: true,
        hardware_vault_available: true,
        biometric_available: false,
        fprintd_available: false,
        is_linux_host: true,
        keychain_probe: KeyringProbeResult::Available,
        hardware_probe_code: "linuxTpmReady".into(),
    };
    store
        .update_security_probe_cache(Some(snapshot.clone()))
        .unwrap();
    let after_set = store.get_app_config().unwrap();
    assert_eq!(after_set.security_probe_cache, Some(snapshot));

    store.update_security_probe_cache(None).unwrap();
    let after_clear = store.get_app_config().unwrap();
    assert_eq!(after_clear.security_probe_cache, None);
}

#[test]
fn update_security_probe_cache_errors_when_not_initialised() {
    let store = Store::for_tests();
    let r = store.update_security_probe_cache(None);
    assert!(r.is_err(), "expected init-required error");
}

#[test]
fn update_security_tier_lands_in_get_app_config_and_preserves_modifiers() {
    // Seed the actor with an existing `(Keychain, password=true)`
    // bag so the partial-update has something to preserve.
    use crate::security::{SecurityConfig, SecurityTier, SecurityTierModifiers};
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    // Seed prior state via the JSON round-trip so we don't need a
    // dedicated test-helper setter for the field.
    let seeded = AppConfig {
        security: Some(SecurityConfig {
            tier: SecurityTier::Keychain,
            modifiers: SecurityTierModifiers {
                password: true,
                biometric: false,
            },
        }),
        ..AppConfig::default()
    };
    store.set_json(&seeded.to_json_value().to_string()).unwrap();

    store.update_security_tier(SecurityTier::Paranoid).unwrap();
    let after = store.get_app_config().unwrap();
    let sec = after.security.expect("security present");
    assert_eq!(sec.tier, SecurityTier::Paranoid);
    assert!(
        sec.modifiers.password,
        "modifiers must survive the tier-only partial update"
    );
}

#[test]
fn update_security_tier_is_idempotent_on_matching_state() {
    // Re-applying the same `(tier, modifiers)` pair must not
    // arm the debounce timer — saves the disk write on a
    // no-op cascade re-run.
    use crate::security::{SecurityConfig, SecurityTier};
    let dir = fresh_dir();
    let store = Store::for_tests();
    store.init(dir.path().to_path_buf()).unwrap();
    let seeded = AppConfig {
        security: Some(SecurityConfig::defaults()),
        ..AppConfig::default()
    };
    store.set_json(&seeded.to_json_value().to_string()).unwrap();
    // Flush the seed so `pending` is cleared.
    store.flush().unwrap();

    store.update_security_tier(SecurityTier::Plaintext).unwrap();
    // No write should have been queued — the state already matched.
    let g = store.inner.lock().unwrap();
    assert!(
        g.pending.is_none(),
        "idempotent skip must leave pending=None"
    );
}

#[test]
fn update_security_tier_errors_when_not_initialised() {
    use crate::security::SecurityTier;
    let store = Store::for_tests();
    let r = store.update_security_tier(SecurityTier::Plaintext);
    assert!(r.is_err(), "expected init-required error");
}
