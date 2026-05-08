//! Catastrophic-reset file sweep — the on-disk half of "wipe every
//! piece of app state this install holds".
//!
//! Owns the canonical [`MANAGED_FILES`] list (every artefact the app
//! writes under `app-support`) and the [`ORPHAN_PROBE_FILES`] subset
//! used at startup to detect "this install has prior state but the
//! current build sees no `SecurityConfig` for it". Both lists used
//! to live Dart-side in `wipe_all_service.dart`; consolidating
//! Rust-side keeps the file-name catalogue authoritative even when
//! the Dart shim shrinks further.
//!
//! What stays Dart: keychain (`flutter_secure_storage`) purge, the
//! `com.letsflutssh/hardware_vault` `MethodChannel` invocations, and
//! the per-session credential cache evict. Each of those rides on a
//! platform plugin that has no equivalent in `lfs_core`; the file
//! half is what this module owns.

use std::fs;
use std::path::Path;
use std::time::SystemTime;

/// Marker the wipe writes before any delete runs. A leftover marker
/// at startup means the previous run started a wipe that did not
/// finish — caller resumes the sweep idempotently before reaching
/// `_initSecurity`.
pub const WIPE_PENDING_MARKER: &str = ".wipe-pending";

/// Wire-format magic + version for `.wipe-pending`. Every emit
/// stamps the prefix; readers reject anything else, so a hostile
/// drop of a same-named file does not coerce the next launch into
/// a recovery wipe.
const WIPE_PENDING_MAGIC: &[u8; 4] = b"LFWP";
const WIPE_PENDING_VERSION: u8 = 1;
const WIPE_PENDING_HEADER_LEN: usize = WIPE_PENDING_MAGIC.len() + 1;

/// Every file the app writes under the app-support directory. New
/// artefacts MUST be added here so the wipe stays total. Ordered
/// from "safest to delete first" (markers, overlays) → "most
/// destructive last" (the DB itself) so a mid-wipe crash leaves the
/// user with at least a detectable "wipe was in progress" state.
///
/// Sole source of truth for what the wipe must clean up — the
/// Dart side calls into the Rust `wipe_all` driver and never
/// maintains its own filename list. Add new artefacts here when
/// any module starts writing a new file under `support_dir`;
/// `wipe::tests::registry_covers_every_known_artefact` enforces
/// coverage at the module-publish layer.
pub const MANAGED_FILES: &[&str] = &[
    // Markers / transient state
    ".tier-transition-pending",
    "keychain_enabled",
    "rate_limit_state.bin",
    // Biometric / hw overlay blobs. Filename grammar:
    //   - Android (post-Rust port): hardware_vault_android_bio.bin
    //     (matches lfs_os_security::android::hardware_vault::VAULT_FILE_BIO).
    //   - Pre-port Android filename kept here so a wipe cleans up
    //     installs that upgraded across the rename.
    //   - Apple / Windows: pre-port filename, retained until the
    //     respective ports rename their on-disk artefact.
    "hardware_vault_android_bio.bin",
    "hardware_vault_password_overlay_android.bin",
    "hardware_vault_password_overlay_apple.bin",
    "hardware_vault_password_overlay_windows.bin",
    // Password gate
    "security_pass_hash.bin",
    // Hardware vault primary blobs — one per platform
    "hardware_vault.bin",
    "hardware_vault_android.bin",
    "hardware_vault_apple.bin",
    "hardware_vault_ios.bin",
    "hardware_vault_macos.bin",
    "hardware_vault_windows.bin",
    "hardware_vault_linux.bin",
    "hardware_vault_salt.bin",
    // KDF descriptors (Argon2id params) + verifier + key
    "credentials.kdf",
    "credentials.verify",
    "credentials.key",
    // Config (active tier, modifiers, user prefs)
    "config.json",
    // Migration framework state — regenerates on next launch
    "migration_history.json",
    // Drift DB + SQLite sidecars. Last because losing these zaps the
    // session list. Ordering intentional: if the wipe crashes before
    // we get here, the user still sees a tier-less install that the
    // wizard can handle, rather than a DB under an unknown cipher.
    "letsflutssh.db",
    "letsflutssh.db-wal",
    "letsflutssh.db-shm",
    "letsflutssh.db-journal",
    // Transitional cleanup: an early Rust-port build (between
    // bf6bb95f and the filename revert at b56ccf7b) wrote the
    // SQLCipher DB to `lfs_core.db` instead of reusing the
    // drift-era `letsflutssh.db` slot. Users who installed that
    // intermediate build have a stale orphan at `lfs_core.db`
    // that the rest of the app no longer touches — but
    // `WipeAllService` never deleted it because the file name
    // wasn't on the managed list. Without this entry, every
    // post-port wipe leaves the orphan behind, and on the next
    // first-launch the SQLCipher init can collide with whatever
    // permission state Windows attaches to the abandoned file.
    // Safe to keep indefinitely — a fresh install never creates
    // `lfs_core.db`, so the entry is a pure no-op outside the
    // upgrade window. Remove once we are confident no installs
    // from the intermediate-filename window remain in the wild.
    "lfs_core.db",
    "lfs_core.db-wal",
    "lfs_core.db-shm",
    "lfs_core.db-journal",
];

/// Subset of [`MANAGED_FILES`] used at startup to detect "install has
/// prior state" when the current build also finds `config.security
/// == None`. `config.json` and `migration_history.json` are
/// excluded — both are recreated as soon as the app initialises its
/// provider graph, so counting them as state would trap the user in
/// a reset-dialog loop after every wipe. The real "orphan install"
/// signal is a KDF descriptor, a hw-vault blob, a DB file, or a
/// credentials artefact.
pub const ORPHAN_PROBE_FILES: &[&str] = &[
    ".tier-transition-pending",
    "keychain_enabled",
    "rate_limit_state.bin",
    "hardware_vault_android_bio.bin",
    "hardware_vault_password_overlay_android.bin",
    "hardware_vault_password_overlay_apple.bin",
    "hardware_vault_password_overlay_windows.bin",
    "security_pass_hash.bin",
    "hardware_vault.bin",
    "hardware_vault_android.bin",
    "hardware_vault_apple.bin",
    "hardware_vault_ios.bin",
    "hardware_vault_macos.bin",
    "hardware_vault_windows.bin",
    "hardware_vault_linux.bin",
    "hardware_vault_salt.bin",
    "credentials.kdf",
    "credentials.verify",
    "credentials.key",
    "letsflutssh.db",
    "letsflutssh.db-wal",
    "letsflutssh.db-shm",
    "letsflutssh.db-journal",
];

/// Result of a file-sweep run. The caller (Dart shim) merges this
/// with the keychain / native-vault / overlay results before
/// surfacing the final `WipeReport` to the UI.
#[derive(Debug, Clone)]
pub struct FileSweepReport {
    pub deleted_files: Vec<String>,
    pub failed_files: Vec<String>,
}

/// True when the `.wipe-pending` marker is on disk under
/// `support_dir` — the previous run started a wipe that did not
/// finish. Call sites check this on startup and re-run the service
/// before `_initSecurity`. Any I/O failure or magic / version
/// mismatch is treated as "no marker present" — a broken
/// support-dir probe must not block startup, and a foreign file at
/// the marker path must not coerce a recovery wipe.
pub fn has_pending_wipe(support_dir: &Path) -> bool {
    let path = support_dir.join(WIPE_PENDING_MARKER);
    let Ok(bytes) = crate::path::read_bytes_secure(&path) else { return false };
    if bytes.len() < WIPE_PENDING_HEADER_LEN || &bytes[..WIPE_PENDING_MAGIC.len()] != WIPE_PENDING_MAGIC {
        return false;
    }
    bytes[WIPE_PENDING_MAGIC.len()] == WIPE_PENDING_VERSION
}

/// True when **any security-bearing** managed artefact lives in the
/// app-support dir. Used at startup to detect installs whose
/// `config.security == None` predates the current schema and need a
/// user-confirmed reset.
pub fn has_any_state(support_dir: &Path) -> bool {
    ORPHAN_PROBE_FILES
        .iter()
        .any(|name| support_dir.join(name).exists())
}

/// Walk every managed file + the logs directory; return per-file
/// success / failure for the caller to surface.
///
/// Step ordering matches the Dart implementation for crash-recovery
/// parity:
///   1. Write the `.wipe-pending` marker so a mid-wipe crash leaves a
///      trace.
///   2. Drop every cached secret out of the process-singleton
///      [`crate::secrets::SecretStore`]. The Dart caller used to
///      pass a `credentialCacheEvict: VoidCallback?` hook for this,
///      which silently skipped the clear when the caller forgot to
///      pass it. Doing it here closes the gap so a wipe always
///      drops the in-RAM plaintext too — file-on-disk and
///      memory-cached state cleared in lockstep.
///   3. Best-effort delete each managed file. One stuck entry does
///      not abort the sweep — the file lands in `failed_files`.
///   4. Wipe the `logs/` subdirectory entry-by-entry. A "reset all"
///      that leaves session-name traces in logs defeats the point;
///      per-entry failure is non-fatal.
///   5. Clear the `.wipe-pending` marker.
pub fn sweep_files(support_dir: &Path) -> FileSweepReport {
    let mut deleted = Vec::new();
    let mut failed = Vec::new();

    // 1. Marker first.
    let _ = write_pending_marker(support_dir);

    // 2. SecretStore — every cached plaintext credential the running
    //    process has staged. Idempotent on an empty store.
    crate::app::instance().secrets.clear();

    // 3. Files.
    for name in MANAGED_FILES {
        let path = support_dir.join(name);
        if !path.exists() {
            continue;
        }
        match fs::remove_file(&path) {
            Ok(()) => deleted.push((*name).to_string()),
            Err(_) => failed.push((*name).to_string()),
        }
    }

    // 4. Logs.
    let _ = wipe_logs_dir(support_dir);

    // 5. Clear the marker.
    let _ = clear_pending_marker(support_dir);

    FileSweepReport {
        deleted_files: deleted,
        failed_files: failed,
    }
}

fn write_pending_marker(support_dir: &Path) -> Result<(), String> {
    crate::path::create_dir_all_secure(support_dir)?;
    let path = support_dir.join(WIPE_PENDING_MARKER);
    let now = SystemTime::now();
    let body = match now.duration_since(SystemTime::UNIX_EPOCH) {
        // The marker's load-bearing property is "magic + version
        // present" — body is an opaque breadcrumb. Unix-epoch
        // milliseconds keeps the previous diagnostic without
        // pulling a date crate.
        Ok(d) => format!("{}\n", d.as_millis()),
        Err(_) => String::from("0\n"),
    };
    let mut buf = Vec::with_capacity(WIPE_PENDING_HEADER_LEN + body.len());
    buf.extend_from_slice(WIPE_PENDING_MAGIC);
    buf.push(WIPE_PENDING_VERSION);
    buf.extend_from_slice(body.as_bytes());
    crate::path::write_bytes_atomic(&path, &buf)
}

fn clear_pending_marker(support_dir: &Path) -> Result<(), String> {
    let path = support_dir.join(WIPE_PENDING_MARKER);
    if !path.exists() {
        return Ok(());
    }
    fs::remove_file(&path).map_err(|e| format!("delete {}: {e}", path.display()))
}

fn wipe_logs_dir(support_dir: &Path) -> Result<(), String> {
    let logs = support_dir.join("logs");
    if !logs.exists() {
        return Ok(());
    }
    let entries = fs::read_dir(&logs).map_err(|e| format!("read {}: {e}", logs.display()))?;
    for entry in entries.flatten() {
        let path = entry.path();
        // Per-entry failure is non-fatal — the next entity's delete
        // still runs. We don't propagate the per-entry error; the
        // Dart logger captured it before the port and consumers
        // never branched on this detail.
        if path.is_dir() {
            let _ = fs::remove_dir_all(&path);
        } else {
            let _ = fs::remove_file(&path);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
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
    }
}
