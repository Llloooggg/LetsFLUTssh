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
    //   - Android: hardware_vault_android_bio.bin (matches
    //     lfs_os_security::android::hardware_vault::VAULT_FILE_BIO).
    //   - Apple / Windows: hardware_vault_password_overlay_<plat>.bin.
    // Both legacy Android filenames remain in this list — a sweep
    // must clean every name an installed user could carry on disk,
    // not only the current one. Adding a new name here is the
    // wipe-coverage tripwire (see the `every_known_artefact_is_in_managed_files`
    // test below).
    "hardware_vault_android_bio.bin",
    "hardware_vault_password_overlay_android.bin",
    "hardware_vault_password_overlay_apple.bin",
    "hardware_vault_password_overlay_linux.bin",
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
    "hardware_vault_password_overlay_linux.bin",
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
    let Ok(bytes) = crate::path::read_bytes_secure(&path) else {
        return false;
    };
    if bytes.len() < WIPE_PENDING_HEADER_LEN {
        crate::app_log_warn!(
            "Wipe",
            "pending-wipe marker present but rejected: length {len} < header {header}",
            len = bytes.len(),
            header = WIPE_PENDING_HEADER_LEN
        );
        return false;
    }
    if &bytes[..WIPE_PENDING_MAGIC.len()] != WIPE_PENDING_MAGIC {
        let prefix: Vec<u8> = bytes[..WIPE_PENDING_MAGIC.len()].to_vec();
        crate::app_log_warn!(
            "Wipe",
            "pending-wipe marker present but rejected: magic mismatch (got {prefix:?})"
        );
        return false;
    }
    if bytes[WIPE_PENDING_MAGIC.len()] != WIPE_PENDING_VERSION {
        crate::app_log_warn!(
            "Wipe",
            "pending-wipe marker present but rejected: version {found} != expected {expected}",
            found = bytes[WIPE_PENDING_MAGIC.len()],
            expected = WIPE_PENDING_VERSION
        );
        return false;
    }
    true
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
///      [`crate::secrets::SecretStore`]. Doing it here closes the
///      gap a Dart-side callback hook would leave — a wipe always
///      drops the in-RAM plaintext too, so file-on-disk and
///      memory-cached state clear in lockstep.
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
        warn_if_unexpected_perms(name, &path);
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

/// Pure diagnostics: surface managed files whose UNIX permissions
/// drift away from the `0o600` invariant the app writes them with.
/// A non-`0o600` mode means either the user copied the file in from
/// another install or a different tool wrote it — in both cases the
/// sweep still deletes the file, the warning just leaves a trail
/// for forensics. Windows skips this — POSIX `mode_t` bits do not
/// model the file's NTFS ACL.
#[cfg(unix)]
fn warn_if_unexpected_perms(name: &str, path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let Ok(meta) = fs::metadata(path) else {
        return;
    };
    let mode = meta.permissions().mode() & 0o777;
    if mode != 0 && mode != 0o600 {
        crate::app_log_warn!(
            "Wipe",
            "managed file {name} has perms {mode:o} != 0600 before delete"
        );
    }
}

#[cfg(not(unix))]
fn warn_if_unexpected_perms(_name: &str, _path: &Path) {}

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
#[path = "../../tests/unit/security_wipe.rs"]
mod tests;
