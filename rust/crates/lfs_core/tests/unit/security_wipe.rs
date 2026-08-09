/// Unit tests extracted from security/wipe.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use tempfile::TempDir;

#[test]
fn pending_wipe_is_false_on_fresh_install() {
    let dir = TempDir::new().unwrap();
    assert!(!has_pending_wipe(dir.path()));
}

#[test]
fn pending_wipe_is_true_when_marker_present() {
    let dir = TempDir::new().unwrap();
    write_pending_marker(dir.path()).unwrap();
    assert!(has_pending_wipe(dir.path()));
}

#[test]
fn pending_wipe_rejects_file_without_magic() {
    let dir = TempDir::new().unwrap();
    // Foreign drop / leftover from an unrelated tool. has_pending_wipe
    // must not coerce the next launch into a recovery wipe.
    std::fs::write(dir.path().join(WIPE_PENDING_MARKER), "stamp").unwrap();
    assert!(!has_pending_wipe(dir.path()));
}

#[test]
fn pending_wipe_rejects_unknown_version() {
    let dir = TempDir::new().unwrap();
    let mut bytes = Vec::from(*WIPE_PENDING_MAGIC);
    bytes.push(WIPE_PENDING_VERSION + 1);
    bytes.extend_from_slice(b"42");
    std::fs::write(dir.path().join(WIPE_PENDING_MARKER), &bytes).unwrap();
    assert!(!has_pending_wipe(dir.path()));
}

/// When the marker exists but the magic is wrong (foreign drop /
/// stale leftover from an unrelated tool), `has_pending_wipe`
/// must still return `false` AND emit a `CoreLog` warn so a
/// future support call can see "the marker was on disk, we
/// rejected it".
#[tokio::test]
async fn pending_wipe_rejection_emits_warn_log() {
    use crate::bus::{CoreLogLevel, Event, EventTopic};

    let app = crate::app::init();
    let mut rx = app.bus.subscribe(EventTopic::CoreLog);
    let dir = TempDir::new().unwrap();
    // Foreign content under the marker name.
    std::fs::write(dir.path().join(WIPE_PENDING_MARKER), b"stamp").unwrap();
    assert!(!has_pending_wipe(dir.path()));

    // Drain CoreLog until either a matching Wipe-tagged warn lands
    // or the channel is empty.
    let mut saw_warn = false;
    for _ in 0..32 {
        match rx.try_recv() {
            Ok(Event::CoreLog {
                level: CoreLogLevel::Warn,
                name,
                message,
            }) if name == "Wipe" && message.contains("magic mismatch") => {
                saw_warn = true;
                break;
            }
            Ok(_) => continue,
            Err(_) => break,
        }
    }
    assert!(
        saw_warn,
        "Wipe warn for magic mismatch must publish on the bus"
    );
}

/// Managed files written with non-0600 perms log a Wipe warn
/// before the delete. The delete still proceeds — pure
/// diagnostics. UNIX only; Windows does not model POSIX mode bits.
#[cfg(unix)]
#[tokio::test]
async fn sweep_warns_on_non_0600_managed_file() {
    use crate::bus::{CoreLogLevel, Event, EventTopic};
    use std::os::unix::fs::PermissionsExt;

    let _ = crate::app::init();
    let app = crate::app::instance();
    let mut rx = app.bus.subscribe(EventTopic::CoreLog);

    let dir = TempDir::new().unwrap();
    let bad = dir.path().join("credentials.kdf");
    std::fs::write(&bad, [0u8; 8]).unwrap();
    std::fs::set_permissions(&bad, std::fs::Permissions::from_mode(0o644)).unwrap();

    let report = sweep_files(dir.path());
    assert!(report
        .deleted_files
        .contains(&"credentials.kdf".to_string()));
    assert!(!bad.exists(), "delete must still proceed on perm drift");

    // The bus is broadcast — drain it until the matching Wipe warn
    // shows up. `app::init()` is process-singleton across tests, so
    // a few unrelated CoreLog lines may interleave.
    let mut saw_warn = false;
    for _ in 0..64 {
        match rx.try_recv() {
            Ok(Event::CoreLog {
                level: CoreLogLevel::Warn,
                name,
                message,
            }) if name == "Wipe"
                && message.contains("credentials.kdf")
                && message.contains("644")
                && message.contains("!= 0600") =>
            {
                saw_warn = true;
                break;
            }
            Ok(_) => continue,
            Err(_) => break,
        }
    }
    assert!(
        saw_warn,
        "Wipe warn for non-0600 perms must publish on the bus"
    );
}

#[test]
fn has_any_state_is_false_on_clean_dir() {
    let dir = TempDir::new().unwrap();
    assert!(!has_any_state(dir.path()));
}

#[test]
fn has_any_state_ignores_config_and_migration_history() {
    // Both files regenerate on next launch; counting them as
    // state would trap the user in a reset loop.
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("config.json"), "{}").unwrap();
    std::fs::write(dir.path().join("migration_history.json"), "[]").unwrap();
    assert!(!has_any_state(dir.path()));
}

#[test]
fn has_any_state_flags_a_credentials_kdf() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("credentials.kdf"), [0u8; 8]).unwrap();
    assert!(has_any_state(dir.path()));
}

#[test]
fn sweep_deletes_present_files_and_skips_absent() {
    // sweep_files clears the app's SecretStore — AppState
    // must be initialized so that singleton resolves.
    let _ = crate::app::init();
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join("credentials.kdf"), [1u8]).unwrap();
    std::fs::write(dir.path().join("letsflutssh.db"), [2u8]).unwrap();
    // `config.json` absent — sweep should not list it as failed.
    let report = sweep_files(dir.path());
    assert!(report
        .deleted_files
        .contains(&"credentials.kdf".to_string()));
    assert!(report.deleted_files.contains(&"letsflutssh.db".to_string()));
    assert!(report.failed_files.is_empty());
    // Marker cleared after a clean sweep.
    assert!(!has_pending_wipe(dir.path()));
}

#[test]
fn sweep_writes_then_clears_pending_marker() {
    let _ = crate::app::init();
    let dir = TempDir::new().unwrap();
    let report = sweep_files(dir.path());
    // No managed files present, but the sweep still ran the
    // marker write/clear cycle.
    assert!(report.deleted_files.is_empty());
    assert!(report.failed_files.is_empty());
    assert!(!has_pending_wipe(dir.path()));
}

#[test]
fn sweep_deletes_lfs_core_db_orphan_from_intermediate_build() {
    // Regression: an early Rust-port build (between bf6bb95f and
    // the b56ccf7b filename revert) wrote the SQLCipher DB to
    // `lfs_core.db` instead of reusing `letsflutssh.db`. Users
    // who installed that intermediate build had a stale orphan
    // at `lfs_core.db` that `sweep_files` skipped because the
    // filename was missing from `MANAGED_FILES`. Pressing Wipe
    // in `DbCorruptDialog` then looped — the next first-launch
    // re-opened the orphan with a freshly-generated keychain
    // key, SQLCipher rejected the cipher mismatch, the dialog
    // fired again. This test pins the cleanup so a future
    // refactor that drops the orphan entry from MANAGED_FILES
    // surfaces the regression instead of recreating the loop.
    let _ = crate::app::init();
    let dir = TempDir::new().unwrap();
    for name in [
        "lfs_core.db",
        "lfs_core.db-wal",
        "lfs_core.db-shm",
        "lfs_core.db-journal",
    ] {
        std::fs::write(dir.path().join(name), [0u8; 16]).unwrap();
    }
    let report = sweep_files(dir.path());
    for name in [
        "lfs_core.db",
        "lfs_core.db-wal",
        "lfs_core.db-shm",
        "lfs_core.db-journal",
    ] {
        assert!(
            report.deleted_files.contains(&name.to_string()),
            "{name} must be in deleted_files; current MANAGED_FILES is missing it"
        );
        assert!(
            !dir.path().join(name).exists(),
            "{name} must be removed from disk"
        );
    }
    assert!(report.failed_files.is_empty());
}

#[test]
fn sweep_wipes_logs_dir_contents() {
    let _ = crate::app::init();
    let dir = TempDir::new().unwrap();
    let logs = dir.path().join("logs");
    std::fs::create_dir(&logs).unwrap();
    std::fs::write(logs.join("session-1.log"), "x").unwrap();
    std::fs::write(logs.join("session-2.log"), "y").unwrap();
    sweep_files(dir.path());
    // Logs dir itself stays (matches Dart behaviour — the dir is
    // recreated on next log-line write); only the entries inside
    // are gone.
    assert!(logs.exists());
    let remaining: Vec<_> = std::fs::read_dir(&logs).unwrap().flatten().collect();
    assert!(remaining.is_empty());
}

#[test]
fn managed_and_orphan_lists_are_in_sync() {
    // Every orphan probe entry must appear in the managed list —
    // otherwise startup would flag state the wipe doesn't clean.
    for name in ORPHAN_PROBE_FILES {
        assert!(
            MANAGED_FILES.contains(name),
            "{name} in ORPHAN_PROBE_FILES but not MANAGED_FILES"
        );
    }
}

/// Reflection-style coverage tripwire: every on-disk artefact
/// the workspace writes under `support_dir` must appear in
/// [`MANAGED_FILES`]. Each entry below references the
/// canonical filename constant from its owning module — when
/// a future commit renames or adds an artefact, the test
/// fails until [`MANAGED_FILES`] is updated to match.
///
/// Filenames without a `pub const` source (legacy
/// `migration_history.json`, the drift-owned `letsflutssh.db`
/// family) are listed as raw literals; those strings live
/// only inside [`MANAGED_FILES`] today, so the test pins
/// the canonical spelling here too.
///
/// Directly addresses the audit's wipe-completeness gap
/// (the `hardware_vault_password_overlay_android.bin` →
/// `hardware_vault_android_bio.bin` Android-port rename
/// that left an orphan file untouched by the sweep until
/// the canonical name was added).
#[test]
fn every_known_artefact_is_in_managed_files() {
    // Markers + small state files
    let known: &[&str] = &[
        crate::security::tier_transition_marker::MARKER_FILE_NAME,
        crate::security::keychain_marker::MARKER_FILE_NAME,
        // Rate-limit on-disk state for the T1+pw keychain gate.
        "rate_limit_state.bin",
        // T1+pw password verifier hash.
        "security_pass_hash.bin",
        // KDF + verifier + key for the Paranoid tier.
        crate::security::master_password::KDF_FILE_NAME,
        crate::security::master_password::VERIFIER_FILE_NAME,
        crate::security::master_password::KEY_FILE_NAME,
        // Persisted user config + migration journal.
        crate::config_store::FILE_NAME,
        "migration_history.json",
        // Drift-owned SQLCipher DB + sidecars.
        "letsflutssh.db",
        "letsflutssh.db-wal",
        "letsflutssh.db-shm",
        "letsflutssh.db-journal",
    ];

    for name in known {
        assert!(
            MANAGED_FILES.contains(name),
            "wipe coverage gap: {name} is written by the codebase but missing from MANAGED_FILES — \
             update wipe.rs and ORPHAN_PROBE_FILES (if appropriate) so the sweep cleans it"
        );
    }

    // Hardware-vault artefacts are cfg-gated — the constant
    // visibility flips per target. Reference the canonical
    // names directly so the test runs on every host.
    let vault_files: &[&str] = &[
        // lfs_os_security::hardware_tier_vault — Apple/iOS path
        "hardware_vault_apple.bin",
        "hardware_vault_password_overlay_apple.bin",
        // lfs_os_security::android::hardware_vault — Android path
        "hardware_vault_android.bin",
        "hardware_vault_android_bio.bin",
        // lfs_core::security::hardware_tier_vault::linux — Linux
        // biometric-overlay envelope (TPM2-sealed under the
        // fprintd enrolment hash).
        "hardware_vault_password_overlay_linux.bin",
        // Pre-port / cross-platform overlays kept managed so
        // upgrade-from-old-install wipes still land cleanly.
        "hardware_vault_password_overlay_android.bin",
        "hardware_vault_password_overlay_windows.bin",
        "hardware_vault.bin",
        "hardware_vault_ios.bin",
        "hardware_vault_macos.bin",
        "hardware_vault_windows.bin",
        "hardware_vault_linux.bin",
        "hardware_vault_salt.bin",
    ];

    for name in vault_files {
        assert!(
            MANAGED_FILES.contains(name),
            "wipe coverage gap: hardware-vault artefact {name} missing from MANAGED_FILES"
        );
    }

    // Cross-check: when running on Apple/Linux/Windows
    // targets the public Apple constants should still match
    // the literal we list above. Tripwire for an accidental
    // const rename in lfs_os_security::hardware_tier_vault.
    #[cfg(not(target_os = "android"))]
    {
        assert_eq!(
            lfs_os_security::hardware_tier_vault::VAULT_FILE_NAME,
            "hardware_vault_apple.bin",
            "Apple vault filename const drifted from MANAGED_FILES"
        );
        assert_eq!(
            lfs_os_security::hardware_tier_vault::BIO_PASSWORD_FILE_NAME,
            "hardware_vault_password_overlay_apple.bin",
            "Apple bio-overlay filename const drifted from MANAGED_FILES"
        );
    }

    // Same belt-and-braces for Android.
    #[cfg(target_os = "android")]
    {
        assert_eq!(
            lfs_os_security::android::hardware_vault::VAULT_FILE,
            "hardware_vault_android.bin",
            "Android vault filename const drifted from MANAGED_FILES"
        );
        assert_eq!(
            lfs_os_security::android::hardware_vault::VAULT_FILE_BIO,
            "hardware_vault_android_bio.bin",
            "Android bio-vault filename const drifted from MANAGED_FILES"
        );
    }

    // And for the Windows primary + biometric overlay files.
    #[cfg(target_os = "windows")]
    {
        assert_eq!(
            lfs_os_security::windows::hardware_vault::VAULT_FILE,
            "hardware_vault.bin",
            "Windows vault filename const drifted from MANAGED_FILES"
        );
        assert_eq!(
            lfs_os_security::windows::hardware_vault::BIO_PASSWORD_FILE,
            "hardware_vault_password_overlay_windows.bin",
            "Windows bio-overlay filename const drifted from MANAGED_FILES"
        );
    }

    // Linux biometric-overlay file — the const lives in
    // `lfs_core::security::hardware_tier_vault::linux` because
    // the orchestrator depends on the in-crate fprintd
    // module. A rename without a matching MANAGED_FILES update
    // would leave an orphan file untouched by every wipe.
    #[cfg(target_os = "linux")]
    {
        assert_eq!(
            crate::security::hardware_tier_vault::linux::BIO_PASSWORD_FILE,
            "hardware_vault_password_overlay_linux.bin",
            "Linux bio-overlay filename const drifted from MANAGED_FILES"
        );
    }
}
