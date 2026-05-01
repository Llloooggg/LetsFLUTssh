//! Atomic macOS `.dmg` installer — Rust port of the Dart
//! `platform/macos/installer/macos_installer.dart` module.
//!
//! Flow (each step a separate subprocess + verify):
//!
//!   1. `hdiutil attach -nobrowse -noautoopen` mounts the DMG.
//!   2. Find the `.app` inside the mounted volume.
//!   3. `rsync -a --delete` copies the `.app` to `<target>.new`.
//!   4. `hdiutil detach` releases the DMG.
//!   5. Optional re-sign via [`super::macos_signing::resign_bundle`]
//!      when a personal cert is in the keychain.
//!   6. `codesign --verify --strict` on `<target>.new` — verify
//!      failure means re-sign corrupted the bundle and we roll
//!      back to the untouched original.
//!   7. Post-resign entitlement probe — the `errSecMissingEntitlement`
//!      (-34018) trap a re-sign that silently dropped
//!      `keychain-access-groups` would create.
//!   8. Atomic rename: `<target>` → `<target>.backup`,
//!      `<target>.new` → `<target>`. The `.backup` directory
//!      sticks around as a crash-recovery trail; startup checks
//!      for it and restores if the new bundle never launched
//!      cleanly.
//!
//! Any failure before the atomic rename leaves `<target>`
//! untouched — worst outcome is a dangling `<target>.new` /
//! `.backup` in the install root, which the next successful
//! install cleans up.
//!
//! **Verification status**: same NI-2 gate as
//! [`super::macos_signing`]; the rust-cross-check matrix
//! validates source compilation against
//! `aarch64-apple-darwin` + `x86_64-apple-darwin`, runtime
//! correctness needs a real Mac install round-trip.

#![cfg(target_os = "macos")]

use std::path::{Path, PathBuf};
use std::process::Output;

use tokio::process::Command;

use super::macos_signing::{
    codesign_extract_entitlements, codesign_verify, has_identity, resign_bundle, SignError,
    DEFAULT_COMMON_NAME,
};

const HDIUTIL_PATH: &str = "/usr/bin/hdiutil";
const RSYNC_PATH: &str = "/usr/bin/rsync";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallOutcome {
    /// Bundle swapped, re-signed under the existing personal
    /// cert (if any), ready to relaunch.
    Succeeded,
    /// Atomic-swap path bailed mid-flight; target bundle is
    /// still the pre-install version.
    RolledBack,
    /// Writability or privilege barrier prevented the swap.
    /// Caller falls back to the Finder-reveal path.
    NotApplicable,
}

#[derive(Debug, thiserror::Error)]
pub enum InstallError {
    #[error("io {context}: {source}")]
    Io {
        context: &'static str,
        #[source]
        source: std::io::Error,
    },
    #[error("sign: {0}")]
    Sign(#[from] SignError),
}

/// Install `dmg_path` on top of `target_bundle`. `target_bundle`
/// is the live `.app` the running process was launched from.
pub async fn install(
    dmg_path: &Path,
    target_bundle: &Path,
) -> Result<InstallOutcome, InstallError> {
    let parent = match target_bundle.parent() {
        Some(p) => p.to_path_buf(),
        None => return Ok(InstallOutcome::NotApplicable),
    };
    if !is_writable(&parent) {
        return Ok(InstallOutcome::NotApplicable);
    }

    let mount_point =
        tempdir_in(&std::env::temp_dir(), "lfs-dmg-mount-").map_err(|e| InstallError::Io {
            context: "create mount tmp",
            source: e,
        })?;
    let staged_path = with_suffix(target_bundle, "new");
    let backup_path = with_suffix(target_bundle, "backup");

    // 1. mount
    let attach_out = run(
        HDIUTIL_PATH,
        &[
            "attach",
            "-nobrowse",
            "-noautoopen",
            "-mountpoint",
            mount_point.to_str().unwrap(),
            dmg_path.to_str().unwrap(),
        ],
    )
    .await?;
    if !attach_out.status.success() {
        let _ = std::fs::remove_dir_all(&mount_point);
        return Ok(InstallOutcome::NotApplicable);
    }

    // 2. find .app inside mount
    let mounted_app = match find_app_bundle(&mount_point) {
        Some(p) => p,
        None => {
            let _ = detach(&mount_point).await;
            let _ = std::fs::remove_dir_all(&mount_point);
            return Ok(InstallOutcome::NotApplicable);
        }
    };

    // 3. rsync into staging
    if staged_path.exists() {
        let _ = std::fs::remove_dir_all(&staged_path);
    }
    let rsync_out = run(
        RSYNC_PATH,
        &[
            "-a",
            "--delete",
            &format!("{}/", mounted_app.to_string_lossy()),
            &format!("{}/", staged_path.to_string_lossy()),
        ],
    )
    .await?;
    let _ = detach(&mount_point).await;
    let _ = std::fs::remove_dir_all(&mount_point);
    if !rsync_out.status.success() {
        if staged_path.exists() {
            let _ = std::fs::remove_dir_all(&staged_path);
        }
        return Ok(InstallOutcome::NotApplicable);
    }

    // 4. snapshot pre-resign entitlements for the post-resign
    //    probe. A CI ad-hoc bundle with `keychain-access-groups`
    //    silently dropped during re-sign is the -34018 trap we
    //    dodge: the staged bundle would pass `codesign --verify`
    //    (signature is valid) but hit `errSecMissingEntitlement`
    //    on the first T1 read.
    let pre_resign_ent = codesign_extract_entitlements(&staged_path)
        .await
        .ok()
        .flatten();

    // 5. re-sign under the user's personal cert, but only if
    //    one is installed. `has_identity` short-circuits the
    //    no-cert case so a user who declined the first-launch
    //    self-sign offer still gets silent updates — the
    //    bundle keeps its CI ad-hoc signature.
    if has_identity(DEFAULT_COMMON_NAME).await? {
        let _ = resign_bundle(&staged_path, DEFAULT_COMMON_NAME).await?;
    }

    // 6. verify the staged bundle.
    if !codesign_verify(&staged_path).await? {
        let _ = std::fs::remove_dir_all(&staged_path);
        return Ok(InstallOutcome::RolledBack);
    }

    // 7. post-resign entitlement probe — pre had ents, post
    //    doesn't = silent strip. Roll back before the atomic
    //    swap.
    if pre_resign_ent.is_some() {
        let post = codesign_extract_entitlements(&staged_path)
            .await
            .ok()
            .flatten();
        if post.is_none() {
            let _ = std::fs::remove_dir_all(&staged_path);
            return Ok(InstallOutcome::RolledBack);
        }
    }

    // 8. atomic swap. Sequence matters: move old → backup
    //    first, then new → target. If the second rename fails
    //    the user is left with `.backup` and no live `.app`,
    //    which the caller surfaces as "update broken, restore
    //    from backup".
    if backup_path.exists() {
        let _ = std::fs::remove_dir_all(&backup_path);
    }
    if let Err(e) = std::fs::rename(target_bundle, &backup_path) {
        return Err(InstallError::Io {
            context: "rename target → backup",
            source: e,
        });
    }
    if std::fs::rename(&staged_path, target_bundle).is_err() {
        // Rollback: restore old bundle, leave staging for diag.
        let _ = std::fs::rename(&backup_path, target_bundle);
        return Ok(InstallOutcome::RolledBack);
    }
    Ok(InstallOutcome::Succeeded)
}

/// Housekeeping: drop the rollback backup after the new bundle
/// has run cleanly. Caller (e.g. `main` shortly after startup)
/// runs this so a crash during early init still finds the
/// backup.
pub fn cleanup_backup(target_bundle: &Path) {
    let backup = with_suffix(target_bundle, "backup");
    if backup.exists() {
        let _ = std::fs::remove_dir_all(&backup);
    }
}

// ── Internals ──────────────────────────────────────────────────

async fn detach(mount_point: &Path) -> std::io::Result<()> {
    let _ = Command::new(HDIUTIL_PATH)
        .args(["detach", mount_point.to_str().unwrap_or(""), "-force"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .stdin(std::process::Stdio::null())
        .status()
        .await?;
    Ok(())
}

async fn run(executable: &str, args: &[&str]) -> Result<Output, InstallError> {
    Command::new(executable)
        .args(args)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .output()
        .await
        .map_err(|e| InstallError::Io {
            context: "spawn",
            source: e,
        })
}

fn find_app_bundle(mount_point: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(mount_point).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("app") {
            if let Ok(meta) = entry.metadata() {
                if meta.is_dir() {
                    return Some(path);
                }
            }
        }
    }
    None
}

fn is_writable(dir: &Path) -> bool {
    let probe = dir.join(".lfs-install-probe");
    match std::fs::write(&probe, b"x") {
        Ok(_) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_os_string();
    s.push(".");
    s.push(suffix);
    PathBuf::from(s)
}

fn tempdir_in(base: &Path, prefix: &str) -> std::io::Result<PathBuf> {
    use rand::RngCore;
    let pid = std::process::id();
    let mut rng = rand::rngs::OsRng;
    for _ in 0..16 {
        let mut bytes = [0u8; 8];
        rng.fill_bytes(&mut bytes);
        let suffix: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let candidate = base.join(format!("{prefix}{pid}-{suffix}"));
        match std::fs::create_dir(&candidate) {
            Ok(_) => {
                use std::os::unix::fs::PermissionsExt;
                let _ =
                    std::fs::set_permissions(&candidate, std::fs::Permissions::from_mode(0o700));
                return Ok(candidate);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::AlreadyExists,
        "tempdir: out of retries",
    ))
}
